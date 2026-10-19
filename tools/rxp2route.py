"""rxp2route.py -- convert RestedXP's Forever guides into zugzugleveler routes.

RestedXP Guides (https://github.com/RestedXP/RXPGuides) is licensed
CC BY-NC-SA 4.0. Routes this tool writes are adaptations of that work, so
they carry the same license, credit RestedXP, and are for personal,
non-commercial use. The tool reads a local clone; it never downloads.

    python -I tools/rxp2route.py <RXPGuides clone> --race Human --class Warrior
        [--faction Alliance] [--start "1-6 Northshire"] [--xprate 1]
        [--hardcore] [--out ZugzugLeveler/routes/rxp] [--name "RXP Human Warrior"]

What the RXP format means was read from RXPGuides' own source, not guessed:
  GuideLoader.lua  ParseGuide / parseLine / applies (the << filter language)
  functions.lua    .goto / .accept / .turnin / .complete / .xp argument order
  RXPGuides.lua    IsStepShown: #hardcore #softcore #season #som #xprate #ssf #ah
  GuideWindow.lua  #include Group\\Name@startLabel-endLabel
  DB/forever/db.lua  zone name -> uiMapID (addon.mapId)
"""
import argparse
import os
import re
import sys

GAME = "FOREVER"
ALLIANCE = {"Human", "Dwarf", "Gnome", "NightElf"}
HORDE = {"Orc", "Troll", "Scourge", "Tauren"}
CLASSES = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}

# --------------------------------------------------------------- filters


class Who:
    """The character the route is for -- the inputs to RXP's applies()."""

    def __init__(self, race, cls, faction, hardcore=False, ssf=False, xprate=1.0, modes=False):
        self.race = "Scourge" if race == "Undead" else race
        self.cls = cls.upper()
        self.faction = faction
        self.hardcore, self.ssf, self.xprate = hardcore, ssf, xprate
        # modes: keep RXP's hardcore/softcore/ssf/ah steps, marked (mode = "hc,ssf"),
        # for the addon to show or pass at play time (Engine.applies) instead of here
        self.modes = modes
        self.unknown = set()  # tokens we could not decide at import time

    def applies(self, text):
        """RXP's << language: '/' = OR, space = AND, '!' = NOT, (..) groups."""
        if text is None:
            return True

        def parse(t):
            def group(m):
                return "TRUEGRP" if parse(m.group(2)) != (m.group(1) == "!") else "NULL"
            t = re.sub(r"(!?)\(\s*(.*?)\s*\)", group, t)
            for alt in t.split("/"):
                ok = True
                for entry in re.findall(r"!?\w+", alt):
                    neg = entry.startswith("!")
                    e = entry.lstrip("!")
                    if not self.token(e) != neg:
                        ok = False
                        break
                if ok:
                    return True
            return False

        return parse(text)

    def token(self, e):
        if e == "TRUEGRP":
            return True
        if e == "NULL":
            return False
        if e == "Undead":
            e = "Scourge"
        up = e.upper()
        if up == "DK":
            up = "DEATHKNIGHT"
        if e.isdigit():
            # "playerLevel >= n": unknowable when importing. Assume the
            # leveling character is past it only if it is a low level.
            self.unknown.add("level " + e)
            return int(e) <= 1
        if up in ("MALE", "FEMALE"):
            self.unknown.add(up.lower())
            return True
        return (up == self.cls or e == self.race or e == self.faction
                or up == GAME or e == "enUS")


# --------------------------------------------------------------- guides

REGISTER = re.compile(r"RegisterGuide\(\s*(?:\"[^\"]*\"\s*,\s*)?\[\[(.*?)\]\]", re.S)


def strip_codes(s):
    s = re.sub(r"\|T[^|]*\|t", "", s)                  # textures
    s = re.sub(r"\|cRXP_[A-Z]+_", "", s)               # |cRXP_ENEMY_  RXP colour tokens
    s = re.sub(r"\|c[A-Za-z_]+?_", "", s)              # any other named colour token
    s = re.sub(r"\|c[0-9a-fA-F]{8}", "", s)
    s = s.replace("|r", "")
    s = re.sub(r"\[([^\]]+)\]", r"\1", s)
    return re.sub(r"\s+", " ", s).strip()


