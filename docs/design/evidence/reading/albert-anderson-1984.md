# Albert and Anderson (1984)

**Reference as checked.** Albert, A., & Anderson, J. A. (1984). On the existence of maximum likelihood estimates in logistic regression models. *Biometrika, 71*(1), 1–10. https://doi.org/10.1093/biomet/71.1.1

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 71, issue 1, pages 1–10 and DOI; published 1 April 1984. Not retracted or corrected.

**Platform and pages read.** Oxford Academic, through Oxford's subscription, read 21 November 2026: the abstract. The article is available only as a PDF, which the browser could not render as readable text, so the registry's `full_text_read: false` stays as it is.

## Claims checked

1. spec/registry/checks/outcome.separation.yaml (summary and sources) and review-catalogue.md (L3 entry on separation): the maximum-likelihood estimates of the fixed effects diverge, that is the MLE has an infinite component, if and only if the data are completely or quasi-completely separated (Albert & Anderson, 1984).
   **Supported in outline by the abstract; the theorem itself not read.** The abstract states that the paper proves existence theorems for multinomial logistic regression by classifying the possible patterns of data points into three mutually exclusive and exhaustive categories, complete separation, quasi-complete separation and overlap, and that the results suggest rules for identifying infinite estimates. The precise statement (estimates exist and are unique exactly under overlap) needs the full text.
2. The registry's derivation (outcome.separation.yaml) extends the result to models with random effects by its own argument, which this paper does not cover; that extension is correctly labelled a derivation, not a citation.
3. Not in the repository yet: the publisher's page lists Santner and Duffy's (1986) 'A note on A. Albert and J. A. Anderson's conditions for the existence of maximum likelihood estimates in logistic regression models' among related articles. Whether it qualifies the conditions on which the linear-programming check relies is a question for the full texts.

## Fields that differ from the repository's records

None.

## Questions for a person

- The full text (PDF), to confirm the existence theorem as the registry states it.
- Whether Santner and Duffy (1986, Biometrika) changes the conditions, and whether the registry should cite it beside this paper and Konis (2007).
