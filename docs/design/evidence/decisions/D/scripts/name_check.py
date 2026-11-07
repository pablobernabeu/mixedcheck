#!/usr/bin/env python3
"""Check candidate package names on CRAN (cran GitHub mirror; current or archived; case-insensitive),
Bioconductor (bioc GitHub mirror), PyPI (exact PEP 503 name and PyPI's 'too similar' ultranormalised name),
and conda-forge (channeldata package list, python and r- prefixed). Writes a TSV."""
import sys, json, re, subprocess, concurrent.futures as cf, os
D = sys.argv[1]
names = sys.argv[3:]
out = sys.argv[2]
env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
def exists(repo):
    try:
        r = subprocess.run(["git", "ls-remote", "--heads", f"https://github.com/{repo}"], capture_output=True, text=True, timeout=90, env=env)
        return r.returncode == 0 and bool(re.search(r"^[0-9a-f]{40}", r.stdout, re.M))
    except Exception as e:
        return None
pep503 = lambda n: re.sub(r"[-_.]+", "-", n).lower()
def ultra(n):
    n = re.sub(r"[._-]", "", n, flags=re.I)
    n = re.sub(r"[lLiI]", "1", n); n = re.sub(r"[oO]", "0", n)
    return n.lower()
simple = json.load(open(os.path.join(D, "pypi_index/simple.json")))["projects"]
by503 = {pep503(p["name"]): p["name"] for p in simple}
byultra = {}
for p in simple:
    byultra.setdefault(ultra(p["name"]), []).append(p["name"])
conda = set(json.load(open(os.path.join(D, "conda/channeldata.json")))["packages"])
def check(n):
    res = {"name": n}
    res["cran"] = exists(f"cran/{n}")
    res["bioc"] = exists(f"bioc/{n}")
    res["pypi_exact"] = by503.get(pep503(n), "")
    res["pypi_similar"] = ",".join(x for x in byultra.get(ultra(n), []) if pep503(x) != pep503(n))
    res["conda_forge"] = ",".join(x for x in (n.lower(), "r-" + n.lower()) if x in conda)
    res["cf_feedstock"] = ",".join(x for x in (f"{n.lower()}-feedstock", f"r-{n.lower()}-feedstock") if exists(f"conda-forge/{x}"))
    return res
with cf.ThreadPoolExecutor(8) as ex:
    rows = list(ex.map(check, names))
cols = ["name","cran","bioc","pypi_exact","pypi_similar","conda_forge","cf_feedstock"]
with open(out, "w") as f:
    f.write("\t".join(cols) + "\n")
    for r in rows:
        f.write("\t".join(str(r[c]) for c in cols) + "\n")
for r in rows:
    free = (r["cran"] is False and r["bioc"] is False and not r["pypi_exact"] and not r["pypi_similar"] and not r["conda_forge"] and not r["cf_feedstock"])
    print(f"{r['name']:<16} CRAN={'TAKEN' if r['cran'] else ('free' if r['cran'] is False else '??'):<6} Bioc={'TAKEN' if r['bioc'] else ('free' if r['bioc'] is False else '??'):<6} PyPI={r['pypi_exact'] or '-':<14} PyPI-similar={r['pypi_similar'] or '-':<22} conda-forge={r['conda_forge'] or '-'}/{r['cf_feedstock'] or '-'}  {'ALL FREE' if free else ''}")
