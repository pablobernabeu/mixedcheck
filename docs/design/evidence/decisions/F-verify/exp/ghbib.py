"""F-verify helper: GitHub code search, then extract the BibTeX entry (or ~12 lines of text) that
contains a DOI fragment from each matching file, and tabulate volume/number/pages/title/author.
Usage: python3 -I ghbib.py '<code search query>' '<doi fragment>' [max_files]
Fetched files are data only (parsed with regular expressions, never executed)."""
import json, re, sys, time, urllib.request, urllib.parse

q, frag = sys.argv[1], sys.argv[2]
max_files = int(sys.argv[3]) if len(sys.argv) > 3 else 20

def get(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "f-verify"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read().decode("utf-8", "replace")

items = []
for page in (1, 2):
    res = json.loads(get(f"https://api.github.com/search/code?per_page=50&page={page}&q=" + urllib.parse.quote(q)))
    items += res.get("items", [])
    if len(res.get("items", [])) < 50:
        break
    time.sleep(2)
print(f"# query={q!r} total={res.get('total_count')} fetched={len(items)}")
fields = ["author", "title", "journal", "journaltitle", "year", "date", "volume", "number", "issue", "pages", "doi"]
n = 0
for it in items:
    if n >= max_files:
        break
    repo, path = it["repository"]["full_name"], it["path"]
    sha = it["url"].split("ref=")[-1]
    try:
        txt = get(f"https://raw.githubusercontent.com/{repo}/{sha}/{urllib.parse.quote(path)}", accept="*/*")
    except Exception as e:
        continue
    i = txt.lower().find(frag.lower())
    if i < 0:
        continue
    start = txt.rfind("@", 0, i)
    is_bib = start >= 0 and re.match(r"@\w+\s*\{", txt[start:start + 40]) is not None and (i - start) < 4000
    n += 1
    if is_bib:
        end = txt.find("\n@", i)
        entry = txt[start:end if end > 0 else start + 4000]
        got = {}
        for f in fields:
            m = re.search(r"(?im)^\s*" + f + r"\s*=\s*[{\"]?(.+?)[}\"]?\s*,?\s*$", entry)
            if m:
                got[f] = m.group(1)[:160]
        print(f"## {repo}/{path}")
        for f in fields:
            if f in got:
                print(f"   {f:12s}: {got[f]}")
    else:
        ln = txt[:i].count("\n")
        lines = txt.splitlines()
        print(f"## {repo}/{path} (not BibTeX)")
        for j in range(max(0, ln - 3), min(len(lines), ln + 3)):
            print("   " + lines[j][:240])
    time.sleep(0.2)
