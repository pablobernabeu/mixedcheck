# Pustejovsky and Tipton (2018)

**Reference as checked.** Pustejovsky, J. E., & Tipton, E. (2018). Small-sample methods for cluster-robust variance estimation and hypothesis testing in fixed effects models. *Journal of Business & Economic Statistics, 36*(4), 672–683. https://doi.org/10.1080/07350015.2016.1247004

**Correction.** Pustejovsky, J. E., & Tipton, E. (2023). Corrigendum: Small sample methods for cluster-robust variance estimation and hypothesis testing in fixed effects models. *Journal of Business & Economic Statistics, 41*(2), 650–652. https://doi.org/10.1080/07350015.2023.2174123

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 36, issue 4, pages 672–683 and DOI; published online 12 June 2017. Crossref records the corrigendum as a correction of this article (published 22 February 2023). Not retracted.

**Platform and pages read.** Taylor & Francis Online, HTML full text through Oxford's subscription, read 21 November 2026: Abstract, Section 5.2 (the drinking-age example) and Section 6 (Conclusion); the corrigendum's abstract and Section 1. Places are given by section.

## Claims checked

1. 02-decisions.md, Q3: for nested designs in R, cluster-robust CR2 inference through clubSandwich is available as a terminal alternative (Pustejovsky & Tipton, 2018); registry assignment.unit_in_random_part, remedy cluster_robust: CR2 small-sample correction clustered on the randomisation unit, through clubSandwich; review-catalogue.md, L7-03: CR2 cluster-robust SEs with small-sample degrees of freedom.
   **Supported.** The paper generalises bias-reduced linearisation (CR2) to models with arbitrary sets of fixed effects, pairs it with a Satterthwaite approximation for t-tests and proposes an approximate Hotelling's T² test for multiple-parameter hypotheses; in its simulations the conventional cluster-robust Wald test could over-reject severely while the proposed tests kept Type I error near nominal; the methods are implemented in clubSandwich (Abstract). The Conclusion recommends CR2 with estimated degrees of freedom whenever cluster-robust variance estimation is used. The paper's framework is linear regression with fixed effects estimated by OLS or WLS; it also applies the tests to random-effects (feasible GLS) estimates in the drinking-age example (Section 5.2), which is the closest it comes to the mixed models of the suite.
2. The correction. **Relevant and not yet recorded in the repository.** The corrigendum states that Theorem 2, a computational short cut for CR2 in models with cluster-specific fixed effects, does not hold for models estimated by generalised least squares with inverse working-model weights, and restricts the revised theorem to OLS. The suite applies CR2 to mixed-model (GLS-type) fits through clubSandwich, so the record should cite the correction beside the article and rely on a clubSandwich version released after it; the H0 library has clubSandwich 0.7.0, from the snapshot of 20 November 2026. Whether clubSandwich's methods for lme and lmer fits ever used the short cut was not checked here.

## Fields that differ from the repository's records

- 02-decisions.md, docs/spec/registry.md and spec/registry/checks/assignment.unit_in_random_part.yaml cite the article without its 2023 corrigendum.
