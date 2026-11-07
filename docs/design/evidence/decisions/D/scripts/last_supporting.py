import sys, json, os
from packaging.specifiers import SpecifierSet
from packaging.version import Version, InvalidVersion
d = sys.argv[1]
for name in sys.argv[2:]:
    j = json.load(open(os.path.join(d, name + ".json")))
    out = {}
    for pyv in ("3.9","3.10","3.11","3.12","3.13","3.14","3.15"):
        best = None
        for ver, files in j["releases"].items():
            if not files: continue
            try: v = Version(ver)
            except InvalidVersion: continue
            if v.is_prerelease or v.is_devrelease: continue
            if all(f.get("yanked") for f in files): continue
            rp = {f.get("requires_python") or "" for f in files}
            ok = any((not r) or (Version(pyv + ".0") in SpecifierSet(r)) for r in rp)
            if ok and (best is None or v > best[0]):
                up = min(f["upload_time_iso_8601"] for f in files)[:10]
                best = (v, up)
        out[pyv] = f"{best[0]} ({best[1]})" if best else "-"
    # wheels for which cp tags in latest
    latest = j["info"]["version"]
    tags = sorted({f["filename"].split("-")[2] for f in j["releases"][latest] if f["filename"].endswith(".whl")})
    print(name, "| latest", latest, "| wheel py tags:", ",".join(t for t in tags if t.startswith("cp"))[:120])
    for k, v in out.items(): print(f"   max version admitting Python {k}: {v}")
