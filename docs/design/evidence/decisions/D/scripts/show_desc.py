import sys, os, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_desc import parse_dcf
cache = sys.argv[1]
for p in sys.argv[2:]:
    path = os.path.join(cache, p + ".DESCRIPTION")
    if not os.path.exists(path):
        print("##", p, "MISSING"); continue
    f = parse_dcf(open(path, encoding="utf-8").read())
    print("##", p, f.get("Version"), "| Published:", f.get("Date/Publication","?"))
    for k in ("License","Depends","Imports","LinkingTo","NeedsCompilation","SystemRequirements"):
        if k in f: print(f"  {k}: {f[k]}")
    print("  Suggests:", (f.get("Suggests","")[:300] + ("..." if len(f.get("Suggests",""))>300 else "")))
