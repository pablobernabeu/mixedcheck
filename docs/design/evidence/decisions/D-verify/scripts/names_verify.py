#!/usr/bin/env python3
"""D-verify independent name check: PyPI (simple index; PEP 503 + Warehouse ultranormalisation, plus
a looser edit-distance-1 screen), conda-forge channeldata, CRAN and Bioc GitHub mirrors (raw DESCRIPTION
HTTP status, which also covers archived CRAN packages), conda-forge feedstocks, and PyPI JSON API."""
import sys, json, re, os, ssl, urllib.request, subprocess, concurrent.futures as cf
D = sys.argv[1]; names = sys.argv[2:]
ctx = ssl.create_default_context(cafile="/root/.ccr/ca-bundle.crt")
def status(url):
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, context=ctx, timeout=40) as r: return r.status
    except urllib.error.HTTPError as e: return e.code
    except Exception as e: return f"ERR {type(e).__name__}"
def lsremote(repo):
    r = subprocess.run(["git","ls-remote","--heads",f"https://github.com/{repo}"],capture_output=True,text=True,timeout=90,
                       env=dict(os.environ, GIT_TERMINAL_PROMPT="0"))
    return r.returncode == 0 and bool(r.stdout.strip())
pep503 = lambda n: re.sub(r"[-_.]+","-",n).lower()
def ultra(n):
    n = re.sub(r"[._-]","",n); n = re.sub(r"[lLiI]","1",n); n = re.sub(r"[oO]","0",n); return n.lower()
simple = json.load(open(os.path.join(D,"simple.json")))["projects"]
allnames = [p["name"] for p in simple]
by503 = {pep503(n): n for n in allnames}
byultra = {}
for n in allnames: byultra.setdefault(ultra(n), []).append(n)
conda = set(json.load(open(os.path.join(D,"channeldata.json")))["packages"])
def lev1(a, b):
    if abs(len(a)-len(b))>1: return False
    if a==b: return True
    if len(a)==len(b): return sum(x!=y for x,y in zip(a,b))==1
    if len(a)>len(b): a,b=b,a
    i=j=0; diff=0
    while i<len(a) and j<len(b):
        if a[i]!=b[j]:
            diff+=1; j+=1
            if diff>1: return False
        else: i+=1; j+=1
    return True
norm_all = {pep503(n).replace("-",""): n for n in allnames}
def check(n):
    k = n.lower()
    out = dict(name=n,
      cran_raw=status(f"https://raw.githubusercontent.com/cran/{n}/master/DESCRIPTION"),
      cran_lsremote=lsremote(f"cran/{n}"),
      bioc_lsremote=lsremote(f"bioc/{n}"),
      pypi_json=status(f"https://pypi.org/pypi/{n}/json"),
      pypi_exact=by503.get(pep503(n),""),
      pypi_too_similar=",".join(x for x in byultra.get(ultra(n),[]) if pep503(x)!=pep503(n)),
      pypi_edit1=",".join(sorted(v for kk,v in norm_all.items() if lev1(kk, pep503(n).replace('-','')) and kk!=pep503(n).replace('-',''))[:8]),
      conda=",".join(x for x in (k, "r-"+k) if x in conda),
      cf_feedstock=",".join(x for x in (f"{k}-feedstock", f"r-{k}-feedstock") if lsremote(f"conda-forge/{x}")))
    return out
with cf.ThreadPoolExecutor(6) as ex: rows = list(ex.map(check, names))
cols = list(rows[0].keys())
print("\t".join(cols))
for r in rows: print("\t".join(str(r[c]) for c in cols))
