import json, sys, os, datetime as dt
from collections import OrderedDict
pk = sys.argv[1:]
for p in pk:
    d = json.load(open(f"pypi/{p}.json"))
    info = d["info"]
    rel = d["releases"]
    dates = []
    for v, files in rel.items():
        ts = [f["upload_time_iso_8601"] for f in files if not f.get("yanked")]
        yk = all(f.get("yanked") for f in files) if files else False
        if ts:
            dates.append((min(ts)[:10], v, len(files), yk))
    dates.sort()
    print("="*80)
    print(p, "| latest:", info["version"], "| requires_python:", info.get("requires_python"))
    print("license:", (info.get("license") or "")[:80], "| license_expression:", info.get("license_expression"))
    print("author:", info.get("author"), "| author_email:", info.get("author_email"))
    print("maintainer:", info.get("maintainer"), "| maintainer_email:", info.get("maintainer_email"))
    print("home:", info.get("home_page"), "| project_urls:", info.get("project_urls"))
    print("summary:", info.get("summary"))
    print("requires_dist:", info.get("requires_dist"))
    cls = [c for c in info.get("classifiers", []) if "Python ::" in c or "Status" in c or "License" in c]
    print("classifiers:", cls)
    print("n releases with files:", len(dates), "first:", dates[0] if dates else None, "last:", dates[-1] if dates else None)
    for x in dates[-15:]:
        print("   ", x)
    # wheel tags for latest
    files = d["urls"]
    print("latest files:", [f["filename"] for f in files][:40])
