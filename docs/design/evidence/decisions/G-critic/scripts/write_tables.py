import csv, os
OUT = "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/G-critic/out"
S = "/tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad"

hpc = [
 # study, source, purpose, release, cpu_h_as_stated, memory_need, in_F_budget, recommendation
 ("HPC-0 pilot + ARC environment checks", "F, D", "module/Apptainer/QoS/credit/CPU flags; re-time lme4 2.1-0", "before M1", "~1", "2 GB", "yes (placed in M6 by the draft plan)", "Run in M0/M1: it fixes the container route (glmmTMB needs R>=4.5 via Deriv), the timing multipliers and the memory classes that every later budget uses"),
 ("V0 deterministic audits", "F", "known-answer and property tests", "every release", "0 (CI)", "-", "yes", "Keep in CI; not HPC"),
 ("V1 Gaussian null bank", "F", "false-flag rates of every check", "1.0", "125 (75-250)", "2 GB", "yes", "Re-cost in HPC-0 with the real suite overhead (budget.R assumes suite checks = 1 fit)"),
 ("V1 exact cluster-deletion influence refits", "F-verify", "exact LOCO refits inside the null bank", "1.0", "+1,120 (total Phase 1 ~3,050)", "2 GB", "no", "Default influence = one-step approximation; exact refits only in V2-infl at 2,000 reps (C's report figure 'influence sensitivity' must name which)"),
 ("V2 misspecification modules", "F", "detection, consequence, cross-talk, action value", "1.0", "56 (34-112)", "2 GB", "yes", "Priority modules only for 1.0"),
 ("V2-infl", "F / F-verify", "influence at 200 reps (verifier: 2,000 for MCSE target)", "1.0", "1.5 at 200 reps (~15 at 2,000)", "2 GB", "partly", "Use 2,000 reps"),
 ("V3 singularity/convergence/boundary criteria", "F + B H3", "validate ONE registry criterion", "1.0", "115 (69-229)", "2 GB; crossed allFit heavier", "yes", "Validate the unified criterion (A's statuses) that SR-P consumes"),
 ("V4 VC tests and PB-LRT", "F", "boundary tests", "1.0 optional", "89 (53-178)", "2 GB", "yes", "Defer unless 1.0 reports variance-component tests"),
 ("V5-H1 stopping rules on fixed ladder", "B H1 via F", "default-rule decision", "1.0 (paper core)", "662 capped / 1,432 uncapped (F); ~650 uncapped with current lme4 (F-verify); B's own 200 assumed 0.07 s fits", "2 GB; KR >2 GB at n>3,072", "yes", "Re-cost with the actual SR-P walk: second optimiser per accepted rung, suite gradient/Hessian, Satterthwaite on the selected rung (budget.R uses 1 + 7 x 0.5 fits)"),
 ("V5-H2/H5", "B via F", "ordering; few-cluster education designs", "1.0", "41", "2 GB", "yes", "H5 needs CR2 (clubSandwich, GPL-3, R-only) as comparator"),
 ("V6 design-analysis calibration", "F + B H6", "calibrate pre-fit predicted probabilities", "1.0 in F", "73 (44-146)", "2 GB", "yes", "Defer: B's verified Release 1 ships no design-analysis predictions"),
 ("V7 cross-language parity", "F", "statsmodels parity", "1.0", "~1 (Python only)", "2 GB", "yes", "Extend to rung agreement on nested and crossed-VC cells (H8-lite), tens of CPU-h"),
 ("A conformance study", "A open item", "200-500 reps per benchmark design x 5 engines + 1e5-1e6-row timing/memory runs", "before tiers ship", "not estimated", ">2 GB (statsmodels peaked 1.6-1.7 GB at 40,000 rows)", "no", "Budget separately; one high-memory timing study; statsmodels capped at ~4e4 rows; experimental Rust engines only if one ships"),
 ("V8-V10 GLMM", "F", "GLMM validation", "1.1", "270 central", "2 GB", "yes", "Keep no-refit calibration (C's bootstrap grids would be 920-2,200 per family)"),
 ("C per-check bootstrap grids", "C", "false-flag/detection per check", "1.0/1.1", "230 (lmer), 520 (glmmTMB gaussian), 920-2,200 per GLMM family", "2 GB", "no (superseded by V1/V2 design)", "Mark superseded by the shared null bank"),
 ("C disclosure-attack tests", "C open item", "differencing and reconstruction of suppressed cells", "1.0", "not estimated", "-", "no", "Deterministic; run as unit/property tests in CI, not on ARC"),
 ("E E1 extension (outcome-aware nesting hint)", "E open item", "1,000 reps over label/school grids", "-", "not estimated", "2 GB", "no", "Drop: E's verified decision excludes outcome-based structure choice on outcome-blindness grounds, so the result cannot change the design"),
 ("E zoo per-fixture validation grids", "E open item", "false-flag/detection per fixture family", "1.0", "not estimated", "2 GB", "no", "Merge into V1/V2 by using the zoo generators as the DGMs"),
 ("B H4, H8, H10", "B", "GLMM back-off, engine parity of rung, Bayesian/MAP calibration", "later", "~400, ~100, ~200", "2 GB; MCMC more", "deferred (F)", "H8-lite inside V7; others after 1.0"),
 ("B KR / parametric bootstrap inference", "B-verify", "inference on selected rung", "1.0", "KR ~21 s per fit at n=1,536; PB ~95 CPU-h per cell", ">2 GB for KR at large n", "partly", "Restrict to smallest cells or subsamples"),
]
with open(os.path.join(OUT, "G_hpc_register.csv"), "w", newline="") as f:
    w = csv.writer(f); w.writerow(["study_or_run","source_key","purpose","release","cpu_h_as_stated_by_source","memory_need","in_F_budget","recommendation"]); w.writerows(hpc)

