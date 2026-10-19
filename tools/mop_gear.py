"""Mists of Pandaria Classic gear data for the companion page's Gear tab.

    python -I tools/mop_gear.py <wowsims/mop checkout> <RXPGuides checkout>

Writes companion/web/data/mists/:
  items.json    the quest reward items of ZugzugLeveler/data/Quests_Mists.lua (rw,
                from AllTheThings) with their stats, from wowsims/mop's item
                database (assets/database/db.json + leftover_db.json, MIT,
                github.com/wowsims/mop), in the shape the addon saves an item
                (Export.lua E.item): id, name, q, ilvl, loc (INVTYPE_*), cid / sc
                (Enum.ItemClass / Enum.ItemArmorSubclass / ItemWeaponSubclass),
                stats keyed like C_Item.GetItemStats (ITEM_MOD_*_SHORT), icon.
  weights.json  stat weight sets, same format as data/weights.json:
                  RestedXP's MoP leveling weights (DB/mop/statWeights.lua,
                  CC BY-NC-SA 4.0; levels 1-84, the classes and specs RestedXP has)
                  wowsims' per-spec EP presets (ui/specs/*/*/presets/ep, MIT;
                  level-90 raid weights, offered at every level as the fallback)
Stat names are unified to the page's: RestedXP's file mixes ITEM_MOD_HASTE /
ITEM_MOD_EXPERTISE_RATING / ITEM_MOD_SPELL_POWER with _SHORT names, and the
game reports some without _SHORT (gear.js canon does the same for the game's).
wowsims' enums are from its proto/common.proto (Stat, ItemType, ArmorType,
WeaponType, HandType, RangedWeaponType).
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
OUT = ROOT / "companion" / "web" / "data" / "mists"

# proto/common.proto enum Stat -> the page's stat keys
STAT = {
    0: "ITEM_MOD_STRENGTH_SHORT", 1: "ITEM_MOD_AGILITY_SHORT", 2: "ITEM_MOD_STAMINA_SHORT",
    3: "ITEM_MOD_INTELLECT_SHORT", 4: "ITEM_MOD_SPIRIT_SHORT", 5: "ITEM_MOD_HIT_RATING_SHORT",
    6: "ITEM_MOD_CRIT_RATING_SHORT", 7: "ITEM_MOD_HASTE_RATING_SHORT", 8: "ITEM_MOD_EXPERTISE_RATING_SHORT",
    9: "ITEM_MOD_DODGE_RATING_SHORT", 10: "ITEM_MOD_PARRY_RATING_SHORT", 11: "ITEM_MOD_MASTERY_RATING_SHORT",
    12: "ITEM_MOD_ATTACK_POWER_SHORT", 13: "ITEM_MOD_RANGED_ATTACK_POWER_SHORT", 14: "STAT_SPELLDAMAGE",
    15: "ITEM_MOD_RESILIENCE_RATING_SHORT", 16: "ITEM_MOD_PVP_POWER_SHORT", 17: "RESISTANCE0_NAME",
    18: "ITEM_MOD_EXTRA_ARMOR_SHORT", 21: "ITEM_MOD_POWER_REGEN0_SHORT",
}
# the EP preset names (StatIntellect ...) -> the same keys; PseudoStat weapon DPS
EP_NAME = {"Stat" + n: k for n, k in {
    "Strength": STAT[0], "Agility": STAT[1], "Stamina": STAT[2], "Intellect": STAT[3], "Spirit": STAT[4],
    "HitRating": STAT[5], "CritRating": STAT[6], "HasteRating": STAT[7], "ExpertiseRating": STAT[8],
    "DodgeRating": STAT[9], "ParryRating": STAT[10], "MasteryRating": STAT[11], "AttackPower": STAT[12],
    "RangedAttackPower": STAT[13], "SpellPower": STAT[14], "PvpResilienceRating": STAT[15],
    "PvpPowerRating": STAT[16], "Armor": STAT[17], "BonusArmor": STAT[18], "MP5": STAT[21]}.items()}
EP_NAME.update({"PseudoStatMainHandDps": "ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
                "PseudoStatOffHandDps": "ITEM_MOD_DAMAGE_PER_SECOND_SHORT_OH",
                "PseudoStatRangedDps": "ITEM_MOD_DAMAGE_PER_SECOND_SHORT_RANGED"})

# ItemType -> INVTYPE (weapons and ranged by hand / kind below)
ITYPE = {1: "INVTYPE_HEAD", 2: "INVTYPE_NECK", 3: "INVTYPE_SHOULDER", 4: "INVTYPE_CLOAK", 5: "INVTYPE_CHEST",
         6: "INVTYPE_WRIST", 7: "INVTYPE_HAND", 8: "INVTYPE_WAIST", 9: "INVTYPE_LEGS", 10: "INVTYPE_FEET",
         11: "INVTYPE_FINGER", 12: "INVTYPE_TRINKET"}
# WeaponType + one/two hand -> Enum.ItemWeaponSubclass (gear.js W)
ONE = {1: 0, 2: 15, 3: 13, 4: 4, 6: 6, 8: 10, 9: 7}   # axe, dagger, fist, mace, polearm, staff, sword
TWO = {1: 1, 3: 13, 4: 5, 6: 6, 8: 10, 9: 8}
RANGED = {1: (2, "INVTYPE_RANGED"), 2: (18, "INVTYPE_RANGEDRIGHT"), 3: (3, "INVTYPE_RANGEDRIGHT"),
          5: (16, "INVTYPE_THROWN"), 6: (19, "INVTYPE_RANGEDRIGHT")}


def convert_item(it):
    opt = (it.get("scalingOptions") or {}).get("0") or {}
    t = it.get("type", 0)
    out = {"id": it["id"], "name": it.get("name"), "q": it.get("quality"), "ilvl": opt.get("ilvl"), "icon": it.get("icon")}
    if t in ITYPE:
        out["loc"] = ITYPE[t]
        out["cid"] = 4
        out["sc"] = it.get("armorType", 0) if t not in (2, 11, 12) else 0
        if t == 4:
            out["sc"] = 1  # cloaks are cloth
    elif t == 13:
        wt, hand = it.get("weaponType", 0), it.get("handType", 0)
        if wt == 7:
            out.update(loc="INVTYPE_SHIELD", cid=4, sc=6)
        elif wt == 5:
            out.update(loc="INVTYPE_HOLDABLE", cid=4, sc=0)
        else:
            two = hand == 4
            out["loc"] = {1: "INVTYPE_WEAPONMAINHAND", 2: "INVTYPE_WEAPON", 3: "INVTYPE_WEAPONOFFHAND", 4: "INVTYPE_2HWEAPON"}.get(hand, "INVTYPE_WEAPON")
            out["cid"] = 2
            out["sc"] = (TWO if two else ONE).get(wt)
    elif t == 14:
        sc, loc = RANGED.get(it.get("rangedWeaponType", 0), (None, "INVTYPE_RANGED"))
        out.update(loc=loc, cid=2, sc=sc)
    else:
        return None
    stats = {}
    for k, v in (opt.get("stats") or {}).items():
        key = STAT.get(int(k))
        if key and v:
            stats[key] = v
    lo, hi, speed = opt.get("weaponDamageMin"), opt.get("weaponDamageMax"), it.get("weaponSpeed")
    if lo and hi and speed:
        stats["ITEM_MOD_DAMAGE_PER_SECOND_SHORT"] = round((lo + hi) / 2 / speed, 1)
        stats["ITEM_MOD_CR_SPEED_SHORT"] = speed
    out["stats"] = stats
    return {k: v for k, v in out.items() if v is not None}


def canon(k):
    """RestedXP's MoP file's names -> the page's."""
    if k == "ITEM_MOD_HASTE":
        return "ITEM_MOD_HASTE_RATING_SHORT"
    if k in ("ITEM_MOD_SPELL_POWER", "ITEM_MOD_SPELL_DAMAGE_DONE"):
        return "STAT_SPELLDAMAGE"
    if k.startswith("ITEM_MOD_") and not k.endswith("_SHORT") and "_SHORT_" not in k:
        return k + "_SHORT"
    return k


