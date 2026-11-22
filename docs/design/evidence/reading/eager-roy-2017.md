# Eager and Roy (2017)

**Reference as checked.** Eager, C., & Roy, J. (2017). *Mixed effects models are sometimes terrible* (arXiv:1701.04858) [Preprint]. arXiv. https://doi.org/10.48550/arXiv.1701.04858

**Match.** The arXiv record (read 21 November 2026) agrees on authors, title and identifier: version 1, submitted 5 January 2017, a write-up of a poster at the Linguistic Society of America's 2017 meeting, with only this version. arXiv's DOIs are registered with DataCite, not Crossref, which is why a Crossref search did not find it.

**Platform and pages read.** arXiv, the abstract page in the browser and the PDF (24 pages), downloaded with the maintainer's permission to a temporary folder outside the repository and read as extracted text, 21 November 2026: abstract (p. 1), the description of convergence (p. 3), the method (p. 11), Table 1 and its discussion (p. 12) and Appendix A (p. 22). The PDF was deleted afterwards.

## Claims checked

03-execution-plan.md lists the paper for 'the conditions'. The evidence (B/tables/literature_extraction.tsv, L17; B/tables/hpc_simulation_plan.tsv, H4; reports.json, research:re-structure) takes the following from it.

1. lme4 non-convergence with known non-zero variances: complex logistic 82% (2,500 simulations), simple logistic 7% (20,000), complex linear 14%; RStan near 0. **Confirmed, with a condition the evidence leaves out.** Table 1 (p. 12) gives, for lme4 and RStan: simple linear 0% and .009% (80,000 simulations), simple logistic 7% and .002% (20,000), complex linear 14% and 3% (2,500), complex logistic 82% and <.001% (2,500). These rates count a fit as non-converged when its gradient check exceeded 0.01, five times lme4's default of .002 (p. 11). With the default tolerance, Appendix A (p. 22) gives simple logistic 22% and complex logistic 98%, the other rates being about the same. The authors also note that lme4's default tolerance had been raised from .001 to .002 (p. 3).
2. The conditions. **Recorded.** The 'simple' simulations follow Barr et al. (2013): 24 subjects, 24 items and one binary predictor, for linear and logistic models. The 'complex' simulations vary imbalance across the data and use one binary and one three-level predictor, with a maximal by-subject random-effects structure, 30 to 60 subjects and no items (abstract, p. 1). The data are generated with non-zero variance for every random intercept and slope, so non-convergence cannot reflect zero variances (abstract).
3. 'Non-convergence is not proof of over-parameterisation (contradicts the parsimonious convergence hypothesis)'. **Confirmed** (abstract): under the hypothesis non-convergence counts as evidence against a more complex structure, which the simulations do not support; with imbalance, lme4 had moderate to high non-convergence that can lead researchers to drop random effects wrongly.
4. The lme4 version is not stated in the passages read; the paper predates lme4 2.x, as the evidence says ('pre-2018 lme4').

## Fields that differ from the repository's records

- reports.json gives no DOI; arXiv's DOI is 10.48550/arXiv.1701.04858.
