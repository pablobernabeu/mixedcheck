"""F-verify: write scenario variants of F's budget.R (copied to exp/budget_sens.R) and nothing else.
Each scenario changes one assumption that F-verify's experiments or F's own protocol contradict.
Usage: python3 -I make_scenarios.py <budget_sens.R> <out_dir>"""
import os, sys

src = open(sys.argv[1]).read()
out = sys.argv[2]
os.makedirs(out, exist_ok=True)

def rep(s, old, new):
    assert old in s, old
    return s.replace(old, new, 1)

# lme4 >= 1.1-38 skips deriv12 for lmer fits with >= 10 covariance parameters and for singular
# fits. exp1 measured derivative-free/default time ratios of 0.54, 0.40, 0.36 at 384, 1536, 6144
# rows for 2x2 maximal lmer fits; log-linear interpolation; applied to maximal 2x2 lmer fits only.
DERIV = '''tf_old <- tf
tf <- function(key, n) {
  base <- tf_old(key, n)
  if (key == "x22_lmer") base * pmin(1, exp(0.253 - 0.146 * log(n))) else base
}
'''
# exp2: Satterthwaite on 2x2 maximal fits costs about 3.1 x a derivative-free fit (1.05-1.41 x a
# lme4 1.1-35.1 fit), not 0.7 x
SATT22 = 'tf("x22_lmer", n) * (1 + 0.1 + R_SATT + R_SIM + R_OVERHEAD)'

scen = {}
s = rep(src, "tf <- function(key, n) exp(CM[[key]][[\"a\"]] + CM[[key]][[\"b\"]] * log(n))\n",
        "tf <- function(key, n) exp(CM[[key]][[\"a\"]] + CM[[key]][[\"b\"]] * log(n))\n" + DERIV)
s = rep(s, SATT22, 'tf("x22_lmer", n) * (1 + 0.1 + 3.1 + R_SIM + R_OVERHEAD)')
scen["S1_lme4_2.1_derivskip_plus_satt22"] = s

# S2: add Kenward-Roger to V1 for n <= 400 (F's own V1 protocol): exp/F timings: KR about 6.5 x a
# nested lmer fit, 17 x a one-factor crossed fit (1.46 s at 384 rows), 24.7 s for a 2x2 maximal fit at 384 rows
s = src
s = rep(s, 'tf("nested_lmer", n) * (1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD) + 0.2 * tf("nested_tmbG", n)),\n    "focal lmer + ML refit',
        'tf("nested_lmer", n) * (1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD + 6.5 * (n <= 400)) + 0.2 * tf("nested_tmbG", n)),\n    "focal lmer + ML refit')
s = rep(s, 'tf("crossed_lmer", n) * (1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD)',
        'tf("crossed_lmer", n) * (1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD + 17 * (n <= 400))')
s = rep(s, SATT22 + ' + tf("x22_lmer_zcp", n)', SATT22 + ' + 24.7 * (n <= 400) + tf("x22_lmer_zcp", n)')
scen["S2_KR_in_V1"] = s

# S3: allFit with all 7 optimisers (only 5 ran here: optimx and dfoptim missing)
scen["S3_allFit_7_optimisers"] = rep(src, "R_ALLFIT <- 20", "R_ALLFIT <- 28")

# S4: V6 without nesting: 500 outer fits + 20 design draws x 200 inner fits x 3 mismatch levels per cell
scen["S4_V6_unnested"] = rep(src, 'with(g, 200 * ifelse(design == "nested", tf("nested_lmer", n), tf("crossed_lmer", n)))',
                              'with(g, (1 + 20 * 200 * 3 / 500) * ifelse(design == "nested", tf("nested_lmer", n), tf("crossed_lmer", n)))')

# S5: exact cluster-deletion influence (catalogue L5-08 default for <= 100 levels) inside the V1 null bank,
# warm-started refits at 0.5 x a fit
s = src
s = rep(s, '(1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD) + 0.2 * tf("nested_tmbG", n)),\n    "focal lmer + ML refit',
        '(1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD + 0.5 * J) + 0.2 * tf("nested_tmbG", n)),\n    "focal lmer + ML refit')
s = rep(s, '(1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD)', '(1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD + 0.5 * (S + I))')
s = rep(s, SATT22, 'tf("x22_lmer", n) * (1 + 0.1 + R_SATT + R_SIM + R_OVERHEAD + 0.5 * ifelse(n == 384, 40, 80))')
s = rep(s, 'tf("n3_lmer", n) * (1 + 1 + R_SATT + R_SIM + R_OVERHEAD)', 'tf("n3_lmer", n) * (1 + 1 + R_SATT + R_SIM + R_OVERHEAD + 0.5 * (K + K * C))')
s = rep(s, 'tf("gr_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD)', 'tf("gr_lmer", n) * (1 + R_SATT + R_SIM + R_OVERHEAD + 0.5 * P)')
scen["S5_exact_influence_in_V1"] = s

# S6: combined S1 + S2 + S3 + S4 (influence excluded, i.e. validated only in V2-infl)
s = scen["S1_lme4_2.1_derivskip_plus_satt22"]
s = rep(s, 'tf("nested_lmer", n) * (1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD) + 0.2 * tf("nested_tmbG", n)),\n    "focal lmer + ML refit',
        'tf("nested_lmer", n) * (1 + R_ML + R_RI + R_SATT + R_SIM + R_OVERHEAD + 6.5 * (n <= 400)) + 0.2 * tf("nested_tmbG", n)),\n    "focal lmer + ML refit')
s = rep(s, 'tf("crossed_lmer", n) * (1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD)',
        'tf("crossed_lmer", n) * (1 + R_ZCP1 + 0.3 + R_SATT + R_SIM + R_OVERHEAD + 17 * (n <= 400))')
s = rep(s, 'tf("x22_lmer", n) * (1 + 0.1 + 3.1 + R_SIM + R_OVERHEAD) + tf("x22_lmer_zcp", n)',
        'tf("x22_lmer", n) * (1 + 0.1 + 3.1 + R_SIM + R_OVERHEAD) + 24.7 * (n <= 400) + tf("x22_lmer_zcp", n)')
s = rep(s, "R_ALLFIT <- 20", "R_ALLFIT <- 28")
s = rep(s, 'with(g, 200 * ifelse(design == "nested", tf("nested_lmer", n), tf("crossed_lmer", n)))',
        'with(g, (1 + 20 * 200 * 3 / 500) * ifelse(design == "nested", tf("nested_lmer", n), tf("crossed_lmer", n)))')
scen["S6_combined_S1_to_S4"] = s

for k, v in scen.items():
    open(os.path.join(out, k + ".R"), "w").write(v)
    print("wrote", k)
