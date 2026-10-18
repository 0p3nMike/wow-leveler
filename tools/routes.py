"""routes.py -- read recorded runs out of SavedVariables and report on them.

    python -I tools/routes.py <path to WTF/Account/<ACCOUNT>/SavedVariables/ZugzugLeveler.lua>
        [--run N] [--report out.md] [--route out.lua --name "My route"]

With no --run it lists the runs. With --run N it prints a markdown report:
per-level time and XP/hour, time per zone, kill vs quest XP, deaths, flights,
and the longest stretches with no XP (where a route loses time). --route also
writes run N as a routes/*.lua file (same steps as /lev route fromrun in game).

Python stdlib only. The SavedVariables file is plain Lua table syntax, parsed
here by a small reader (strings, numbers, booleans, nil, nested tables).
"""
import argparse
import re
import sys
from collections import OrderedDict

# --------------------------------------------------------------- lua reader

TOKEN = re.compile(r'''\s*(?:
    (?P<str>"(?:[^"\\]|\\.)*")|
    (?P<num>-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|
    (?P<word>[A-Za-z_][A-Za-z0-9_]*)|
    (?P<sym>[{}\[\]=,;])|
    (?P<comment>--[^\n]*)
)''', re.X)

ESC = {"n": "\n", "t": "\t", "r": "\r", "\\": "\\", '"': '"', "'": "'", "\n": "\n"}


def tokens(src):
    pos = 0
    while pos < len(src):
        m = TOKEN.match(src, pos)
        if not m or m.end() == pos:
            if src[pos:].strip() == "":
                return
            raise ValueError("cannot read SavedVariables at offset %d: %r" % (pos, src[pos:pos + 40]))
        pos = m.end()
        kind = m.lastgroup
        if kind == "comment":
            continue
        yield kind, m.group(kind)


def unquote(s):
    body = s[1:-1]
    out, i = [], 0
    while i < len(body):
        c = body[i]
        if c == "\\" and i + 1 < len(body):
            n = body[i + 1]
            if n.isdigit():
                d = re.match(r"\d{1,3}", body[i + 1:]).group(0)
                out.append(chr(int(d)))
                i += 1 + len(d)
                continue
            out.append(ESC.get(n, n))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


class Reader:
    def __init__(self, src):
        self.toks = list(tokens(src))
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else (None, None)

    def take(self, want=None):
        t = self.peek()
        if want and t[1] != want:
            raise ValueError("expected %s, got %r" % (want, t))
        self.i += 1
        return t

    def value(self):
        kind, v = self.take()
        if kind == "str":
            return unquote(v)
        if kind == "num":
            f = float(v)
            return int(f) if f.is_integer() and "." not in v and "e" not in v.lower() else f
        if kind == "word":
            return {"true": True, "false": False, "nil": None}.get(v, v)
        if v == "{":
            return self.table()
        raise ValueError("unexpected %r" % v)

    def table(self):
        arr, d, n = [], OrderedDict(), 0
        while self.peek()[1] != "}":
            kind, v = self.peek()
            if v == "[":
                self.take()
                key = self.value()
                self.take("]")
                self.take("=")
                d[key] = self.value()
            elif kind == "word" and self.toks[self.i + 1][1] == "=":
                self.take()
                self.take("=")
                d[v] = self.value()
            else:
                n += 1
                d[n] = self.value()
            if self.peek()[1] in (",", ";"):
                self.take()
        self.take("}")
        # an array-shaped table becomes a list
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[k] for k in range(1, len(d) + 1)]
        return dict(d) if d else arr

    def assignments(self):
        out = {}
        while self.peek()[0]:
            name = self.take()[1]
            self.take("=")
            out[name] = self.value()
        return out


def load(path):
    return Reader(open(path, encoding="utf-8").read()).assignments()


# --------------------------------------------------------------- report

