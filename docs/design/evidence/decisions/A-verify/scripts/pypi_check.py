import json, sys, os
from datetime import datetime
d = sys.argv[1]
for p in ["statsmodels","mixedlm","glmm","gpboost","pymer4","rpy2","juliacall","rpy2-rinterface","rpy2-robjects"]:
    j = json.load(open(os.path.join(d, p + ".json")))
    info = j["info"]
    rel = j["releases"]
    dates = []
    for v, files in rel.items():
        if files:
            t = min(f["upload_time_iso_8601"] for f in files)
            yanked = all(f.get("yanked") for f in files)
            dates.append((t, v, yanked))
    dates.sort()
    nonempty = len(dates)
    latest = info["version"]
    lat_files = rel.get(latest, [])
    lat_date = min(f["upload_time_iso_8601"] for f in lat_files) if lat_files else None
    print(f"== {p}: latest {latest} uploaded {lat_date}; releases with files: {nonempty}; first {dates[0][:2]}; yanked: {[x[1] for x in dates if x[2]]}")
    print("   license:", info.get("license"), "| license_expression:", info.get("license_expression"))
    print("   classifiers(license):", [c for c in info.get("classifiers", []) if "License" in c])
    print("   requires_python:", info.get("requires_python"))
    print("   requires_dist:", info.get("requires_dist"))
    print("   author:", info.get("author"), "|", info.get("author_email"), "| maintainer:", info.get("maintainer"), "|", info.get("maintainer_email"))
    print("   py classifiers:", [c.split("::")[-1].strip() for c in info.get("classifiers", []) if c.startswith("Programming Language :: Python :: 3.")])
    if p in ("mixedlm", "glmm", "pymer4", "statsmodels", "gpboost", "rpy2", "juliacall"):
        print("   last 16 releases:", [(x[1], x[0][:10]) for x in dates[-16:]])
    if p == "glmm" or p == "mixedlm":
        print("   wheel files of latest:", [f["filename"] for f in lat_files])
