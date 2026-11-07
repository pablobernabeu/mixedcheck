import sys, json, os
from packaging.specifiers import SpecifierSet
from packaging.version import Version, InvalidVersion
d = sys.argv[1]
for name in sys.argv[2:]:
    j = json.load(open(os.path.join(d, name + ".json")))
    info = j["info"]; latest = info["version"]
    up = min((f["upload_time_iso_8601"] for f in j["releases"].get(latest, [])), default="?")[:10]
    lic = info.get("license_expression") or (info.get("license") or "")[:30].replace("\n", " ")
    print(f"{name}: latest {latest} ({up}) requires_python={info.get('requires_python')!r} licence={lic!r}")
    for pyv in ("3.10", "3.11", "3.12"):
        best = None
        for ver, files in j["releases"].items():
            if not files: continue
            try: v = Version(ver)
            except InvalidVersion: continue
            if v.is_prerelease or v.is_devrelease: continue
            if all(f.get("yanked") for f in files): continue
            rps = {f.get("requires_python") or "" for f in files}
            if any((not r) or Version(pyv + ".0") in SpecifierSet(r) for r in rps):
                if best is None or v > best: best = v
        print(f"    newest admitting Python {pyv}: {best}")
    # first release of selected series and its requires_python
    for series in sys.argv[2:3]: pass
