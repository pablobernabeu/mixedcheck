# Crainiceanu and Ruppert (2004)

**Reference as checked.** Crainiceanu, C. M., & Ruppert, D. (2004). Likelihood ratio tests in linear mixed models with one variance component. *Journal of the Royal Statistical Society: Series B (Statistical Methodology), 66*(1), 165–185. https://doi.org/10.1111/j.1467-9868.2004.00438.x

**Match.** Crossref (queried 21 November 2026; found by bibliographic search, since the repository gives no DOI) and the publisher's page agree on authors, title, journal, volume 66, issue 1, pages 165–185 and DOI; first published online 22 December 2003, in the February 2004 issue. The journal is now published by Oxford University Press as the Journal of the Royal Statistical Society Series B: Statistical Methodology. Not retracted or corrected. The metadata that open_items_local_session.csv marks 'from memory, unverified' is correct.

**Platform and pages read.** Oxford Academic, HTML full text through Oxford's subscription, read 21 November 2026: Summary, Section 1 (Introduction, where it contrasts its results with earlier theory) and the section list. Places are given by section.

## Claims checked

1. open_items_local_session.csv: 'Exact (R)LRT null distribution; RLRsim comparator in V4'. **Supported.** For a linear mixed model with one variance component, the paper derives the finite-sample and asymptotic null distributions of the likelihood ratio and restricted likelihood ratio tests, and uses their spectral representations for efficient simulation of those distributions (Summary). This simulation is what RLRsim implements (see Scheipl et al., 2008).
2. review-catalogue.md (L4 entry on variance-component tests): the 0.5χ²ₖ + 0.5χ²ₖ₊₁ result of Stram and Lee assumes many independent, identically distributed cluster subvectors (Crainiceanu & Ruppert 2004, who derive finite-sample null distributions). **Confirmed.** The Summary states that the theory of Self and Liang applies only to linear mixed models whose data vector can be partitioned into a large number of independent and identically distributed subvectors, that the usual χ² mixture approximations have been poor in simulation studies, and that the paper's asymptotic calculations explain why; the Introduction says the same of Self and Liang (1987), Liang and Self (1996) and Stram and Lee (1994). The paper illustrates its results with the balanced one-way ANOVA and penalised-spline models (Sections 4 and 5).

## Fields that differ from the repository's records

- The repository gives no DOI; the DOI is 10.1111/j.1467-9868.2004.00438.x.