def load_guides(root, who):
    """Every Forever guide that applies to `who`, keyed (group, name)."""
    gdir = os.path.join(root, "Guides", "Forever")
    guides = {}
    for dirpath, _, files in os.walk(gdir):
        if os.sep + "dungeon" in dirpath:
            continue  # the dungeon variants are thin wrappers over the same routes
        for fn in sorted(files):
            if not fn.endswith(".lua"):
                continue
            src = open(os.path.join(dirpath, fn), encoding="utf-8").read()
            for m in REGISTER.finditer(src):
                g = parse_guide(m.group(1), who, fn)
                if g:
                    guides[(g["group"], g["name"])] = g
    return guides


def parse_guide(text, who, source):
    text = re.sub(r"--[^\r\n]*", "", text)
    head, steps, cur = {}, [], None
    skip_guide = False
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line.startswith("step"):
            m = re.search(r"<<\s*(.+)", line)
            cur = {"lines": [], "tags": {}} if (not m or who.applies(m.group(1))) else None
            if cur is not None:
                steps.append(cur)
            continue
        if cur is None and not steps:
            # header: a whole-line "<< x" filters the guide; "#tag v << x" filters the tag
            m = re.match(r"^<<\s*(.+)$", line)
            if m:
                if not who.applies(m.group(1)):
                    skip_guide = True
                continue
            m = re.match(r"^(#\S+)\s*(.*?)\s*<<\s*(.+)$", line)
            if m:
                if not who.applies(m.group(3)):
                    continue
                line = m.group(1) + " " + m.group(2)
            m = re.match(r"^#(\S+)\s*(.*)$", line)
            if m and m.group(1) not in head:
                head[m.group(1)] = m.group(2).strip()
            continue
        if cur is None:
            continue  # inside a step filtered out for this character
        m = re.search(r"\s*<<\s*(.+)$", line)
        if m:
            if not who.applies(m.group(1)):
                continue
            line = line[:m.start()].strip()
        m = re.match(r"^#(\S+)\s*(.*)$", line)
        if m:
            cur["tags"].setdefault(m.group(1), m.group(2).strip())
        else:
            cur["lines"].append(line)
    if skip_guide or "name" not in head or "group" not in head:
        return None
    return {"name": head["name"], "group": head["group"], "next": head.get("next"),
            "head": head, "steps": steps, "source": source}


# RXP's play-style tags and the mark they get in a route file (who.modes)
MODE_TAGS = (("hardcore", "hc"), ("softcore", "sc"), ("ssf", "ssf"), ("ah", "ah"))


def step_mode(step):
    """'hc,ssf' etc. for a step RXP shows only in some play styles, or None."""
    marks = [m for tag, m in MODE_TAGS if tag in step["tags"]]
    return ",".join(marks) or None


def step_shown(step, who):
    t = step["tags"]
    if "season" in t or "som" in t:
        return False
    if not who.modes:
        if "hardcore" in t and not who.hardcore:
            return False
        if "softcore" in t and who.hardcore:
            return False
        if "ssf" in t and not who.ssf:
            return False
        if "ah" in t and who.ssf:
            return False
    if "xprate" in t:
        m = re.match(r"^([<>]?)\s*(\d+\.?\d*)-?(\d*\.?\d*)", t["xprate"])
        if m:
            op, a, b = m.groups()
            lo, hi = 1.0, 4095.0
            if op == "<":
                lo, hi = 0, float(a) - 1e-4
            elif op == ">":
                lo, hi = float(a) + 1e-4, 4095.0
            else:
                lo, hi = float(a), float(b) if b else 4095.0
            if not lo <= who.xprate <= hi:
                return False
    return True


def expand(guide, guides, who, seen=None, start=None, stop=None):
    """The guide's steps with #include expanded, filtered for `who`."""
    seen = seen or set()
    out = []
    active = start is None
    for st in guide["steps"]:
        label = st["tags"].get("label")
        if not active and label == start:
            active = True
        if not active:
            continue
        inc = st["tags"].get("include")
        if inc and not inc.startswith("*"):
            grp, _, name = inc.rpartition("\\")
            grp = grp.rstrip("\\") or guide["group"]
            m = re.match(r"^(.*?)@([^@-]+)-?([^@-]*)$", name)
            s0 = s1 = None
            if m:
                name, s0, s1 = m.group(1), m.group(2), m.group(3) or None
            sub = guides.get((grp, name))
            key = (grp, name, s0, s1)
            if sub and key not in seen:
                out.extend(expand(sub, guides, who, seen | {key}, s0, s1))
            elif not sub:
                who.unknown.add("missing include " + inc)
        elif step_shown(st, who):
            out.append(st)
        if stop is not None and label == stop:
            break
    return out


