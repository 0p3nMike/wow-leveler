"""Mists of Pandaria Classic zone names -> zone (area) IDs, for the page's map art.

    python -I tools/mop_zones.py <AreaTable.csv>

The CSV is the 5.5.4 client's AreaTable as wago.tools exports it
(https://wago.tools/db2/AreaTable/csv?build=5.5.4.70449). Zones are its rows with
ParentAreaID 0; a name can have several IDs (the same zone in another phase or
continent), kept ascending as data/zones.json keeps Forever's. The companion
tries each ID against Wowhead's "mists" map set
(wow.zamimg.com/images/wow/mists/maps/enus/original/<id>.jpg) and keeps the
first that exists.
Writes companion/web/data/zones-mists.json.
"""
import csv
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    rows = list(csv.DictReader(open(sys.argv[1], encoding="utf-8")))
    zones = {}
    for r in rows:
        if r.get("ParentAreaID") == "0" and r.get("AreaName_lang"):
            zones.setdefault(r["AreaName_lang"], []).append(int(r["ID"]))
    for ids in zones.values():
        ids.sort()
    out = ROOT / "companion" / "web" / "data" / "zones-mists.json"
    doc = {"_source": "AreaTable of the 5.5.4.70449 client (wago.tools/db2/AreaTable), zones (ParentAreaID 0): name -> area IDs ascending",
           "zones": dict(sorted(zones.items()))}
    out.write_text(json.dumps(doc, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
    print(f"{len(zones)} zone names -> {out}")


if __name__ == "__main__":
    main()
