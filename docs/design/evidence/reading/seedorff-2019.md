# Seedorff et al. (2019)

**Reference as checked.** Seedorff, M., Oleson, J., & McMurray, B. (2019). *Maybe maximal: Good enough mixed models optimize power while controlling Type I error* [Preprint]. PsyArXiv. https://doi.org/10.31234/osf.io/xmhfr

**Match.** Crossref (queried 21 November 2026) and the PsyArXiv page agree on authors, title and DOI; posted 25 January 2019, version 1. Licence CC BY 4.0. Crossref records no published version (no relation to a journal article, and a bibliographic search for the title finds only the preprint), so it is still a preprint.

**Platform and pages read.** PsyArXiv on OSF, the preprint's PDF read in the browser's PDF viewer (57 pages), 21 November 2026: abstract (p. 2), the description of the simulation design and the General Discussion (pp. 34–38). Page numbers are the preprint's own.

## Claims checked

03-execution-plan.md lists the paper without a specific point. The evidence (B/tables/literature_extraction.tsv, L05; B/tables/hpc_simulation_plan.tsv, H1; reports.json, research:re-structure, recommendation 3) takes the following from it.

1. Considering the whole space of candidate random-effects structures with AIC gives the best power while holding Type I error at the nominal level. **Confirmed** (abstract, p. 2; General Discussion, pp. 35–36). Model-space selection beat incremental (forward or backward) procedures, AIC and AICc performed best, AICc being preferred for small samples, and BIC performed poorly.
2. 'Published support for selection rules is limited to LRT and AIC (Matuschek et al., 2017; Seedorff et al., 2019, a preprint)' (reports.json). **Consistent**: this preprint supports AIC over the model space, not LRT, and it is not peer reviewed.
3. Guidance on non-convergence. **Confirmed and specified** (pp. 37–38). Non-convergence was much more common in logistic than in linear models and rose with the complexity of the fitted structure; it was 'not a straightforward sign' that the data support a simpler model. When a model with random slopes and their covariances fails to converge, dropping the covariances while keeping the slopes kept Type I error at .05 with a moderate loss of power, whereas dropping a slope raised Type I error and intercept-only models should not be used. This matches the order of the ladder in 02-decisions.md (Q3): correlations go before protected slopes.
4. Further findings, not used in the repository yet: the maximal model kept Type I error for between-subject effects with power close to the generating model, but cost power for within-subject effects when the generating structure was simpler (pp. 34–35); Satterthwaite degrees of freedom sometimes exceeded the number of subjects, with little effect on Type I error or power (p. 36); aggregating within subject and item changed Type I error and power little and lowered non-convergence (pp. 36–37).
5. Simulation design, for H1. Crossed subjects and items with a between-subject factor (two groups of 25, 50 subjects), 20 items, a two-level within-subject factor and 5 repetitions per subject, item and level (10,000 observations per data set), linear and logistic models fitted with lme4 (Laplace for logistic), and a correlation of .8 between subject intercepts and slopes in the maximal generating model.

## Fields that differ from the repository's records

- B/tables/reference_verification.tsv marks the year as confirmed only by a secondary listing; Crossref confirms 2019 (posted 25 January 2019). No field differs.

## Questions for a person

None.
