# Scheipl et al. (2008)

**Reference as checked.** Scheipl, F., Greven, S., & Küchenhoff, H. (2008). Size and power of tests for a zero random effect variance or polynomial regression in additive and linear mixed models. *Computational Statistics & Data Analysis, 52*(7), 3283–3299. https://doi.org/10.1016/j.csda.2007.10.022

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 52, issue 7, pages 3283–3299 and DOI. Not retracted or corrected. The DOI that open_items_local_session.csv marks 'not checked' is correct.

**Platform and pages read.** ScienceDirect, HTML full text through Oxford's subscription, read 21 November 2026: Abstract, Section 3.1 (simulation set-up), Section 3.1's notes on software and the conclusions of Section 4. Places are given by section.

## Claims checked

1. open_items_local_session.csv: 'Size and power of zero-variance tests; V4 design precedents'. **Supported.** The paper compares nine tests of a zero random-effect variance in linear mixed models: three based on the restricted likelihood ratio test (RLRT) and six extensions of the F test, four of them calibrated by parametric bootstrap (Abstract). The bootstrap-based tests performed alike, tests based on approximate F distributions were usually the least powerful, and the chi-square mixture approximation for the RLRT was conservative, with a loss of power (Abstract). The settings, for V4: testing a random intercept in an unbalanced one-way design with a covariate (3 or 10 groups with 30 observations, 5 or 20 with 100, 5 or 100 with 500), testing linearity or constancy of a smooth term with penalised splines, and further settings with nuisance random effects (Section 3.1); critical values for the approximation were simulated with 100,000 draws, at the 5% level.
2. review-catalogue.md, L4 entry on variance-component tests: the best available test is an exact (R)LRT for a single variance component in an LMM with independent random effects (RLRsim, see Scheipl, Greven & Küchenhoff 2008). **Supported, with a refinement.** The exact null distribution of the RLRT is available for models with one random effect (Crainiceanu & Ruppert, 2004); the approximation that this paper evaluates extends it to models with several random effects, testing one variance with the others as nuisance, and the paper finds it a rapid, powerful and reliable alternative to the parametric bootstrap (Abstract; results). It is implemented in RLRsim by the first author (Section 3.1). The catalogue's 'exact' therefore holds for a single random effect; with further random effects the test is the approximation this paper validates.

## Fields that differ from the repository's records

- In reports.json (research:re-structure), one entry gives the authors as 'Greven & Küchenhoff (2008)', omitting Scheipl, the first author. reports.json is frozen evidence and is not edited; open_items_local_session.csv and review-catalogue.md name all three authors (the CSV transliterates Küchenhoff as 'Kuechenhoff').