def chain(guides, who, start):
    """Follow #next from the start guide; the first alternative that applies wins."""
    order, g = [], guides.get(start)
    while g and g not in order:
        order.append(g)
        nxt = g.get("next")
        g = None
        for alt in (nxt or "").split(";"):
            alt = alt.strip()
            if not alt:
                continue
            m = re.match(r"^(.*?)\s*<<\s*(.+)$", alt)
            if m:
                if not who.applies(m.group(2)):
                    continue
                alt = m.group(1)
            grp, _, name = alt.rpartition("\\")
            cand = guides.get((grp or order[-1]["group"], name.strip()))
            if cand:
                g = cand
                break
    return order


# --------------------------------------------------------------- convert

def map_ids(root):
    src = open(os.path.join(root, "DB", "forever", "db.lua"), encoding="utf-8").read()
    m = re.search(r"addon\.mapId\s*=\s*\{(.*?)\n\}", src, re.S)
    return {k: int(v) for k, v in re.findall(r'\["([^"]+)"\]\s*=\s*(\d+)', m.group(1))}


def args_of(rest):
    return [a.strip() for a in re.sub(r"\s*,\s*", ",", rest).split(",") if a.strip()]


def convert_step(st, maps, who, state):
    """One RXP step -> zero or more zugzugleveler steps."""
    if "completewith" in st["tags"] or "sticky" in st["tags"]:
        return []  # done in passing alongside other steps; never blocks progress
    opt = "optional" in st["tags"]
    state["_step"] = {}  # per-step scratch (the quest item to use)
    need, quests, other = {}, [], []
    coord, text = None, None
    waiting = []  # elements seen before any goto: they take the next one
    pts = []      # every goto in the step, in order: RXP's arrow walks these
    hints, mobs, npcs = [], [], []

    def place(e):
        # In RXP a .goto is the waypoint for the elements after it, so each
        # element takes the goto most recently above it.
        e["_c"] = coord
        if coord is None:
            waiting.append(e)
        return e

    for line in st["lines"]:
        m = re.match(r"^\.(\S+)\s*(.*?)\s*(?:>>\s*(.*))?$", line)
        if not m:
            if line.startswith(">>") or line.startswith("+"):
                t = strip_codes(line[2:] if line.startswith(">>") else line[1:])
                if t and t not in hints:
                    hints.append(t)
                if not text:
                    text = t
            continue
        cmd, rest, ltext = m.group(1), m.group(2), m.group(3)
        a = args_of(rest)
        ltext = strip_codes(ltext) if ltext else None
        if cmd == "use" and rest and "use" not in state.get("_step", {}):
            # functions.lua addon.functions.use: item ids, "id[:arg]"
            mm = re.match(r"^(\d+)", a[0]) if a else None
            if mm:
                state.setdefault("_step", {})["use"] = int(mm.group(1))
        if cmd == "mob" and rest:
            for nm in re.split(r"\s*;\s*", rest):
                nm = strip_codes(nm.lstrip("+"))
                if nm and nm not in mobs:
                    mobs.append(nm)
        elif cmd == "target" and rest:
            for nm in re.split(r"\s*;\s*", rest):
                nm = strip_codes(nm.lstrip("+"))
                if nm and nm not in npcs:
                    npcs.append(nm)
        if cmd in ("goto", "groundgoto", "flygoto"):
            # RXP's goto always takes the zone first (functions.lua: `text, zone,
            # x, y, radius`); a number is a uiMapID (map.lua GetMapInfo:
            # `addon.GetMapId(zone) or tonumber(zone)`).
            zone, nums = (a[0], a[1:]) if a else (None, [])
            zone = zone or state.get("zone")
            if zone:
                state["zone"] = zone
            if len(nums) < 2 or not zone:
                who.unknown.add("goto without a zone: " + line)
                continue
            # a typo in the guide ("-623.92.00"): skip that point, say so
            if not all(re.match(r"^-?\d+(\.\d+)?$", n) for n in nums[:2]):
                who.unknown.add("goto with a bad number: " + line)
                continue
            r = float(nums[2]) if len(nums) >= 3 and re.match(r"^\d", nums[2]) and float(nums[2]) > 0 else None
            if "/" in zone:
                # "map/continent,a,b": WORLD coordinates. RXP hands them to
                # HereBeDragons, whose (x, y) is Blizzard's world vector (y, x)
                # (HereBeDragons-2.0.lua processMap: `top, left = center:GetXY()`),
                # so a = vector y, b = vector x.
                mz, cont = zone.split("/", 1)
                mid = int(mz) if mz.isdigit() else maps.get(mz)
                coord = {"map": mid, "cont": int(cont), "wx": float(nums[1]), "wy": float(nums[0]), "r": r}
            elif zone in maps or zone.isdigit():
                mid = maps[zone] if zone in maps else int(zone)
                coord = {"map": mid, "x": float(nums[0]) / 100, "y": float(nums[1]) / 100, "r": r}
            else:
                who.unknown.add("zone not in mapId: %s" % zone)
                continue
            pts.append(coord)
            for e in waiting:
                e["_c"] = coord
            waiting.clear()
        elif cmd == "accept" and a:
            title = re.sub(r"^Accept\s+", "", ltext) if ltext else None
            quests.append(place({"act": "accept", "q": abs(int(a[0])), "title": title}))
        elif cmd == "turnin" and a:
            title = re.sub(r"^Turn in\s+", "", ltext) if ltext else None
            q = int(a[0])
            quests.append(place({"act": "turnin", "q": abs(q), "title": title, "opt": q < 0 or None}))
        elif cmd == "complete" and len(a) >= 2:
            quests.append(place({"act": "complete", "q": abs(int(a[0])), "obj": int(a[1]), "text": ltext}))
        elif cmd in ("isOnQuest", "isQuestComplete", "isQuestTurnedIn", "isQuestAvailable", "isQuestNotComplete"):
            key = {"isOnQuest": "on", "isQuestComplete": "done", "isQuestTurnedIn": "turned",
                   "isQuestAvailable": "avail", "isQuestNotComplete": "notdone"}[cmd]
            need.setdefault(key, []).extend(abs(int(x)) for x in a if re.match(r"^-?\d+$", x))
        elif cmd == "xp" and a:
            # functions.lua addon.functions.xp: `(<?)%s*(%d+)([%+%.%-]?%d*)`
            # = level, then XP: +N into the level, .f a fraction of it, -N short of it
            mm = re.match(r"^(<?)\s*(\d+)([+.\-]?\d*)", a[0].replace(" ", ""))
            if mm and mm.group(1) == "<":
                need["below"] = int(mm.group(2))
            elif mm:
                xp = float(mm.group(3)) if mm.group(3) not in ("", "+", "-", ".") else 0
                g = {"act": "note", "lvl": int(mm.group(2)), "text": ltext}
                if xp:
                    g["xp"] = int(xp) if xp == int(xp) else xp
                other.append(place(g))
        elif cmd in ("train", "trainer"):
            other.append(place({"act": "train", "text": ltext}))
        elif cmd == "home":
            other.append(place({"act": "sethearth", "text": ltext}))
        elif cmd == "hs":
            other.append(place({"act": "hearth", "text": ltext}))
        elif cmd == "fly":
            other.append(place({"act": "fly", "text": ltext or ("Fly to " + rest)}))
        if ltext and not text:
            text = ltext
    out = []
    turned = []
    for q in quests:
        # An accept listed after turn-ins in the same RXP step is usually their
        # follow-up (Wild Eyes -> Return to Quinn (Again)); RXP itself learns
        # prerequisites from Questie's database, which we may not use, so the
        # step's own grouping is the signal. The engine passes the accept only
        # when every one of these quests is one you do not have.
        if q["act"] == "accept" and turned:
            q["after"] = list(turned)
        if q["act"] == "turnin":
            turned.append(q["q"])
        out.append(q)
    if not quests:
        if other:
            o = other[0]
            o["text"] = o.get("text") or text
            out.append(o)
        elif coord:
            out.append({"act": "goto", "text": text, "_c": coord})
    mode = step_mode(st) if who.modes else None
    for s in out:
        if mode:
            s["mode"] = mode
        c = s.pop("_c", None)
        if c:
            for k in ("map", "cont", "wx", "wy", "x", "y"):
                if c.get(k) is not None:
                    s[k] = round(c[k], 4) if isinstance(c[k], float) else c[k]
            if c["r"] and s["act"] in ("goto", "fly", "hearth"):
                s["r"] = c["r"]
        if need:
            s["need"] = need
        if opt and s["act"] in ("complete", "turnin"):
            s["opt"] = True
        # sub-objective guidance: the chain of points RXP's arrow walks, whether
        # the step loops it (#loop: a hunting circuit), what the guide says to do,
        # and who to kill / talk to.
        if len(pts) > 1:
            s["path"] = [point(p) for p in pts]
            if "loop" in st["tags"]:
                s["loop"] = True
        hint = next((h for h in hints if not h.lower().startswith(("talk to", "accept ", "turn in "))), None)
        if hint and s["act"] in ("complete", "goto", "note"):
            s["hint"] = hint[:140]
        if mobs and s["act"] == "complete":
            s["mobs"] = mobs[:4]
        if npcs and s["act"] in ("accept", "turnin", "train"):
            s["npc"] = npcs[0]
        if state["_step"].get("use") and s["act"] in ("complete", "goto", "note"):
            s["use"] = state["_step"]["use"]
        for k in [k for k, v in s.items() if v is None]:
            del s[k]
    return out


