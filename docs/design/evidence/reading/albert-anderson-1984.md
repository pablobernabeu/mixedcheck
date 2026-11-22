# Albert and Anderson (1984)

**Reference as checked.** Albert, A., & Anderson, J. A. (1984). On the existence of maximum likelihood estimates in logistic regression models. *Biometrika, 71*(1), 1–10. https://doi.org/10.1093/biomet/71.1.1

**Match.** Crossref (queried 21 November 2026), the publisher's page and JSTOR (stable 2336390) agree on authors, title, journal, volume 71, issue 1, pages 1–10 and DOI; published 1 April 1984. Not retracted or corrected.

**Platform and pages read.** JSTOR, page images with their text layer, through Oxford's subscription, read 21 November 2026: all ten pages, with the introduction (p. 1), Theorems 1 to 3 (pp. 3, 5 and 7) and the section on categorising data sets (p. 7) read closely. Oxford Academic offers the article only as a PDF. Also read, for its correction of the separated cases: Santner, T. J., & Duffy, D. E. (1986). A note on A. Albert and J. A. Anderson's conditions for the existence of maximum likelihood estimates in logistic regression models. *Biometrika, 73*(3), 755–758 (JSTOR stable 2336546), its summary and introduction.

## Claims checked

1. spec/registry/checks/outcome.separation.yaml (summary and sources) and review-catalogue.md (L3 entry on separation): the maximum-likelihood estimates of the fixed effects diverge, the MLE having an infinite component, if and only if the data are completely or quasi-completely separated.
   **Confirmed.** The paper classifies data configurations as completely separated, quasi-completely separated or overlapping, the first two giving infinite estimates and the third finite and unique ones (p. 1). Theorem 1 (p. 3): under complete separation the MLE does not exist. Theorem 2 (p. 5): under quasi-complete separation the MLE does not exist. Theorem 3 (p. 7): under overlap the MLE exists and is unique. The results are proved for multinomial logistic regression, which includes the binary case.
2. The registry's test by linear programming. **Supported, with a second source.** The paper notes that the categorisation can be approached algebraically with linear programming, finding whether the feasible sets of a linear programme are empty (p. 7), but gives no algorithm. Santner and Duffy (1986) give a linear programme that decides whether data are of the overlap, complete-separation or quasi-separation type, and also modify the statements and proofs of Albert and Anderson's results for the two separated cases (their summary). The registry's LP check therefore rests on Santner and Duffy (1986) and Konis (2007) as much as on this paper.
3. The registry's derivation that extends the result to models with random effects is the project's own argument, which this paper does not cover; the registry labels it as a derivation.

## Fields that differ from the repository's records

None.