tax = [
 ("status field","availability","available | not_available:<engine_missing|package_missing|capability_missing|declaration_missing|not_expressible|too_large|privacy_suppressed|planned_<version>>","Replaces E's 'not assessable' for a missing declaration and gives C's suppression a status","E Q4; C Q5; D Q6"),
 ("status field","assessability","adequate | weak | not_assessable (+ reason: prerequisite_unmet, low_detection)","Statistical only (F V2 thresholds; catalogue prerequisite rule)","F V2; catalogue L5 handling"),
 ("status field","finding","consistent | detectable_inconsequential | consequential","Orthogonal to assessability (catalogue verifier)","catalogue verifier on severity"),
 ("status field","optimisation","at_optimum | near_optimum | not_converged | not_certified | objective_unavailable | objective_offset_registered | contract_mismatch","One criterion for A's contract, B's SR-P and F's V3; 'near_optimum' must not reuse the word used for thresholds; SR-P needs an explicit rule for near_optimum and not_certified (large q)","A Q1.contract; B Q3.3; F V3"),
 ("status field","threshold_proximity","clear | near_threshold","Also applied to formatted numbers at reporting precision (string parity)","proposal; C Q5"),
 ("status field","validation","validated(study, language, engine, version range) | descriptive | outside_validated_range","Python inherits R-validated thresholds only after V7 shows statistic parity","F Q9; parent R1 gate"),
 ("hash","registry_sha256","bytes of compiled registry JSON","public","D Q7"),
 ("hash","declaration_hash","SHA-256 of RFC 8785 form; forbid 'categories' on ID-role columns so declarations carry no identifiers","public if no identifiers","E Q4"),
 ("hash","ir_hash","canonical IR: terms, coding, centring constants as decimal strings, reference levels","public","A contract; B Step 0"),
 ("hash","design_plan_hash","language-neutral plan: IR rungs, protected set, rule id/version, terminal state, declarations hash","public; must match across languages (M3 gate)","B Q3.3; parent M3"),
 ("hash","execution_binding_hash","engine, version, optimiser settings, per-rung encoding and expressibility","public; language/engine specific","B Q3.3"),
 ("hash","analysis_table_commitment","HMAC-SHA-256 (key in _INTERNAL sidecar) of canonical analysis table + observation keys","shareable outputs use keyed form; unkeyed form only internal/parity","proposal fingerprint; C results JSON; E-verify parsed-table hash"),
 ("hash","data_file_sha256","raw file bytes when a file path exists","internal/provenance; keyed in shareable outputs","E-verify"),
 ("hash","outcome_access_commitment","HMAC of outcome column for the access log","never unkeyed in any shareable file (all-but-one attack)","B Q3.4"),
 ("hash","results_sha256","bytes of the written results JSON","public for shareable results; travels with .qmd export","C Q5"),
 ("json profile","hashable","declarations, plans: strings, integers within +/-2^53, decimals <= 15 significant digits; centring constants as decimal strings; no null/NaN/Inf","E strict rules","E-verify"),
 ("json profile","data","results, contract/BYO: null with status objects, doubles at shortest round-trip (17 sd), explicit non-finite encoding","A contract (glmmTMB NA SEs), C results","A; C"),
]
with open(os.path.join(OUT, "G_status_and_hash_taxonomy.csv"), "w", newline="") as f:
    w = csv.writer(f); w.writerow(["kind","name","values_or_input","rule","source_keys"]); w.writerows(tax)
print("written")