ENTRY = re.compile(r"\[\s*'([^']+)'\s*\]\s*=\s*\{(.*?)\n\s*\},", re.S)
FIELD = re.compile(r"\[\s*'([^']+)'\s*\]\s*=\s*(\"[^\"]*\"|-?[\d.]+)")
META = {"Title": "title", "Class": "class", "Spec": "spec", "Kind": "kind", "MIN_LEVEL": "min", "MAX_LEVEL": "max"}


def rxp_sets(rxp):
    src = (rxp / "DB" / "mop" / "statWeights.lua").read_text(encoding="utf-8")
    out = []
    for name, body in ENTRY.findall(src):
        e = {"id": name, "w": {}, "src": "RestedXP"}
        for k, v in FIELD.findall(body):
            val = v.strip('"') if v.startswith('"') else float(v)
            if k in META:
                e[META[k]] = int(val) if k.endswith("LEVEL") else val
            elif k != "Total" and val:
                e["w"][canon(k)] = val
        if "class" in e and "min" in e:
            e["kind"] = "Leveling (RestedXP)"
            out.append(e)
    return out


CLASS = {"death_knight": "Death Knight", "druid": "Druid", "hunter": "Hunter", "mage": "Mage", "monk": "Monk",
         "paladin": "Paladin", "priest": "Priest", "rogue": "Rogue", "shaman": "Shaman", "warlock": "Warlock",
         "warrior": "Warrior"}


