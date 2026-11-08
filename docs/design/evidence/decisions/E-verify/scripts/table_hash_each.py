"""Run report E's table_hash.parse() on each fixture separately, catching errors,
and print the canonical JSON and its SHA-256 so R and Python can be compared.
Usage: python -I table_hash_each.py <report_scripts_dir> <zoo_dir>
"""
import hashlib
import os
import sys

sys.path.insert(0, sys.argv[1])
import rfc8785  # noqa: E402
import table_hash  # noqa: E402  (report E's script)

zoo = sys.argv[2]
for fid in sorted(os.listdir(zoo)):
    try:
        doc = table_hash.parse(os.path.join(zoo, fid))
        canon = rfc8785.dumps(doc)
        print(f"{fid}\tCANON\t{canon.decode()}")
        print(f"{fid}\t{hashlib.sha256(canon).hexdigest()}")
    except Exception as e:  # noqa: BLE001
        print(f"{fid}\tERROR\t{type(e).__name__}: {str(e)[:120]}")