def fmt_time(s):
    s = int(s)
    if s >= 3600:
        return "%dh %02dm" % (s // 3600, (s % 3600) // 60)
    if s >= 60:
        return "%dm %02ds" % (s // 60, s % 60)
    return "%ds" % s


def run_label(i, r):
    secs = (r.get("stopped") or r["ev"][-1]["t"] if r.get("ev") else r["started"]) - r["started"]
    return "#%d %s %s lvl %s-%s, %d events, %s%s" % (
        i, r.get("name") or "", r.get("char", "?"), r.get("startLevel", "?"), r.get("endLevel", "now"),
        len(r.get("ev", [])), fmt_time(secs), "" if r.get("stopped") else " (still recording)")


def report(r, gap=180):
    ev = r.get("ev", [])
    if not ev:
        return "run has no events\n"
    t0, t1 = r["started"], r.get("stopped") or ev[-1]["t"]
    lines = ["# Run: %s" % (r.get("name") or r.get("char", "?")), "",
             "- character: %s (%s %s), XP preset: %s" % (r.get("char"), r.get("race"), r.get("class"), r.get("preset") or "unknown"),
             "- levels %s to %s in %s" % (r.get("startLevel"), r.get("endLevel") or "?", fmt_time(t1 - t0)), ""]

    quest_xp = sum(e.get("gain") or 0 for e in ev if e["e"] == "turnin")
    kill_xp = sum(e.get("gain") or 0 for e in ev if e["e"] == "xp")
    total = quest_xp + kill_xp
    lines += ["## XP", "",
              "| source | XP | share |", "|---|---:|---:|",
              "| quests | %d | %d%% |" % (quest_xp, 100 * quest_xp / total if total else 0),
              "| kills/other | %d | %d%% |" % (kill_xp, 100 * kill_xp / total if total else 0),
              "| **total** | **%d** | %s/h |" % (total, int(total / max(t1 - t0, 1) * 3600)), ""]

    # per level
    lines += ["## Time per level", "", "| level | time | XP/h |", "|---:|---:|---:|"]
    lvl_start, cur_lvl, xp_in = t0, r.get("startLevel"), 0
    for e in ev:
        if e["e"] in ("turnin", "xp"):
            xp_in += e.get("gain") or 0
        if e["e"] == "level":
            dt = e["t"] - lvl_start
            lines.append("| %s | %s | %d |" % (cur_lvl, fmt_time(dt), xp_in / max(dt, 1) * 3600))
            lvl_start, cur_lvl, xp_in = e["t"], e.get("lvl"), 0
    lines.append("")

    # per zone
    zones, last_zone, last_t = OrderedDict(), None, t0
    for e in ev + [{"t": t1, "e": "end"}]:
        if e["e"] in ("zone", "end"):
            if last_zone:
                zones[last_zone] = zones.get(last_zone, 0) + e["t"] - last_t
            last_zone, last_t = e.get("note") or last_zone, e["t"]
    lines += ["## Time per zone", "", "| zone | time |", "|---|---:|"]
    lines += ["| %s | %s |" % (z, fmt_time(s)) for z, s in sorted(zones.items(), key=lambda kv: -kv[1])]
    lines.append("")

    # dry spells: stretches with no XP at all
    xp_times = [t0] + [e["t"] for e in ev if e["e"] in ("turnin", "xp")] + [t1]
    gaps = sorted(((b - a, a) for a, b in zip(xp_times, xp_times[1:]) if b - a >= gap), reverse=True)[:10]
    lines += ["## Longest stretches without XP (over %s)" % fmt_time(gap), ""]
    if not gaps:
        lines.append("none")
    for dur, at in gaps:
        near = [e for e in ev if at <= e["t"] <= at + dur and e["e"] not in ("xp",)]
        what = ", ".join(sorted({e["e"] for e in near})) or "nothing recorded"
        lines.append("- %s starting %s into the run (%s)" % (fmt_time(dur), fmt_time(at - t0), what))
    lines.append("")

    # downtime (Downtime.lua writes run.time[zone][state] while recording)
    times = r.get("time") or {}
    if times:
        states = ["combat", "drink", "move", "flight", "idle", "dead"]
        lines += ["## Where the time went", "",
                  "| zone | " + " | ".join(states) + " |", "|---|" + "---:|" * len(states)]
        for zone, st in sorted(times.items(), key=lambda kv: -sum(kv[1].values())):
            tot = sum(st.values()) or 1
            lines.append("| %s | " % zone + " | ".join(
                "%s (%d%%)" % (fmt_time(st.get(s, 0)), 100 * st.get(s, 0) / tot) if st.get(s) else "" for s in states) + " |")
        lines.append("")

    deaths = [e for e in ev if e["e"] == "death"]
    flights = [e for e in ev if e["e"] == "fly"]
    lines += ["## Other", "", "- deaths: %d" % len(deaths), "- flights: %d" % len(flights),
              "- quests: %d accepted, %d turned in, %d abandoned" % (
                  sum(e["e"] == "accept" for e in ev), sum(e["e"] == "turnin" for e in ev),
                  sum(e["e"] == "abandon" for e in ev)), ""]
    return "\n".join(lines)


def to_route(r, name):
    """Same conversion as Route.FromRun in Route.lua."""
    titles = {e["q"]: e.get("title") for e in r["ev"] if e["e"] == "accept" and e.get("q")}
    abandoned = {e["q"] for e in r["ev"] if e["e"] == "abandon" and e.get("q")}
    steps = []
    for e in r["ev"]:
        base = {k: e[k] for k in ("map", "x", "y") if e.get(k) is not None}
        if e["e"] == "accept" and e["q"] not in abandoned:
            steps.append(dict(act="accept", q=e["q"], title=titles.get(e["q"]), **base))
        elif e["e"] == "done" and e["q"] not in abandoned:
            steps.append(dict(act="complete", q=e["q"], title=titles.get(e["q"]) or e.get("title"), **base))
        elif e["e"] == "turnin":
            steps.append(dict(act="turnin", q=e["q"], title=titles.get(e["q"]), **base))
        elif e["e"] == "sethearth":
            steps.append(dict(act="sethearth", text=e.get("note"), **base))
        elif e["e"] == "mark":
            steps.append(dict(act="note", text=e.get("note"), **base))
    keys = ["act", "q", "title", "text", "map", "x", "y"]

    def lit(v):
        if isinstance(v, str):
            return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
        if isinstance(v, float):
            return "%.4f" % v
        return str(v)

    out = ["local _, ns = ...", "", "ns.Route.Register({", "  name = %s," % lit(name), "  steps = {"]
    for s in steps:
        out.append("    { " + ", ".join("%s = %s" % (k, lit(s[k])) for k in keys if s.get(k) is not None) + " },")
    out += ["  },", "})", ""]
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("saved", help="SavedVariables/ZugzugLeveler.lua")
    ap.add_argument("--run", type=int)
    ap.add_argument("--report", help="write the report here instead of stdout")
    ap.add_argument("--route", help="write run N as a routes/*.lua file")
    ap.add_argument("--name", help="route name for --route")
    a = ap.parse_args(argv)

    db = load(a.saved).get("ZugzugLevelerDB") or {}
    runs = db.get("runs") or []
    if not a.run:
        if not runs:
            print("no runs recorded yet (/lev rec start in game)")
        for i, r in enumerate(runs, 1):
            print(run_label(i, r))
        return
    if not 1 <= a.run <= len(runs):
        sys.exit("no run #%d (have %d)" % (a.run, len(runs)))
    r = runs[a.run - 1]
    text = report(r)
    if a.report:
        open(a.report, "w", encoding="utf-8").write(text)
        print("wrote " + a.report)
    else:
        print(text)
    if a.route:
        open(a.route, "w", encoding="utf-8", newline="\n").write(to_route(r, a.name or r.get("name") or "run %d" % a.run))
        print("wrote " + a.route)


if __name__ == "__main__":
    main()
