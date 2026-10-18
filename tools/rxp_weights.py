"""RestedXP's Forever leveling stat weights -> companion/web/data/weights.json.

    python -I tools/rxp_weights.py <RXPGuides checkout>

Reads DB/forever/StatWeights.lua (CC BY-NC-SA 4.0, RestedXP): one table per
class / spec / level bracket / kind (Speedrun or Hardcore), keyed by the
names C_Item.GetItemStats uses (ITEM_MOD_INTELLECT_SHORT ...) plus RestedXP's
own STAT_SPELLDAMAGE_<SCHOOL> and weapon speed keys. Zero weights are dropped,
as RestedXP's ItemUpgrades.lua LoadStatWeights does. The output keeps the
license: credit RestedXP, never sell it.
"""
import json
import pathlib
import re
import sys

ENTRY = re.compile(r"\[\s*'([^']+)'\s*\]\s*=\s*\{(.*?)\n\s*\},", re.S)
FIELD = re.compile(r"\[\s*'([^']+)'\s*\]\s*=\s*(\"[^\"]*\"|-?[\d.]+)")
META = {"Title": "title", "Class": "class", "Spec": "spec", "Kind": "kind", "MIN_LEVEL": "min", "MAX_LEVEL": "max"}


def convert(src):
    out = []
    for name, body in ENTRY.findall(src):
        e = {"id": name, "w": {}}
        for k, v in FIELD.findall(body):
            val = v.strip('"') if v.startswith('"') else float(v)
            if k in META:
                e[META[k]] = int(val) if k.endswith("LEVEL") else val
            elif val:
                e["w"][k] = val
        if "class" in e and "min" in e:
            out.append(e)
    return out


def main():
    root = pathlib.Path(sys.argv[1])
    src = (root / "DB" / "forever" / "StatWeights.lua").read_text(encoding="utf-8")
    data = convert(src)
    if len(data) < 9:
        sys.exit(f"only {len(data)} weight sets parsed; the file format changed?")
    dest = pathlib.Path(__file__).resolve().parent.parent / "companion" / "web" / "data" / "weights.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    doc = {"source": "RestedXP Guides, DB/forever/StatWeights.lua", "license": "CC BY-NC-SA 4.0", "sets": data}
    dest.write_text(json.dumps(doc, separators=(",", ":"), sort_keys=True), encoding="utf-8")
    classes = sorted({e["class"] for e in data})
    print(f"{len(data)} weight sets, {len(classes)} classes ({', '.join(classes)}) -> {dest}")


if __name__ == "__main__":
    main()
