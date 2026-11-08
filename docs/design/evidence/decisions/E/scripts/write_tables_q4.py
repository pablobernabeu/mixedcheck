"""Write the Q4 tables (frameworks reviewed; what data can and cannot reveal;
declaration fields and missing-field behaviour) as CSV."""
import csv, sys
out = sys.argv[1]

frameworks = [
 # name, version/date checked, what is declared, required inputs, format, R/Python, licence, what it lacks for lmecheck, source
 ("DeclareDesign (+fabricatr, randomizr)", "DeclareDesign 2.0.0 (CRAN 2026-10-25); fabricatr 2.0.0; randomizr 2.0.1",
  "MIDA: model, inquiry (estimand), data strategy (sampling, assignment incl. clusters and blocks, measurement), answer strategy; fabricatr declares nested and cross-classified levels (add_level, nest_level, cross_levels, link_levels)",
  "A design is R code; diagnosis needs at least one inquiry and an estimator mapped to it",
  "R objects (code), not a data file", "R only", "MIT",
  "Declares designs for simulation; does not read real data or check a declaration against it; no file format to share with Python. randomizr does check data at assignment time ('All units within a cluster must be in the same block')",
  "https://raw.githubusercontent.com/cran/DeclareDesign/master/NAMESPACE; cran/fabricatr man/cross_levels.Rd, man/link_levels.Rd; cran/randomizr R/helper_functions.R"),
 ("faux", "1.2.4 (CRAN 2026-03-11)",
  "Within and between factors (sim_design), random factors crossed or nested (add_random(..., .nested_in = NULL) crosses by default), random effects (add_ranef), contrasts; design stored as an attribute and exportable with json_design(); codebook() writes Psych-DS 0.1.0 JSON-LD",
  "Factor levels, n, mu, sd, r; column roles only for codebook (identifier, levels, na)",
  "R list or JSON", "R only", "MIT",
  "check_mixed_design() takes subject and item columns as arguments and fits a null lmer; no inference or checking of structure from data; JSON describes a simulated design, not a dataset",
  "cran/faux man/add_random.Rd, man/check_mixed_design.Rd, R/check_mixed_design.R, man/codebook.Rd, man/json_design.Rd"),
 ("designr", "0.1.13 (CRAN 2023-05-05)",
  "fixed.factor(); random.factor(name, groups =) declares which fixed or random factors a random factor is nested in; design.formula() derives the maximal lme4 formula (each random factor gets slopes for every fixed factor it is not grouped by)",
  "Factors and their nesting", "R S4 objects; write.design.json() writes experimental codes, not the design semantics", "R only", "GPL-3",
  "Closest precedent for a declaration-implied maximal structure, but from declared design only; never checks real data",
  "cran/designr R/methods.R (design.formula), man/random.factor.Rd, man/write.design.Rd"),
 ("simr", "1.0.11 (CRAN 2026-09-11)",
  "Structure implied by a fitted (or makeLmer-built) model; extend(along =, within =) names the unit to enlarge and the grouping within which to extend",
  "A fitted lme4 model and its data, or formula plus parameter values", "R objects", "R only", "GPL (>= 2)",
  "No explicit declaration of nesting, randomisation unit or roles; inherits whatever the model frame encodes, including reused labels",
  "cran/simr man/extend.Rd; Green & MacLeod (2016)"),
 ("mixedpower", "0.1.0 (GitHub only, not on CRAN)",
  "fixed_effects (names), simvar (the random variable to vary), R2power adds a second random variable (R2var, R2level) for crossed designs",
  "A fitted lme4 model, its data, fixed_effects, simvar, steps, critical_value, n_sim", "R arguments", "R only",
  "DESCRIPTION says 'GNU GENERAL PUBLIC LICENSE' without a version",
  "Unit names are declared as arguments but structure is taken from the model; no file format",
  "https://raw.githubusercontent.com/DejanDraschkow/mixedpower/master/R/meta_functions.R; Kumle et al. (2021)"),
 ("Frictionless Table Schema / Data Package v2", "v2.0 released 2024-06-26; R frictionless 2.0.1 (CRAN 2026-10-29); Python frictionless 5.21.0 (PyPI 2026-10-15)",
  "Field name (required), type and format, constraints, categories and categoriesOrdered (level order), missingValues per table or field (v2: labelled missing values), primaryKey, uniqueKeys, foreignKeys, fieldsMatch; extensions through $schema profiles; field descriptors may carry other properties",
  "Only fields[].name", "JSON (or YAML) descriptor beside CSV", "R and Python",
  "Packages MIT (specification licence not checked)",
  "No notion of nesting semantics, randomisation, roles relative to assignment, time order or estimands. R frictionless 2.0.0 NEWS: field.categories and schema.fieldsMatch not yet supported, so level order would not round-trip through it in R",
  "https://raw.githubusercontent.com/frictionlessdata/datapackage/main/content/docs/standard/table-schema.mdx; .../extensions.mdx; .../blog/2024-06-26-v2-release.md; cran/frictionless NEWS.md"),
 ("Psych-DS", "R psychds 0.1.0 (CRAN 2026-10-15); faux::codebook schemaVersion 'Psych-DS 0.1.0'",
  "Dataset metadata (schema.org Dataset JSON-LD), variableMeasured with descriptions, levels, identifiers, missing codes; file-naming rules; columns must appear in variableMeasured",
  "dataset_description.json with variableMeasured", "JSON-LD + CSV directory layout", "R (validator bundles JavaScript, needs Node.js >= 18)", "MIT",
  "Documents variables, not design relations; validator needs Node.js",
  "cran/psychds DESCRIPTION; https://raw.githubusercontent.com/psych-ds/psych-DS/master/README.md"),
 ("DDI (Codebook 2.x, Lifecycle 3.x, CDI 1.0)", "DDI-CDI 1.0 published January 2025 (DDI Alliance announcement via search)",
  "CDI data-structure components with roles: identifier, measure, attribute, dimension; Codebook and Lifecycle document variables, universes and analysis units for survey archives",
  "Archive-oriented metadata", "XML (Codebook, Lifecycle); XML and RDF (CDI)", "R: DDIwR 0.22 (GPL >= 3) converts data to and from DDI, SPSS, Stata, SAS and R, including user-declared missing values; no Python reader checked", "Open specifications",
  "Too heavy for a two-language package; offers the identifier/measure/attribute vocabulary only. docs.ddialliance.org was unreachable, so CDI class definitions were read from search snippets only",
  "WebSearch snippets of docs.ddialliance.org and ddialliance.org news; cran/DDIwR DESCRIPTION"),
 ("CONSORT 2010 extension to cluster randomised trials", "Campbell et al. (2012); CONSORT 2025 core statement (Hopewell et al., 2025); no 2025-aligned cluster extension found",
  "Reporting items: definition of the cluster and how design features apply to clusters (3a); sample size with number of clusters, cluster size, ICC and its uncertainty (7a); stratification or matching; allocation based on clusters; how clustering was taken into account (12a); results with an ICC for each primary outcome (17a, per checklist copies)",
  "A reporting checklist, not a data format", "Checklist", "n/a", "n/a",
  "Maps onto declaration fields (units, assignment.unit, assignment.blocks, estimand level) and onto Stream B outputs (ICC needs the outcome: tier T1)",
  "WebSearch: PubMed 22951546 listing; Springer supplementary checklist copies; catalogue L7-03 verifier"),
 ("Preregistration templates", "OSF Preregistration; AsPredicted; ESM template (Kirtley et al., 2021); ERP guidelines and template (Paul et al., 2021); machine-readable hypotheses with scienceverse (Lakens & DeBruine, 2021)",
  "Free-text sections on design, sampling, variables and analysis; the ESM template adds sampling schemes and time-outs; the ERP guidelines add preprocessing steps",
  "Prose", "Prose (scienceverse: JSON)", "scienceverse: R", "Templates CC licences (not checked)",
  "No template specific to mixed models was found; a search found only general templates and advice to state the formula, random-effects structure and convergence fallback in advance. A hashed declaration plus the Stream B ladder file can be attached to any of them",
  "WebSearch results (SFB1252 preregistration talk; APS and KU Leuven records; MPI and COS pages)"),
]
with open(f"{out}/q4_frameworks.csv", "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["framework", "version_checked", "what_is_declared", "required_inputs", "format", "languages", "licence", "gap_for_lmecheck", "source"])
    w.writerows(frameworks)

inference = [
 # quantity, inferable from data alone?, how, failure modes, evidence, decision
 ("Whether two grouping factors are nested, crossed or partially crossed (as labelled)", "Yes, exactly", "Incidence of labels (m(b), fill rate, components)", "None for the labels themselves; requires canonical IDs (L1-20)", "E4 on Exam, ScotsSec, star, guImmun, InstEval", "Compute always (T0, exact parity)"),
 ("Whether a repeated inner label means the same unit (crossing, mobility) or a reused local label (nesting)", "No", "Identical label incidence under both truths (E1 part A); outcome-based likelihood comparison is T2 and weak", "E1: when the label SD was 0.05-0.1 (residual SD 1) the true structure won in only 19.5-82.5% of replicates, with 2.5-42% ties; at SD 0.4 with 20 schools it won in 96-100%", "E1 (lme4 1.1-35.1, 200 replicates per cell)", "Declare id_scope; without it report 'ambiguous' and never recode"),
 ("Randomisation unit", "Only in clean, simple designs", "Rule R1: coarsest level within which treatment is constant", "E2: one miscoded row in 2,000 (0.05%) made R1 wrong in 45% of school-randomised datasets, 0.5% in 99.8%; stepped-wedge always wrong; 10 mostly-singleton families: wrong 8%", "E2 (numpy, 2,000 replicates per cell)", "Declare assignment.unit; offer R1 only as a draft; a declared unit with mixed treatment is a top-severity finding"),
 ("Whether assignment was randomised at all, and blocking versus chance balance", "No", "-", "A class-level covariate chosen by teachers looks like a class-randomised arm", "Logical", "Declare assignment.randomised and blocks"),
 ("Observation key", "No (circular)", "Minimal unique column sets", "Continuous measures are unique by chance: Reaction in sleepstudy; in Exam every minimal key contains a score, and (school, student) has 4 duplicated pairs", "E3 (sleepstudy, fhch2010, Exam)", "Declare observation.key; without it duplicates are informational only"),
 ("Local versus global ID scope in public data", "Detectable as a pattern, not provable", "Labels repeating under many outer units", "Exam: 322 of 650 student labels occur in more than one school (up to 34)", "E3/E4", "Raise 'probable local IDs' and ask for id_scope"),
 ("Time variable and its resolution", "Partly", "Numeric or date column increasing within unit", "Cannot tell occasion from dose or trial order from presentation order; time zone and resolution are not in the data", "Logical; L7-11, L7-12", "Declare observation.time; inference only as a suggestion"),
 ("Variable roles (baseline, post-assignment, mediator, outcome-derived)", "No", "-", "Timing relative to assignment is not stored in a data frame; only near-exact functions of the outcome are detectable, and only outcome-aware (T2)", "Logical; critic gap 'declared variable roles'", "Declare variables; role checks otherwise not assessable"),
 ("Focal estimands", "No", "-", "-", "Logical", "Declare estimands; otherwise all fixed terms are treated as focal"),
 ("Within/between status of predictors per grouping factor", "Yes, exactly", "Variance decomposition by group on the analysis sample", "Changes after listwise deletion (L1-09)", "performance::check_group_variation exists (proposal)", "Compute always"),
 ("Dyad member roles and distinguishability", "Partly", "Cluster size 2 plus a column varying within cluster", "Fires on sibling sex or twin order (L7-08 verifier)", "Catalogue L7-08", "Declare dyad block"),
 ("EEG reference scheme", "Partly", "Sum over channels within trial is zero under average reference", "Only when all channels are present", "Catalogue L7-17 (simulation: max trial mean 3e-16)", "Declare eeg.reference"),
]
with open(f"{out}/q4_inference_reliability.csv", "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["quantity", "inferable_from_data_alone", "method", "failure_modes_and_numbers", "evidence", "decision"])
    w.writerows(inference)

fields = [
 # block/field, required when, default if absent, behaviour when absent, checks enabled when present, precedent
 ("schema_version", "Always", "-", "File rejected", "Version-specific reading and coercion", "Frictionless $schema; registry versioning (L6-02)"),
 ("goal", "Never", "exploratory", "Findings graded as exploratory", "confirmatory: requires units, observation.key, variables and estimands (JSON Schema if/then); prediction: switches Stream A to leave-cluster-out validation", "Critic gap on predictive goals"),
 ("features", "Never", "[]", "Generic wording; domain checks chosen from data patterns with 'inferred' wording", "Selects domain checks and wording; each tag requires the blocks it depends on (dyadic -> dyad; eeg -> eeg; cluster_randomised -> assignment)", "L7-22 verifier: compositional tags, not one design type"),
 ("table (Frictionless subset)", "Never", "Types inferred by each language's reader", "Parity downgraded to best effort; NA tokens and level order taken from defaults that differ between R and pandas (L1-20)", "Exact typing, NA tokens (incl. labelled sentinel codes), explicit level order via categories, primaryKey", "Frictionless Table Schema v2"),
 ("units[].name, columns", "If units is given", "-", "Grouping factors taken from the formula", "Declared-versus-observed structure checks", "fabricatr levels; designr random.factor"),
 ("units[].nested_in", "Never", "No declared parent", "Relation inferred from incidence and reported as 'inferred'", "Nesting check; composite ID building (L2-22)", "designr groups =; faux .nested_in"),
 ("units[].id_scope", "Required whenever nested_in is given (dependentRequired)", "-", "File rejected if nested_in is present without it", "within_parent: suite builds a collision-free composite ID and offers school/class syntax; global: a label under two parents is mobility, crossing or an error", "Resolves L1-01/L7-01; E1 shows data cannot"),
 ("units[].membership", "Never", "fixed", "Units under more than one parent are flagged", "may_change_over_time (needs observation.time): membership-change table and crossed suggestion; multiple: multiple-membership warning (outside engines)", "L7-01 verifier"),
 ("crossings", "Never", "[]", "Crossing inferred from incidence", "Connectivity, per-factor tables, list balance when a list column is declared", "L1-14, L7-14, L7-15"),
 ("observation.key", "Required when goal = confirmatory", "-", "Duplicates reported as information only (L1-15, L7-19)", "Duplicate-key errors, double-import detection, row fingerprint for model comparisons", "Frictionless primaryKey"),
 ("observation.time", "Required for longitudinal, intensive_longitudinal and stepped_wedge features", "-", "Longitudinal checks not run; a candidate time column may be suggested", "Lag construction, semivariograms, mobility within/across occasions, time-zone handling", "L7-09 to L7-12"),
 ("assignment[]", "Required for cluster_randomised, multisite, stepped_wedge, partially_nested", "-", "Randomisation checks not run; R1 offered only as a draft", "Constant-within-unit check, unit-in-random-part check, design df, blocks in fixed part, partially nested advice", "randomizr clusters/blocks; CONSORT cluster 3a, 7a, 12a"),
 ("variables{}", "Required when goal = confirmatory", "-", "Role checks not assessable; outcome-blind mode cannot exclude an undeclared outcome", "Post-assignment adjustment warning for total-effect estimands; outcome-derived predictors; bounds for ceiling checks; measurement level for family suggestions", "Critic gap on roles; DDI identifier/measure/attribute"),
 ("estimands[]", "Required when goal = confirmatory", "-", "All fixed terms treated as focal; 'consequence for declared estimand' not assessable; ladder cannot prioritise focal slopes", "Severity grading, ladder order (focal slopes kept longest), cross-level interaction rule", "DeclareDesign inquiry; proposal severity fields"),
 ("dyad", "Required with feature dyadic", "-", "-", "Role completeness, Pearson r or ICC, negative-dependence warning, marginal 2x2 advice", "L7-08"),
 ("eeg", "Required with feature eeg", "-", "-", "Reference-scheme-aware trial grouping advice, retained trials per cell", "L7-17"),
 ("imputation", "Required with feature multiple_imputation", "-", "-", "Per-imputation audits, rates across imputations, warning when the imputation model ignored clustering", "Critic gap on multiple imputation"),
 ("provenance", "Never", "-", "Reported as 'no attestation'", "created timestamp, author, outcome_seen attestation and data hash recorded with the canonical SHA-256 of the declaration", "L1-16, L6-22, L7-22 verifier (hash and timestamp)"),
 ("x-* properties", "Never", "-", "-", "Kept, hashed, never interpreted", "Extension escape hatch"),
]
with open(f"{out}/q4_declaration_fields.csv", "w", newline="", encoding="utf-8") as fh:
    w = csv.writer(fh)
    w.writerow(["field", "required_when", "default_if_absent", "behaviour_when_absent", "enables_when_present", "precedent_or_catalogue_item"])
    w.writerows(fields)
print("ok")
