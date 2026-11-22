# Veríssimo (2023)

**Reference as checked.** Veríssimo, J. (2023). When fixed and random effects mismatch: Another case of inflation of evidence in non-maximal models. *Computational Brain & Behavior, 6*(1), 84–101. https://doi.org/10.1007/s42113-022-00152-3

**Match.** Crossref (queried 21 November 2026) gives volume 6, issue 1, pages 84–101; the publisher's page gives volume 6, pages 84–101 (2023) and does not show the issue. Published online 15 September 2022. Licence CC BY 4.0. Not retracted or corrected. The author's surname carries an accent (Veríssimo).

**Platform and pages read.** Springer Nature Link, HTML full text (open access), read 21 November 2026: Abstract, 'Model Comparisons With Synthetic Data' and General Discussion, 'Recommendations'. Places are given by section.

## Claims checked

03-execution-plan.md lists the paper without a specific point. The evidence (B/tables/literature_extraction.tsv, L13; B/tables/hpc_simulation_plan.tsv, H2; reports.json, research:re-structure, recommendation 2, where it supports keeping correlated nuisance slopes, ordering key k3) takes the following from it.

1. What a 'mismatch' is. **Confirmed and clarified.** A mismatch occurs when a model includes the random slope for the effect of interest but omits the random slopes of predictors that correlate with it, such as a covariate (Abstract; Recommendations). It is not the plain omission of the focal slope.
2. Mismatches lead to underestimated random variance and inflated Bayes factors. **Confirmed** (Abstract), from Bayesian model comparisons on a synthetic dataset with two correlated, within-participant, item-level continuous predictors, one focal and one a covariate ('Model Comparisons With Synthetic Data'). The evidence is a demonstration on one generated dataset, not a Monte Carlo estimate of error rates.
3. Recommendations: fit maximal models, decorrelate predictors, residualise the random effects. **Confirmed** (Abstract; Recommendations). The Recommendations section adds two points that bear on ordering key k3: predictors other than the effect of interest can be left out of the random part without harm only if they do not correlate with the effect of interest and are not themselves of interest, and even a maximal model can contain a mismatch when a correlated predictor cannot have a random slope within the clusters (for example a between-participant variable).

## Fields that differ from the repository's records

- B/tables/reference_verification.tsv and reports.json give no issue number; Crossref gives issue 1. reports.json and the B tables spell the surname 'Verissimo' without the accent. Both files are frozen evidence and are not edited; any citation in the design record should read 'Veríssimo' and '6(1)'.