def wowsims_sets(ws):
    out = []
    for f in sorted((ws / "ui" / "specs").glob("*/*/presets/ep/*.ep.json")):
        cls, spec = f.parts[-5], f.parts[-4]
        d = json.loads(f.read_text(encoding="utf-8"))
        w = {}
        for k, v in {**(d.get("stats") or {}), **(d.get("pseudoStats") or {})}.items():
            key = EP_NAME.get(k)
            if key and v:
                w[key] = v
        if not w:
            continue
        preset = d.get("name") or f.stem
        spec_name = spec.replace("_", " ").title()
        out.append({"id": f"wowsims {cls} {spec} {f.stem}", "class": CLASS.get(cls, cls), "spec": spec_name,
                    "kind": "Level 90 (wowsims " + preset + ")", "min": 1, "max": 90,
                    "title": f"{CLASS.get(cls, cls)} {spec_name}", "w": w, "src": "wowsims"})
    return out


def ratings(ws):
    """Rating points per 1% by level, from wowsims' assets/db_inputs/basestats/
    combatratings.txt (Blizzard's combat rating table, levels 1-100). Its columns
    are Level then CR_* ids from 1 (CR_HIT_SPELL = 8 -> column 9, CR_MASTERY = 26 ->
    column 27, as Blizzard_CharacterFrame's CR_ constants number them); the header
    names are one off from column 26 on, so columns are read by number.
    Checked: level 90 = hit 340, crit 600, haste 425, mastery 600."""
    col = {"hit_melee": 7, "hit_spell": 9, "crit_melee": 10, "crit_spell": 12, "haste_melee": 19,
           "haste_spell": 21, "expertise": 25, "mastery": 27, "dodge": 4, "parry": 5}
    out = {}
    for line in (ws / "assets" / "db_inputs" / "basestats" / "combatratings.txt").read_text(encoding="utf-8").splitlines()[1:]:
        f = line.split("\t")
        if len(f) > 27 and f[0].isdigit():
            out[f[0]] = {k: round(float(f[c - 1]), 4) for k, c in col.items()}
    if out.get("90", {}).get("mastery") != 600:
        sys.exit("combatratings.txt: level 90 mastery is not 600; the columns moved?")
    return out


def main():
    ws, rxp = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    commit = (ws / "COMMIT").read_text().strip() if (ws / "COMMIT").exists() else git_head(ws)
    items = {}
    for name in ("db.json", "leftover_db.json"):
        p = ws / "assets" / "database" / name
        for it in json.loads(p.read_text(encoding="utf-8")).get("items", []):
            items.setdefault(it["id"], it)
    quests = (ROOT / "ZugzugLeveler" / "data" / "Quests_Mists.lua").read_text(encoding="utf-8")
    want = set()
    for m in re.finditer(r"rw=\{([\d,]+)\}", quests):
        want.update(int(x) for x in m.group(1).split(","))
    out = {}
    for i in sorted(want):
        if i in items:
            c = convert_item(items[i])
            if c:
                out[str(i)] = c
    OUT.mkdir(parents=True, exist_ok=True)
    doc = {"source": f"wowsims/mop {commit} (github.com/wowsims/mop, MIT License, Copyright (c) 2022 wowsims team): "
                     "assets/database/db.json + leftover_db.json; which items: AllTheThings quest rewards (MIT)",
           "items": out}
    (OUT / "items.json").write_text(json.dumps(doc, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    sets = rxp_sets(rxp) + wowsims_sets(ws)
    wdoc = {"source": "RestedXP Guides DB/mop/statWeights.lua (CC BY-NC-SA 4.0) and wowsims/mop "
                      f"{commit} ui/specs/*/*/presets/ep (MIT, github.com/wowsims/mop)", "license": "CC BY-NC-SA 4.0 + MIT",
            "sets": sets}
    (OUT / "weights.json").write_text(json.dumps(wdoc, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    rdoc = {"source": f"wowsims/mop {commit} assets/db_inputs/basestats/combatratings.txt (MIT): rating points per 1%",
            "levels": ratings(ws)}
    (OUT / "ratings.json").write_text(json.dumps(rdoc, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    print(f"{len(out)} of {len(want)} quest reward items found in wowsims' database -> {OUT / 'items.json'}")
    print(f"{len(sets)} weight sets ({sum(1 for s in sets if s['src'] == 'RestedXP')} RestedXP leveling, "
          f"{sum(1 for s in sets if s['src'] == 'wowsims')} wowsims) -> {OUT / 'weights.json'}")


if __name__ == "__main__":
    main()