def point(c):
    """A path point: the same position fields a step has, plus its radius."""
    p = {k: (round(c[k], 4) if isinstance(c[k], float) else c[k])
         for k in ("map", "cont", "wx", "wy", "x", "y") if c.get(k) is not None}
    if c.get("r"):
        p["r"] = c["r"]
    return p


# --------------------------------------------------------------- output

def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return ("%.4f" % v).rstrip("0").rstrip(".") if v != int(v) else str(int(v))
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "{ " + ", ".join(lua(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join("%s = %s" % (k, lua(v[k])) for k in sorted(v)) + " }"
    raise TypeError(v)


KEYS = ["act", "q", "obj", "title", "text", "hint", "npc", "mobs", "use", "map", "x", "y", "cont", "wx", "wy", "r", "lvl", "xp", "opt", "mode", "need", "after", "loop", "path"]


def write_route(path, name, steps, guides_used, commit, who, sections=()):
    lines = [
        "-- %s -- generated by tools/rxp2route.py; do not edit by hand, re-run the tool." % os.path.basename(path),
        "--",
        "-- Adapted from RestedXP Guides, https://github.com/RestedXP/RXPGuides",
        "-- (commit %s): %s." % (commit, "; ".join(guides_used)),
        "-- Licensed CC BY-NC-SA 4.0, https://creativecommons.org/licenses/by-nc-sa/4.0/",
        "-- Changes: converted to the zugzugleveler step format for %s %s (%s); text shortened."
        % (who.race, who.cls.title(), who.faction),
        "-- Personal, non-commercial use only. Credit: RestedXP.",
        "",
        "local _, ns = ...",
        "-- only for its race and class (Route.Skip), so 50 routes do not all sit in memory",
        "if ns.Route.Skip and ns.Route.Skip(%s, %s) then return end" % (lua(who.race), lua(who.cls.upper())),
        "",
        "ns.Route.Register({",
        "  name = %s," % lua(name),
        "  faction = %s," % lua(who.faction),
        "  credit = \"RestedXP Guides (CC BY-NC-SA 4.0)\",",
        "  sections = { " + ", ".join("{ from = %d, name = %s }" % (s["from"], lua(s["name"])) for s in sections) + " },",
        "  steps = {",
    ]
    for s in steps:
        parts = ["%s = %s" % (k, lua(s[k])) for k in KEYS if k in s]
        lines.append("    { " + ", ".join(parts) + " },")
    lines += ["  },", "})", ""]
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def write_index(out):
    """routes.xml: every route file in `out`, so the TOC never needs editing."""
    files = sorted(f for f in os.listdir(out) if f.endswith(".lua"))
    body = "\n".join('    <Script file="%s"/>' % f for f in files)
    with open(os.path.join(out, "routes.xml"), "w", encoding="utf-8", newline="\n") as f:
        f.write('<Ui xmlns="http://www.blizzard.com/wow/ui/">\n'
                "    <!-- generated by tools/rxp2route.py: RestedXP Guides, CC BY-NC-SA 4.0 -->\n"
                + body + "\n</Ui>\n")


def git_commit(root):
    head = os.path.join(root, ".git", "HEAD")
    try:
        ref = open(head).read().strip()
        if ref.startswith("ref:"):
            ref = open(os.path.join(root, ".git", ref[5:])).read().strip()
        return ref[:10]
    except OSError:
        return "unknown"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("rxp", help="path to a local clone of RestedXP/RXPGuides")
    ap.add_argument("--race", required=True, help="Human Dwarf Gnome NightElf Orc Troll Undead Tauren Skyborne")
    ap.add_argument("--class", dest="cls", required=True)
    ap.add_argument("--faction", help="Alliance/Horde (needed for Skyborne)")
    ap.add_argument("--start", help="first guide name, e.g. '1-6 Northshire' (default: the guide marked #defaultfor your race)")
    ap.add_argument("--path", help="guides to take in order, ';'-separated; #next is followed after the last "
                    "(e.g. '1-6 Tirisfal Glades;6-12 Tirisfal Glades;12-14 Silverpine Forest;12-17 The Barrens AoE')")
    ap.add_argument("--xprate", type=float, default=1.0, help="RXP's XP-rate setting (default 1)")
    ap.add_argument("--hardcore", action="store_true", help="bake in hardcore (by default its steps are kept, marked, for the addon's option)")
    ap.add_argument("--ssf", action="store_true", help="bake in self-found (by default its steps are kept, marked)")
    ap.add_argument("--name", help="route name (default 'RXP <race> <class>')")
    ap.add_argument("--out", default=os.path.join("ZugzugLeveler", "routes", "rxp"))
    a = ap.parse_args(argv)

    race = "Scourge" if a.race == "Undead" else a.race
    faction = a.faction or ("Alliance" if race in ALLIANCE else "Horde" if race in HORDE else None)
    if not faction:
        ap.error("--faction is required for race %s" % a.race)
    if a.cls.upper() not in CLASSES:
        ap.error("unknown class %s" % a.cls)
    # no --hardcore/--ssf: keep those steps, marked, so one route serves every play style
    who = Who(race, a.cls, faction, a.hardcore, a.ssf, a.xprate, modes=not (a.hardcore or a.ssf))

    guides = load_guides(a.rxp, who)
    maps = map_ids(a.rxp)
    if a.start:
        cands = [k for k in guides if k[1] == a.start]
    else:
        cands = [k for k, g in guides.items()
                 if g["head"].get("defaultfor") and who.applies(g["head"]["defaultfor"])
                 and re.match(r"^1-", g["name"])]
    cands.sort(key=lambda k: ("ADV" in k[1] or "AoE" in k[1], k))  # plain speedrun route before the Mage AoE variants
    if not cands:
        sys.exit("no starting guide for %s %s; pass --start (guides: %s)"
                 % (a.race, a.cls, ", ".join(sorted(n for _, n in guides))))
    if a.path:
        order = []
        for nm in [n.strip() for n in a.path.split(";") if n.strip()]:
            hit = [k for k in guides if k[1] == nm]
            if not hit:
                sys.exit("no guide named %r for this character" % nm)
            order.append(guides[hit[0]])
        for g in chain(guides, who, (order[-1]["group"], order[-1]["name"]))[1:]:
            if g not in order:
                order.append(g)
    else:
        order = chain(guides, who, cands[0])

    steps, used, state, sections = [], [], {}, []
    for g in order:
        used.append("%s\\%s" % (g["group"], g["name"]))
        first = len(steps) + 1
        for st in expand(g, guides, who):
            steps.extend(convert_step(st, maps, who, state))
        if len(steps) >= first:
            # which RXP guide each stretch of steps comes from: the addon's
            # "why" names it ("RestedXP's 12-17 The Barrens AoE, from step 330")
            sections.append({"from": first, "name": g["name"]})

    name = a.name or "RXP %s %s" % (a.race, a.cls.title())
    os.makedirs(a.out, exist_ok=True)
    fn = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_") + ".lua"
    path = os.path.join(a.out, fn)
    write_route(path, name, steps, used, git_commit(a.rxp), who, sections)
    write_index(a.out)

    counts = {}
    for s in steps:
        counts[s["act"]] = counts.get(s["act"], 0) + 1
    print("wrote %s: %d steps from %d guides" % (path, len(steps), len(order)))
    print("  guides: " + " -> ".join(g["name"] for g in order))
    print("  steps:  " + ", ".join("%s %d" % kv for kv in sorted(counts.items())))
    for u in sorted(who.unknown):
        print("  note:   " + u)
    return path


if __name__ == "__main__":
    main()
