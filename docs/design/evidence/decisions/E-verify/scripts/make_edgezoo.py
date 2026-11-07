"""Build edge-case table fixtures (design.json + data.csv) to probe whether the
report's R (read.csv) and Python (pandas) table readers parse identically.
Usage: python -I make_edgezoo.py <out_dir>
"""
import json
import os
import sys

MV = {"missingValues": [""]}


def fx(name, fields, data, mv=True):
    table = {"fields": fields}
    if mv:
        table.update(MV)
    return name, {"schema_version": "0.1.0", "table": table}, data


S = {"name": "id", "type": "string"}
FIXTURES = [
    # Frictionless default missingValues is [""] when the property is absent
    fx("T1_missing_default", [S, {"name": "g", "type": "string"}, {"name": "y", "type": "number"}],
       b"id,g,y\n1,a,1.5\n2,,2.5\n3,b,\n", mv=False),
    fx("T2_integer_forms", [S, {"name": "k", "type": "integer"}], b"id,k\n1,007\n2,+5\n3, 12\n4,1_000\n"),
    fx("T3_hex_integer", [S, {"name": "k", "type": "integer"}], b"id,k\n1,0x1A\n"),
    fx("T4_number_tokens", [S, {"name": "y", "type": "number"}], b"id,y\n1,NaN\n2,INF\n3,-INF\n"),
    fx("T5_strings", [S, {"name": "s", "type": "string"}], "id,s\n1,NA\n2,café\n3, padded \n4,\"a,b\"\n".encode()),
    fx("T6_crlf", [S, {"name": "s", "type": "string"}], b"id,s\r\n1,x\r\n2,y\r\n"),
    fx("T7_bom", [S, {"name": "s", "type": "string"}], b"\xef\xbb\xbfid,s\n1,x\n"),
    fx("T8_volts", [S, {"name": "amp", "type": "number"}], b"id,amp\n1,3.2e-06\n2,-1.25e-07\n"),
    fx("T9_embedded_newline", [S, {"name": "s", "type": "string"}], b"id,s\n1,\"two\nlines\"\n2,z\n"),
    fx("T10_clean_control", [S, {"name": "s", "type": "string"}, {"name": "y", "type": "number"}],
       b"id,s\n1,x,0.5\n2,y,1.25\n".replace(b"id,s\n", b"id,s,y\n")),
]


def main():
    out = sys.argv[1]
    for name, des, data in FIXTURES:
        d = os.path.join(out, name)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "design.json"), "w", encoding="utf-8") as fh:
            json.dump(des, fh)
        with open(os.path.join(d, "data.csv"), "wb") as fh:
            fh.write(data)
    print("wrote", len(FIXTURES), "fixtures to", out)


if __name__ == "__main__":
    main()
