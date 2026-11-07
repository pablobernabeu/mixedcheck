"""C-verify: re-analyse C's NEWS keyword proxy (C-E03).

C counted bullets in performance/insight/DHARMa NEWS matching 'binomial|poisson|
bernoulli|logistic|glmer|GLMM'. Here each such bullet is split into
 (a) bullets that also mention a mixed model (glmer, GLMM, mixed, merMod, glmmTMB,
     random effect), and
 (b) bullets that do not (plain GLMs, e.g. logistic regression),
and bullets naming mixed models generically ('mixed model', 'mixed-effects') are
counted for comparison with C's lme4-only pattern.
Usage: python3 -I news_reanalysis.py <news_dir> <out_csv>
"""
import csv
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "C" / "scripts"))
from news_classes import bullets  # C's own bullet parser, reused unchanged

GLMM_GENERIC = re.compile(r"\bglmer\b|\bGLMMs?\b|binomial|poisson|bernoulli|logistic", re.I)
MIXED = re.compile(r"\bglmer\b|\bGLMMs?\b|mixed|merMod|glmmTMB|random[- ]effect|\blme4\b|\blmer\b", re.I)
LME4_C = re.compile(r"\blmer\b|lmerMod|merMod|lmerTest|\blme4\b", re.I)
MIXED_GENERIC = re.compile(r"mixed[- ](effects? )?models?|mixed-effects|\bLMMs?\b", re.I)

rows = []
for pkg in ["performance", "insight", "DHARMa"]:
    items = bullets((Path(sys.argv[1]) / f"{pkg}_NEWS.md").read_text(encoding="utf-8"))
    g = [b for _, _, b in items if GLMM_GENERIC.search(b)]
    g_mixed = [b for b in g if MIXED.search(b)]
    rows.append({
        "package": pkg,
        "C_glmm_generic": len(g),
        "of_which_mention_mixed_or_glmmTMB": len(g_mixed),
        "of_which_no_mixed_term (plain GLM)": len(g) - len(g_mixed),
        "C_lme4_pattern": sum(1 for _, _, b in items if LME4_C.search(b)),
        "generic_mixed_model_mentions": sum(1 for _, _, b in items if MIXED_GENERIC.search(b)),
        "lme4_pattern_or_generic_mixed": sum(1 for _, _, b in items
                                             if LME4_C.search(b) or MIXED_GENERIC.search(b)),
    })
    if pkg == "performance":
        print("performance: GLMM-generic bullets with no mixed-model term (first 8):")
        for b in [b for b in g if not MIXED.search(b)][:8]:
            print("  -", b[:160])
with open(sys.argv[2], "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
for r in rows:
    print(r)
