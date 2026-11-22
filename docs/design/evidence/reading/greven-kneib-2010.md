# Greven and Kneib (2010)

**Reference as checked.** Greven, S., & Kneib, T. (2010). On the behaviour of marginal and conditional AIC in linear mixed models. *Biometrika, 97*(4), 773–789. https://doi.org/10.1093/biomet/asq042

**Correction.** Greven, S., & Kneib, T. (2019). Correction to 'On the behaviour of marginal and conditional AIC in linear mixed models'. *Biometrika*. https://doi.org/10.1093/biomet/asz051

**Match.** Crossref (queried 21 November 2026), the publisher's page and JSTOR (stable 29777136) agree on authors, title, journal, volume 97, issue 4, pages 773–789 and DOI; published 27 July 2010. The publisher's page links a correction published in 2019 that Crossref does not record against the article. Not retracted.

**Platform and pages read.** JSTOR, page images with their text layer, through Oxford's subscription, read 21 November 2026: all 17 pages, with the abstract (p. 773) and Section 2 on the marginal AIC, Theorem 1 and the comparison with a likelihood ratio test (p. 778), read closely. Oxford Academic offers the article only as a PDF; its abstract and the correction notice were read there.

## Claims checked

1. review-catalogue.md (L4 entry on information criteria) and reports.json (research:re-structure, recommendation 3): the marginal AIC is not an asymptotically unbiased estimator of the Akaike information and favours smaller models without random effects; the conditional AIC that ignores the estimation uncertainty in the random-effects covariance matrix is biased towards keeping any random effect not predicted to be exactly zero; the authors derive a corrected conditional AIC. **Confirmed** (abstract, p. 773). The corrected conditional AIC has an analytic form and an R implementation.
2. reports.json (research:re-structure, open item): the size of the marginal AIC's bias. **Answered in kind.** For a model with one variance component, the bias of the marginal AIC depends on the true variance and does not vanish asymptotically when that variance is zero (Theorem 1, p. 778). Comparing the marginal AIC of the model without and with the random effect is the same as a likelihood ratio test with critical value 2; with a χ²₁ statistic that would be a level of about .157, but because the statistic has a point mass at zero when a variance is tested, the level can be far below .05, which is why the marginal AIC tends to drop random effects (p. 778). The simulations (Section 5) illustrate the size in particular settings.
3. Bearing on 02-decisions.md (Q3), not cited there: the equivalence that Matuschek et al. (2017) use, an LRT at α ≈ .157 matching AIC, assumes the regular χ²₁ case. When the reduction tests a variance on its boundary, the naive level of an LRT at α = .2 is not the actual level either. The registered alternative's α = .2 is a weight between fit and complexity, as Matuschek et al. say, not a Type I error rate.
4. The correction (2019) replaces Tables 2 and 3 of the Supplementary Material, which contained errors; the article is unchanged (correction notice).

## Fields that differ from the repository's records

- The repository cites the article without its 2019 correction to the Supplementary Material.
