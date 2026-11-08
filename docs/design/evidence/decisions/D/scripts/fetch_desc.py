#!/usr/bin/env python3
"""Fetch CRAN DESCRIPTION files from the cran GitHub mirror (raw.githubusercontent.com/cran/<pkg>/master/DESCRIPTION),
recursively over hard dependencies (Depends, Imports, LinkingTo). Caches files under dl/desc/.
Usage: fetch_desc.py <cache_dir> <pkg> [<pkg> ...]
"""
import sys, os, re, json, urllib.request, ssl, time

BASE = {"R","base","compiler","datasets","graphics","grDevices","grid","methods","parallel",
        "splines","stats","stats4","tcltk","tools","utils"}

def parse_dcf(text):
    fields = {}
    key = None
    for line in text.splitlines():
        if not line.strip():
            continue
        if line[0] in " \t" and key:
            fields[key] += " " + line.strip()
        else:
            m = re.match(r"^([A-Za-z0-9@/._-]+):\s*(.*)$", line)
            if m:
                key = m.group(1); fields[key] = m.group(2).strip()
    return fields

def parse_deps(s):
    out = []
    if not s: return out
    for part in s.split(","):
        part = part.strip()
        if not part: continue
        m = re.match(r"^([A-Za-z0-9.]+)\s*(\((.*)\))?", part)
        if m:
            out.append((m.group(1), (m.group(3) or "").strip()))
    return out

ctx = ssl.create_default_context(cafile="/root/.ccr/ca-bundle.crt")

def fetch(pkg, cache):
    path = os.path.join(cache, pkg + ".DESCRIPTION")
    if os.path.exists(path):
        return open(path, encoding="utf-8", errors="replace").read()
    url = f"https://raw.githubusercontent.com/cran/{pkg}/master/DESCRIPTION"
    for attempt in range(3):
        try:
            with urllib.request.urlopen(url, context=ctx, timeout=30) as r:
                txt = r.read().decode("utf-8", errors="replace")
            open(path, "w", encoding="utf-8").write(txt)
            return txt
        except urllib.error.HTTPError as e:
            if e.code == 404:
                open(path + ".404", "w").write("404")
                return None
            time.sleep(1)
        except Exception as e:
            time.sleep(1)
    return None

def main():
    cache = sys.argv[1]
    todo = list(sys.argv[2:])
    seen = set()
    while todo:
        p = todo.pop()
        if p in seen or p in BASE: continue
        seen.add(p)
        txt = fetch(p, cache)
        if txt is None:
            print("MISSING", p, file=sys.stderr); continue
        f = parse_dcf(txt)
        for fld in ("Depends","Imports","LinkingTo"):
            for d,_ in parse_deps(f.get(fld,"")):
                if d not in BASE and d not in seen:
                    todo.append(d)
    print(len(seen), "packages fetched/cached")

if __name__ == "__main__":
    main()
