# Oberauer (2022)

**Reference as checked.** Oberauer, K. (2022). The importance of random slopes in mixed models for Bayesian hypothesis testing. *Psychological Science, 33*(4), 648–665. https://doi.org/10.1177/09567976211046884

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on author, title, journal, volume 33, issue 4, pages 648–665 and DOI. First published online 31 March 2022. Licence CC BY-NC 4.0. Not retracted or corrected.

**Platform and pages read.** Sage Journals, HTML full text (open access), read 21 November 2026: Abstract, Simulation 1 (Method) and the passages that state the recommendation. Places are given by section.

## Claims checked

03-execution-plan.md lists the paper without a specific point. The evidence (B/tables/literature_extraction.tsv, L12; B/tables/hpc_simulation_plan.tsv, H10; reports.json, research:re-structure) takes the following from it.

1. Without random slopes, Bayesian mixed models often give strong Bayes factors for population effects that do not exist. **Confirmed** (Abstract, over five simulations).
2. Including random slopes largely removes the risk of strong false positives but lowers the chance of strong evidence for true effects. **Confirmed** (Abstract).
3. Recommendation. **Confirmed, and the wording recorded in B/tables/literature_extraction.tsv matches the journal's text.** The author recommends starting by testing the support for random slopes in the data and removing them only if there is clear evidence against them (Abstract). L12 had flagged the wording as taken from an index page; the journal page gives the same recommendation.
4. H10 says the paper addresses Bayes factors, not the frequentist error of the whole procedure. **Consistent** with the paper: its error rates are proportions of Bayes factors above conventional evidence thresholds (Kass and Raftery's bands), not frequentist Type I error of a selection procedure.
5. Simulation conditions, for any later use. Five simulations: a 2 × 2 within-subject ANOVA design (Simulation 1: 20 subjects, 30 trials per subject and cell, residual SD 1, subject-level SDs equal across intercept and effects, focal effect 0, 0.25, 0.5 or 0.75), an ANOVA design with many cells (2), a multilevel regression (3), the effects of sample size and number of trials (4) and the calibration of Bayes factors (5), followed by a section on random slopes in brms, BayesFactor and JASP.

## Fields that differ from the repository's records

None.

## Questions for a person

None.
