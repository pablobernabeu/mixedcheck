"""Parse each fixture's data.csv with the types, missing tokens and category
order declared in design.json (Frictionless subset), then hash a canonical
column-wise JSON form (RFC 8785). Compare with table_hash.R.
Usage: python -I table_hash.py <zoo_dir>
"""
import hashlib
import json
import os
import sys

import pandas as pd
import rfc8785


def parse(fixture_dir):
    des = json.load(open(os.path.join(fixture_dir, "design.json"), encoding="utf-8"))
    fields = des["table"]["fields"]
    na = des["table"].get("missingValues", [""])
    na = [m if isinstance(m, str) else m["value"] for m in na]
    df = pd.read_csv(os.path.join(fixture_dir, "data.csv"), dtype=str, keep_default_na=False,
                     na_values=[], encoding="utf-8")
    cols, levels = {}, {}
    for f in fields:
        raw = df[f["name"]].tolist()
        t = f.get("type", "string")
        vals = []
        for v in raw:
            if v in na:
                vals.append(None)
            elif t == "integer":
                vals.append(int(v))
            elif t == "number":
                vals.append(float(v))
            else:
                vals.append(v)
        cols[f["name"]] = vals
        if "categories" in f:
            levels[f["name"]] = [c if not isinstance(c, dict) else c["value"] for c in f["categories"]]
            bad = {v for v in vals if v is not None} - set(levels[f["name"]])
            if bad:
                raise ValueError(f"values outside categories in {f['name']}: {sorted(bad)[:3]}")
    return {"columns": cols, "levels": levels, "nrow": len(df)}


def main():
    zoo = sys.argv[1]
    for fid in sorted(os.listdir(zoo)):
        doc = parse(os.path.join(zoo, fid))
        print(f"{fid}\t{hashlib.sha256(rfc8785.dumps(doc)).hexdigest()}")


if __name__ == "__main__":
    main()
