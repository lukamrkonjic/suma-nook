#!/usr/bin/env python3
"""Move a rebuilt tile back into the live catalog.

Four places have to agree or the tile is live in one system and missing in
another: the tile-kit manifest's lifecycle/visibility, tuning.json's
active_tile_ids gate, the obtainable flag in tiles.json, and membership of a
creative collection.

Usage: python tools/gg_match/publish_tile.py <tile_id> --collection <id>
"""
import argparse
import json
import re
from pathlib import Path


def crlf(path, data):
    path.write_text(json.dumps(data, indent=2).replace("\n", "\r\n") + "\r\n",
                    encoding="utf-8")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tile_id")
    ap.add_argument("--collection", required=True)
    args = ap.parse_args()
    tid = args.tile_id

    p = Path("tools/tile_kit/library/manifests/%s.tres" % tid)
    t = p.read_text(encoding="utf-8")
    t = re.sub(r'lifecycle = "[a-z]+"', 'lifecycle = "published"', t)
    t = re.sub(r'visibility = "[a-z]+"', 'visibility = "active"', t)
    p.write_text(t, encoding="utf-8")

    p = Path("data/tuning.json")
    d = json.loads(p.read_text(encoding="utf-8"))

    def find(o):
        if isinstance(o, dict):
            for k, v in o.items():
                if k == "active_tile_ids":
                    return o
                r = find(v)
                if r is not None:
                    return r
    owner = find(d)
    if tid not in owner["active_tile_ids"]:
        owner["active_tile_ids"].append(tid)
        owner["active_tile_ids"].sort()
    crlf(p, d)

    p = Path("data/tiles.json")
    d = json.loads(p.read_text(encoding="utf-8"))
    name = "?"
    for tile in d["tiles"]:
        if tile["id"] == tid:
            tile["obtainable"] = True
            name = tile["name"]
    crlf(p, d)

    p = Path("data/creative_collections.json")
    d = json.loads(p.read_text(encoding="utf-8"))
    for c in d["creative_collections"]:
        if c["id"] != args.collection:
            continue
        if not any(m["id"] == tid for m in c["members"]):
            c["members"].append(
                {"kind": "tile", "id": tid, "tier": 1, "family": "ground"})
    crlf(p, d)
    print("published %s (%s) into %s; roster now %d"
          % (tid, name, args.collection, len(owner["active_tile_ids"])))


if __name__ == "__main__":
    main()
