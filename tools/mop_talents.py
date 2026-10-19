"""Mists of Pandaria Classic talent builds and glyphs, from wowsims/mop (MIT).

    python -I tools/mop_talents.py <wowsims/mop checkout>

Reads, from github.com/wowsims/mop (MIT License, Copyright (c) 2022 wowsims team):
  ui/sim/talents/trees/<class>.json   the 6 x 3 talent grid (fancyName, rowIdx, colIdx, spellId)
  ui/specs/<class>/<spec>/presets/talents/*.talents.json
                                      a build: talentsString (one digit per tier, the
                                      column 1-3, 0 = none) and six glyphs by name
  proto/<class>.proto                 glyph enums: name = glyph item ID
  assets/database/db.json glyphIds    glyph item ID -> the glyph's spell ID
                                      (what GetGlyphSocketInfo reports in game)
Writes:
  ZugzugLeveler/data/Talents_Mists.lua    ns.TalentDataMists, for Talents.lua on Mists
  companion/web/data/mists/talents.json   the same, for the page
The builds are wowsims' level-90 PvE presets (raid sims): the talent tiers are
the same at any level; the choice is for raiding, not PvP or leveling.
Tier unlock levels: Blizzard's CLASS_TALENT_LEVELS (Blizzard_FrameXMLBase/Classic/
Constants.lua, 5.5.4): 15 30 45 60 75 90, death knights 56 57 58 60 75 90.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def git_head(path):
    import subprocess
    r = subprocess.run(["git", "-C", str(path), "rev-parse", "HEAD"], capture_output=True, text=True)
    return r.stdout.strip() or "unknown"
TOKEN = {"death_knight": "DEATHKNIGHT", "druid": "DRUID", "hunter": "HUNTER", "mage": "MAGE", "monk": "MONK",
         "paladin": "PALADIN", "priest": "PRIEST", "rogue": "ROGUE", "shaman": "SHAMAN", "warlock": "WARLOCK",
         "warrior": "WARRIOR"}
PROTO_PREFIX = {"death_knight": "DeathKnight", "druid": "Druid", "hunter": "Hunter", "mage": "Mage", "monk": "Monk",
                "paladin": "Paladin", "priest": "Priest", "rogue": "Rogue", "shaman": "Shaman", "warlock": "Warlock",
                "warrior": "Warrior"}
LEVELS = {"DEFAULT": [15, 30, 45, 60, 75, 90], "DEATHKNIGHT": [56, 57, 58, 60, 75, 90]}


def words(camel):
    """GlyphOfSplittingIce -> Glyph of Splitting Ice"""
    w = re.sub(r"(?<!^)(?=[A-Z])", " ", camel).split()
    return " ".join(x.lower() if x in ("Of", "The", "A", "An", "And") and i > 0 else x for i, x in enumerate(w))


def glyph_enums(proto, prefix):
    out = {}
    for kind in ("Major", "Minor"):
        m = re.search(r"enum\s+%s%sGlyph\s*\{(.*?)\}" % (prefix, kind), proto, re.S)
        if not m:
            continue
        for name, val in re.findall(r"(\w+)\s*=\s*(\d+)\s*;", m.group(1)):
            if int(val):
                out[name] = int(val)
    return out


def lua(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(("%s=" % k if re.match(r"^[A-Za-z_]\w*$", k) else "[%s]=" % json.dumps(k)) + lua(x) for k, x in v.items()) + "}"
    raise TypeError(v)


def main():
    ws = pathlib.Path(sys.argv[1])
    commit = (ws / "COMMIT").read_text().strip() if (ws / "COMMIT").exists() else git_head(ws)
    db = json.loads((ws / "assets" / "database" / "db.json").read_text(encoding="utf-8"))
    spell_of = {g["itemId"]: g["spellId"] for g in db.get("glyphIds", [])}
    data = {}
    for cls, token in TOKEN.items():
        tree = json.loads((ws / "ui" / "sim" / "talents" / "trees" / f"{cls}.json").read_text(encoding="utf-8"))
        tiers = [[None, None, None] for _ in range(6)]
        for t in tree["talents"]:
            loc = t["location"]
            tiers[loc["rowIdx"]][loc["colIdx"]] = {"name": t["fancyName"], "spell": t.get("spellId")}
        glyphs = glyph_enums((ws / "proto" / f"{cls}.proto").read_text(encoding="utf-8"), PROTO_PREFIX[cls])
        builds = []
        for f in sorted((ws / "ui" / "specs" / cls).glob("*/presets/talents/*.talents.json")):
            spec = f.parts[-4].replace("_", " ").title()
            d = json.loads(f.read_text(encoding="utf-8"))
            g = d.get("glyphs") or {}
            b = {"spec": spec, "name": d.get("name") or f.stem.title(), "talents": d.get("talentsString", ""),
                 "major": [], "minor": []}
            for slot in ("major1", "major2", "major3", "minor1", "minor2", "minor3"):
                n = g.get(slot)
                if not n:
                    continue
                # a preset names a glyph (GlyphOfSplittingIce) or gives its item ID
                if isinstance(n, int):
                    item = n
                    n = next((k for k, v in glyphs.items() if v == item), None)
                else:
                    item = glyphs.get(n)
                b[slot[:5]].append({"name": words(n) if n else f"glyph item {item}", "item": item, "spell": spell_of.get(item)})
            builds.append(b)
        data[token] = {"levels": LEVELS.get(token, LEVELS["DEFAULT"]), "tiers": tiers, "builds": builds}
    src = f"wowsims/mop {commit} (github.com/wowsims/mop, MIT License, Copyright (c) 2022 wowsims team)"
    out = ROOT / "companion" / "web" / "data" / "mists" / "talents.json"
    out.write_text(json.dumps({"source": src, "classes": data}, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    lines = ["-- Talents_Mists.lua -- generated by tools/mop_talents.py; do not edit by hand, re-run the tool.",
             f"-- Mists of Pandaria talent tiers, wowsims' level-90 PvE builds and their glyphs, from {src}.",
             "-- tiers[t][column] = { name, spell }; a build's talents: one digit per tier (column, 0 = none).",
             "", "local _, ns = ...", "", "ns.TalentDataMists = {"]
    for token in sorted(data):
        lines.append("%s=%s," % (token, lua(data[token])))
    lines.append("}")
    lua_out = ROOT / "ZugzugLeveler" / "data" / "Talents_Mists.lua"
    lua_out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    nb = sum(len(v["builds"]) for v in data.values())
    print(f"{len(data)} classes, {nb} builds -> {out} and {lua_out}")


if __name__ == "__main__":
    main()
