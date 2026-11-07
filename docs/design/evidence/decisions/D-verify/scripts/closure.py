#!/usr/bin/env python3
"""Independent re-implementation of recursive hard-dependency closure over CRAN DESCRIPTION files
(cran GitHub mirror). Written for D-verify; does not import report D's code.
Usage: closure.py <cache_dir> <out_json>"""
import sys, os, re, json, ssl, urllib.request, time
cache, outp = sys.argv[1], sys.argv[2]
BASE = {"R","base","compiler","datasets","graphics","grDevices","grid","methods","parallel","splines",
        "stats","stats4","tcltk","tools","utils"}
REC = {"KernSmooth","MASS","Matrix","boot","class","cluster","codetools","foreign","lattice","mgcv",
       "nlme","nnet","rpart","spatial","survival"}
ctx = ssl.create_default_context(cafile="/root/.ccr/ca-bundle.crt")
def get(p):
    fp = os.path.join(cache, p + ".DESCRIPTION")
    if not os.path.exists(fp):
        url = f"https://raw.githubusercontent.com/cran/{p}/master/DESCRIPTION"
        for i in range(4):
            try:
                with urllib.request.urlopen(url, context=ctx, timeout=40) as r:
                    open(fp, "wb").write(r.read()); break
            except urllib.error.HTTPError as e:
                if e.code == 404: return None
                time.sleep(2)
            except Exception: time.sleep(2)
        else:
            return None
    t = open(fp, encoding="utf-8", errors="replace").read()
    f, k = {}, None
    for line in t.splitlines():
        if line[:1] in (" ", "\t") and k: f[k] += " " + line.strip()
        else:
            m = re.match(r"^([A-Za-z0-9@/._-]+):\s*(.*)$", line)
            if m: k = m.group(1); f[k] = m.group(2).strip()
    return f
def deps(f, fields):
    out = []
    for fld in fields:
        for part in (f.get(fld) or "").split(","):
            m = re.match(r"\s*([A-Za-z][A-Za-z0-9.]*)", part)
            if m and m.group(1) not in BASE: out.append(m.group(1))
    return out
def closure(roots, fields):
    seen, todo = set(), list(roots)
    while todo:
        p = todo.pop()
        if p in seen or p in BASE: continue
        seen.add(p)
        f = get(p)
        if f is None: print("MISSING", p, file=sys.stderr); continue
        todo += [d for d in deps(f, fields) if d not in seen]
    return seen
SETS = {
 "S0 Matrix+jsonlite": ["Matrix","jsonlite"],
 "S2 +lme4": ["Matrix","jsonlite","lme4"],
 "S3 +lme4+insight": ["Matrix","jsonlite","lme4","insight"],
 "S4 +lme4+performance": ["Matrix","jsonlite","lme4","performance"],
 "S5 +lme4+DHARMa": ["Matrix","jsonlite","lme4","DHARMa"],
 "S6 +lme4+glmmTMB": ["Matrix","jsonlite","lme4","glmmTMB"],
 "S7 +lme4+lmerTest+pbkrtest": ["Matrix","jsonlite","lme4","lmerTest","pbkrtest"],
 "S8 S0+quarto": ["Matrix","jsonlite","quarto"],
 "S9 S0+ggplot2": ["Matrix","jsonlite","ggplot2"],
 "S10 everything": ["Matrix","jsonlite","lme4","performance","DHARMa","glmmTMB","lmerTest","pbkrtest","ggplot2"],
 "X1 S0+reformulas": ["Matrix","jsonlite","reformulas"],
 "X2 S0+whisker": ["Matrix","jsonlite","whisker"],
 "X3 performance alone": ["performance"],
}
res = {}
for name, roots in SETS.items():
    rt = closure(roots, ("Depends","Imports"))
    src = closure(roots, ("Depends","Imports","LinkingTo"))
    comp = sorted(p for p in src if (get(p) or {}).get("NeedsCompilation","no").strip().lower()=="yes")
    comp_nonrec = [p for p in comp if p not in REC]
    rfloor = []
    for p in src:
        f = get(p) or {}
        for part in (f.get("Depends") or "").split(","):
            m = re.match(r"\s*R\s*\(\s*>=?\s*([0-9.\-]+)\s*\)", part)
            if m: rfloor.append((tuple(int(x) for x in re.split(r"[.-]", m.group(1))), m.group(1), p))
    rfloor.sort(reverse=True)
    res[name] = dict(roots=roots, runtime=len(rt), withLinkingTo=len(src), nonrec=len([p for p in src if p not in REC]),
                     compiled=len(comp), compiled_nonrec=comp_nonrec, top_R_floors=[(v,p) for _,v,p in rfloor[:4]],
                     members=sorted(src))
    print(f"{name:<30} runtime={len(rt):>3} +LinkingTo={len(src):>3} nonrec={res[name]['nonrec']:>3} compiled={len(comp):>3} compiled_nonrec={len(comp_nonrec):>3} topR={res[name]['top_R_floors'][:2]}")
json.dump(res, open(outp, "w"), indent=1)
