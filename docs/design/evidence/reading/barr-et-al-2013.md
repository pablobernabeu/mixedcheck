# Barr et al. (2013)

**Reference as checked.** Barr, D. J., Levy, R., Scheepers, C., & Tily, H. J. (2013). Random effects structure for confirmatory hypothesis testing: Keep it maximal. *Journal of Memory and Language, 68*(3), 255–278. https://doi.org/10.1016/j.jml.2012.11.001

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 68, issue 3, pages 255–278 and DOI. Crossref lists no open licence; an author manuscript is in PubMed Central (PMC3881361). Not retracted or corrected.

**Platform and pages read.** ScienceDirect, HTML full text through Oxford's subscription, read 21 November 2026: Abstract, 'Generating simulated data' with Table 2, Tables 4 to 6, and General discussion, 'Identifying the maximal random effects structure'. The HTML has no page numbers, so places are given by section and table; Barr (2013) quotes the interaction guideline from p. 275.

## Claims checked

1. 02-decisions.md, Q3 (protected set): 'the by-unit slopes of focal within-unit effects (Barr et al., 2013)'.
   **Supported.** If a factor is within-unit and there are several observations per level per unit, the model needs a by-unit random slope for it; a factor that varies between units needs only a random intercept; with a single observation per level and unit the slope is not identifiable and the intercept suffices; with unbalanced data one should at least try to estimate the slope ('Identifying the maximal random effects structure'). The protected set follows this, provided the condition on replication is carried with it (see the note on Barr, 2013).
2. 03-execution-plan.md: 'the Type I error figures for the maximal model'; reports.json (research:re-structure, open item): exact Type I error of the intercepts-only, no-correlation and selection models, and the conditions.
   **Recorded.** With 24 subjects and 12 or 24 items, Type I error at α = .05 was:

   | Model and test | Within items, 12 / 24 items | Between items, 12 / 24 items |
   |---|---|---|
   | Maximal LMEM, likelihood-ratio χ² | .059 / .056 | .070 / .058 |
   | No random correlations, likelihood-ratio χ² | .059 / .056 | .069 / .057 |
   | Maximal LMEM, t as z | .072 / .063 | .086 / .065 |
   | Random intercepts only, likelihood-ratio χ² | .440 / .498 | .102 / .111 |
   | min-F′ | .027 / .031 | .044 / .045 |

   (Tables 6 and 5.) The maximal model is close to nominal with the likelihood-ratio test and somewhat liberal when t is treated as z, whereas random intercepts only is badly anticonservative, above all for within-item designs.
3. Conditions. **Recorded.** One two-level treatment factor, always within subjects and either within or between items (two counterbalanced lists for within-item designs); 24 subjects and 12 or 24 items; one observation per subject and item; parameters drawn for each dataset from uniform ranges (intercept U(−3, 3); variances of subject and item intercepts and slopes and the residual variance U(0, 3); correlations U(−.8, .8); up to 5% missing); effect 0 or .8; 100,000 datasets for each of the eight combinations, with fewer runs (10,000) for the MCMC analyses ('Generating simulated data'; Table 2).
4. Data-driven selection (B/tables/literature_extraction.tsv, L01). **Confirmed** at abstract level: LMEMs with data-driven random-effects structures performed reasonably on moderately sized samples with conservative criteria, but with little or no power advantage over maximal models (Abstract); the selection algorithms compared are listed in Table 4.

5. docs/spec/documents.md as M3 leaves it (pull request #3): the ceiling has, for each grouping factor, one correlated random term with the intercept and every fixed term whose variables all vary within the factor (Barr et al., 2013).
   **Supported, with the same condition left out as in item 1.** The paper adds the slope for a within-unit factor when there are several observations per level and unit, and says a random intercept suffices when each unit has a single observation per level ('Identifying the maximal random effects structure'). A ceiling built from 'varies within the factor' alone includes slopes that the paper would leave out in designs without replication, where they are not identifiable.

## Fields that differ from the repository's records

None. The reference in 02-decisions.md and the one that M3 adds to docs/spec/documents.md (pull request #3) both match the published record.
