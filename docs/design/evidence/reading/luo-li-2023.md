# Luo and Li (2023)

**Reference as checked.** Luo, W., & Li, H. (2023). A comparison of methods for specifying optimal random effects structures. *Methodology, 19*(4), 365–386. https://doi.org/10.5964/meth.9601

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 19, issue 4, pages 365–386 and DOI. Published 22 December 2023. Licence CC BY 4.0. Not retracted or corrected.

**Platform and pages read.** PsychOpen (Methodology), HTML full text (open access), read 21 November 2026: Abstract, Method ('Data Generation and Design Factors', 'Model Selection Algorithms') and Discussion ('Implications'). The HTML has no page numbers, so places are given by section.

## Claims checked

03-execution-plan.md lists the paper without a specific point. The evidence (B/tables/literature_extraction.tsv, L07, B/tables/hpc_simulation_plan.tsv, H2 and H5, and reports.json, research:re-structure) takes the following from it.

1. The maximal approach and best-path forward and backward searches are 'desirable' for within-cluster and cross-level focal predictors. **Confirmed** (Abstract; Implications). The authors add that best-path forward search is the recommendation when the maximal model has convergence problems.
2. For a cluster-level focal predictor, Level-1 random slopes are not essential. **Confirmed** (Abstract; Implications).
3. Random slopes of within-cluster control variables raise power for the within-cluster focal effect, most of all with small samples and a large slope variance. **Confirmed** (Abstract; Implications).
4. Not in the repository yet, and relevant to it: the authors advise against AIC- and BIC-based selection, especially in small samples (Implications), and their forward and backward searches tested variance components with the restricted LRT of RLRsim and covariances with an ordinary LRT, both at α = .20 (Model Selection Algorithms).
5. Simulation grid, for H2 and H5. Two-level cross-sectional design with two Level-1 predictors (focal X1, control X2, correlated .3), two Level-2 predictors and one cross-level interaction (X1 × W1); 10, 50 or 100 clusters of 10, 25 or 50; fixed effects 0 or 0.5; residual variance 1; intercept variance 0.25; slope variances 0.05, 0.25 or 0.5; random-effect correlation 0.5; 162 conditions with 1,000 replications each; 14 candidate structures fitted by REML in lme4 (Data Generation and Design Factors; Model Selection Algorithms).

## Fields that differ from the repository's records

None.
