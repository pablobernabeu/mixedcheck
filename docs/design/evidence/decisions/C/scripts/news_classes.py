"""Count NEWS entries of R diagnostic packages that mention each model class.

A rough proxy for how much maintenance each model class has cost the
existing diagnostic packages (easystats performance and insight, DHARMa).
Each bullet is assigned to every class whose keywords it contains; bullets
under a 'Bug fixes' heading are counted separately.

Usage: python3 -I news_classes.py <news_dir> <out_csv>
"""
import csv
import re
import sys
from pathlib import Path

CLASSES = {
    "lme4 LMM (lmer/merMod)": r"\blmer\b|lmerMod|merMod|lmerTest|\blme4\b",
    "GLMM generic (glmer/binomial/poisson)": r"\bglmer\b|\bGLMMs?\b|binomial|poisson|bernoulli|logistic",
    "glmmTMB (any family)": r"glmmTMB",
    "zero-inflation / hurdle": r"zero[- ]?inflat|hurdle|ziformula|\bzi\b|truncated",
    "overdispersion / dispersion": r"over-?dispersion|under-?dispersion|dispersion",
    "negative binomial": r"negative[- ]binomial|nbinom|glmer\.nb|negbin",
    "beta / ordbeta / beta-binomial": r"\bbeta[_ ]?family|ordbeta|beta-?binomial|betareg|\bbeta regression|\bbeta models?\b",
    "ordinal (clm/clmm/polr)": r"\bclmm?2?\b|ordinal|\bpolr\b|cumulative",
    "nlme (lme/gls)": r"\bnlme\b|\blme\b|\bgls\b|corAR1|corStruct",
    "Bayesian (brms/rstanarm/stan)": r"\bbrms\b|brmsfit|stanreg|rstanarm|bayesian|\bstan\b",
    "GAM/GAMM (mgcv/gamm4)": r"\bmgcv\b|\bgamm4?\b|\bgam\b",
}


def bullets(text):
    """Yield (version, section, bullet_text) from a NEWS.md file."""
    version, section = "", ""
    cur = []
    def flush():
        if cur:
            yield_item = " ".join(cur).strip()
            cur.clear()
            return yield_item
        return None
    out = []
    for line in text.splitlines():
        m = re.match(r"^#\s+(\S+)\s+(\S+)", line)
        if m:
            b = flush()
            if b:
                out.append((version, section, b))
            version, section = m.group(2), ""
            continue
        m = re.match(r"^##+\s+(.*)", line)
        if m:
            b = flush()
            if b:
                out.append((version, section, b))
            section = m.group(1).strip()
            continue
        if re.match(r"^\s*[*-]\s+", line):
            b = flush()
            if b:
                out.append((version, section, b))
            cur.append(re.sub(r"^\s*[*-]\s+", "", line))
        elif line.strip() and cur:
            cur.append(line.strip())
        elif not line.strip():
            b = flush()
            if b:
                out.append((version, section, b))
    b = flush()
    if b:
        out.append((version, section, b))
    return out


def main(news_dir, out_csv):
    rows = []
    for pkg in ["performance", "insight", "DHARMa"]:
        f = Path(news_dir) / f"{pkg}_NEWS.md"
        items = bullets(f.read_text(encoding="utf-8", errors="replace"))
        n_all = len(items)
        n_bug = sum(1 for v, s, b in items if re.search(r"bug", s, re.I))
        for cls, pat in CLASSES.items():
            rx = re.compile(pat, re.I)
            hits = [(v, s, b) for v, s, b in items if rx.search(b)]
            bug_hits = [h for h in hits if re.search(r"bug", h[1], re.I)]
            rows.append({
                "package": pkg, "class": cls,
                "entries_mentioning": len(hits),
                "bugfix_entries_mentioning": len(bug_hits),
                "all_entries": n_all, "all_bugfix_entries": n_bug,
            })
    with open(out_csv, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    for r in rows:
        print(f"{r['package']:12s} {r['class']:40s} {r['entries_mentioning']:4d} "
              f"bugfix={r['bugfix_entries_mentioning']:4d} "
              f"(of {r['all_entries']} entries, {r['all_bugfix_entries']} bugfix)")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
