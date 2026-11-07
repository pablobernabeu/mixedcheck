import sys, json, urllib.request, ssl, os
ctx = ssl.create_default_context(cafile="/root/.ccr/ca-bundle.crt")
outdir = sys.argv[1]
rows = []
for name in sys.argv[2:]:
    url = f"https://pypi.org/pypi/{name}/json"
    try:
        with urllib.request.urlopen(url, context=ctx, timeout=30) as r:
            d = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"{name:<14} HTTP {e.code}"); continue
    json.dump(d, open(os.path.join(outdir, name + ".json"), "w"))
    info = d["info"]; ver = info["version"]
    files = d.get("urls", [])
    upload = min((f["upload_time_iso_8601"] for f in files), default="?")
    lic = info.get("license_expression") or (info.get("license") or "")[:40].replace("\n"," ")
    classifiers = [c for c in info.get("classifiers", []) if c.startswith("License")]
    req = info.get("requires_dist") or []
    print(f"{name:<14} {ver:<10} uploaded {upload[:10]} requires_python={info.get('requires_python')!r} licence={lic!r} {classifiers[:1]}")
    print(f"{'':<14} requires_dist(non-extra): {[r for r in req if 'extra ==' not in r]}")
