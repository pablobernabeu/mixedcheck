import sys, os, re, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fetch_desc import parse_dcf, parse_deps, BASE, fetch

RECOMMENDED = {"KernSmooth","MASS","Matrix","boot","class","cluster","codetools","foreign",
               "lattice","mgcv","nlme","nnet","rpart","spatial","survival"}
cache = sys.argv[1]
_meta = {}
def meta(p):
    if p not in _meta:
        txt = fetch(p, cache)
        _meta[p] = parse_dcf(txt) if txt else None
    return _meta[p]

def closure(roots, fields):
    seen = set(); todo = list(roots)
    while todo:
        p = todo.pop()
        if p in BASE or p in seen: continue
        seen.add(p)
        m = meta(p)
        if m is None: continue
        for fld in fields:
            for d,_ in parse_deps(m.get(fld, "")):
                if d not in BASE and d not in seen: todo.append(d)
    return seen

def summarise(name, roots):
    rt = closure(roots, ("Depends","Imports"))
    src = closure(roots, ("Depends","Imports","LinkingTo"))
    def stats(s):
        nonrec = sorted(x for x in s if x not in RECOMMENDED)
        rec = sorted(x for x in s if x in RECOMMENDED)
        comp = sorted(x for x in s if meta(x) and meta(x).get("NeedsCompilation","no").strip().lower()=="yes")
        comp_nonrec = [x for x in comp if x not in RECOMMENDED]
        sysreq = {x: meta(x).get("SystemRequirements") for x in s if meta(x) and meta(x).get("SystemRequirements")}
        lic = {}
        for x in s:
            l = (meta(x) or {}).get("License","?")
            lic.setdefault(l, []).append(x)
        maxR = []
        for x in s:
            for d,v in parse_deps((meta(x) or {}).get("Depends","")):
                if d == "R" and v: maxR.append((v, x))
        return dict(total=len(s), nonrecommended=len(nonrec), recommended=rec, compiled=len(comp),
                    compiled_nonrec=comp_nonrec, sysreq=sysreq, licences=lic, nonrec_list=nonrec, Rreqs=maxR)
    return dict(set=name, roots=roots, runtime=stats(rt), source=stats(src))

sets = json.loads(sys.argv[2])
res = [summarise(k, v) for k, v in sets.items()]
json.dump(res, open(sys.argv[3], "w"), indent=1, default=list)
for r in res:
    a, b = r["runtime"], r["source"]
    print(f"{r['set']:<38} runtime: total={a['total']:>3} non-rec={a['nonrecommended']:>3} compiled={a['compiled']:>2} (non-rec compiled={len(a['compiled_nonrec']):>2}) | +LinkingTo: total={b['total']:>3} non-rec={b['nonrecommended']:>3} compiled={b['compiled']:>2}")
