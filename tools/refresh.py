"""refresh.py -- regenerate every route and the quest data from pinned sources.

    python -I tools/refresh.py --rxp <RXPGuides clone> --att <AllTheThings clone> [--check] [--pin]

RestedXP's guides and AllTheThings change weekly. This is the one command that
rebuilds everything the addon ships from them, at the commits in
tools/pins.json, then runs both test suites and shows how each route's step
count moved:

  * every route in tools/routes.json, through tools/rxp2route.py, and the
    talent guides (data/Talents.lua) through tools/rxptalents.py
    (RestedXP Guides, CC BY-NC-SA 4.0: personal, non-commercial; credit RestedXP);
  * data/Quests.lua and companion/web/data/npcloot.json, through
    tools/att2quests.lua (AllTheThings, MIT).

--check   write into a scratch folder and compare with what is in the repo;
          nothing in the repo changes. Use it to see that the pinned commits
          reproduce today's files, or what a new commit would change.
--pin     check out the commits in pins.json in both clones first
          (git checkout; the clones must have them).
To move to newer data: update the clones, put their commits in pins.json,
run without --check, read the step-count report, then play a route.
"""
import argparse
import difflib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "ZugzugLeveler")
ROUTES = os.path.join(ADDON, "routes", "rxp")


def run(cmd, **kw):
    print("  $ " + " ".join(cmd))
    return subprocess.run(cmd, check=True, **kw)


def steps_in(path):
    """Step count of a route file: one 'act =' per step."""
    try:
        with open(path, encoding="utf-8") as f:
            return len(re.findall(r'\bact = "', f.read()))
    except OSError:
        return None


def head(clone):
    return subprocess.run(["git", "-C", clone, "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rxp", required=True, help="a clone of https://github.com/RestedXP/RXPGuides")
    ap.add_argument("--att", help="a clone of https://github.com/ATTWoWAddon/AllTheThings (quest data; skipped if not given)")
    ap.add_argument("--check", action="store_true", help="write to a scratch folder and compare; change nothing")
    ap.add_argument("--pin", action="store_true", help="check out the pinned commits first")
    ap.add_argument("--only", help="regenerate only routes whose name contains this text")
    a = ap.parse_args(argv)

    with open(os.path.join(ROOT, "tools", "pins.json"), encoding="utf-8") as f:
        pins = json.load(f)
    with open(os.path.join(ROOT, "tools", "routes.json"), encoding="utf-8") as f:
        routes = json.load(f)["routes"]

    if a.pin:
        run(["git", "-C", a.rxp, "checkout", "-q", pins["rxp"]])
        if a.att:
            run(["git", "-C", a.att, "checkout", "-q", pins["att"]])
    for clone, key in ((a.rxp, "rxp"), (a.att, "att")):
        if clone and not head(clone).startswith(pins[key][:10]):
            print("note: %s is at %s, not the pinned %s (pins.json)" % (clone, head(clone)[:10], pins[key][:10]))

    out = tempfile.mkdtemp(prefix="zug-routes-") if a.check else ROUTES
    before = {}
    for r in routes:
        if a.only and a.only not in r["name"]:
            continue
        fn = re.sub(r"[^A-Za-z0-9]+", "_", r["name"]).strip("_") + ".lua"
        before[fn] = steps_in(os.path.join(ROUTES, fn))
        cmd = [sys.executable, "-I", os.path.join(ROOT, "tools", "rxp2route.py"), a.rxp,
               "--race", r["race"], "--class", r["class"], "--name", r["name"], "--out", out]
        if r.get("faction"):
            cmd += ["--faction", r["faction"]]
        if r.get("path"):
            cmd += ["--path", r["path"]]
        run(cmd, stdout=subprocess.DEVNULL)

    talents = os.path.join(out, "Talents.lua") if a.check else os.path.join(ADDON, "data", "Talents.lua")
    run([sys.executable, "-I", os.path.join(ROOT, "tools", "rxptalents.py"), a.rxp, "--out", talents], stdout=subprocess.DEVNULL)

    # att2quests writes its two files itself: <out> and <loot out> (its arguments 3 and 4)
    data = {"Quests.lua": os.path.join(ADDON, "data", "Quests.lua"),
            "npcloot.json": os.path.join(ROOT, "companion", "web", "data", "npcloot.json")}
    if a.att:
        dest = {k: (os.path.join(out, k) if a.check else v) for k, v in data.items()}
        run(["luajit", os.path.join(ROOT, "tools", "att2quests.lua"), os.path.join(a.att, "db", "Camelot", "Categories"),
             pins["att"], dest["Quests.lua"], dest["npcloot.json"]], cwd=ROOT)

    # the report: step counts, and in --check mode which files differ
    changed = 0
    print("\nroute steps (before -> after):")
    for fn, n0 in sorted(before.items()):
        n1 = steps_in(os.path.join(out, fn))
        mark = "" if n0 == n1 else "   <- changed"
        same = True
        if a.check:
            try:
                with open(os.path.join(ROUTES, fn), encoding="utf-8") as f1, open(os.path.join(out, fn), encoding="utf-8") as f2:
                    same = f1.read() == f2.read()
            except OSError:
                same = False
            if not same and not mark:
                mark = "   <- same count, different text"
        changed += 0 if (same and n0 == n1) else 1
        print("  %-42s %5s -> %5s%s" % (fn, n0, n1, mark))
    if a.check:
        with open(os.path.join(ADDON, "data", "Talents.lua"), encoding="utf-8") as f1, open(talents, encoding="utf-8") as f2:
            same = f1.read() == f2.read()
        print("Talents.lua: %s" % ("unchanged" if same else "differs"))
        changed += 0 if same else 1
    if a.check and a.att:
        for k, v in data.items():
            with open(v, encoding="utf-8") as f1, open(os.path.join(out, k), encoding="utf-8") as f2:
                old, new = f1.read().splitlines(), f2.read().splitlines()
            diff = [d for d in difflib.unified_diff(old, new, lineterm="", n=0) if d[:1] in "+-" and d[:3] not in ("+++", "---")]
            print("%s: %s" % (k, "unchanged" if not diff else "%d lines differ" % len(diff)))
            changed += 1 if diff else 0
    print("\n%d route file(s) differ" % changed)

    if a.check:
        shutil.rmtree(out, ignore_errors=True)
        return 0 if changed == 0 else 1

    print("\ntests:")
    run(["luajit", os.path.join(ROOT, "test", "harness.lua"), ADDON])
    run(["go", "test", "./..."], cwd=os.path.join(ROOT, "companion"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
