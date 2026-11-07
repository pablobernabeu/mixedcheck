"""F-verify helper: GitHub code search for bibliographic records of a reference, then fetch
matching files from raw.githubusercontent.com and print the lines around the match.
Usage: python3 -I ghsearch.py '<code search query>' '<regex to show>' [max_files] [context_lines]
Files fetched are treated as data only (printed, never executed)."""
import json, re, sys, time, urllib.request, urllib.parse

q, pat = sys.argv[1], sys.argv[2]
max_files = int(sys.argv[3]) if len(sys.argv) > 3 else 6
ctx = int(sys.argv[4]) if len(sys.argv) > 4 else 6

def get(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"Accept": accept, "User-Agent": "f-verify"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return r.read().decode("utf-8", "replace")

res = json.loads(get("https://api.github.com/search/code?per_page=30&q=" + urllib.parse.quote(q)))
items = res.get("items", [])
print(f"# query={q!r} total={res.get('total_count')} shown<={max_files}")
rx = re.compile(pat, re.I)
seen = 0
for it in items:
    if seen >= max_files:
        break
    repo, path = it["repository"]["full_name"], it["path"]
    sha = it["url"].split("ref=")[-1]
    raw = f"https://raw.githubusercontent.com/{repo}/{sha}/{urllib.parse.quote(path)}"
    try:
        txt = get(raw, accept="*/*")
    except Exception as e:
        print(f"## {repo}/{path}: fetch failed {e}")
        continue
    lines = txt.splitlines()
    hits = [i for i, l in enumerate(lines) if rx.search(l)]
    if not hits:
        continue
    seen += 1
    print(f"## {repo}/{path} @ {sha[:10]}")
    shown = set()
    for i in hits[:2]:
        for j in range(max(0, i - ctx), min(len(lines), i + ctx + 1)):
            if j not in shown:
                print("   " + lines[j][:220])
                shown.add(j)
        print("   ...")
    time.sleep(0.3)
