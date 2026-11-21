# Harrison (2015)

**Reference as checked.** Harrison, X. A. (2015). A comparison of observation-level random effect and Beta-Binomial models for modelling overdispersion in Binomial data in ecology & evolution. *PeerJ, 3*, Article e1114. https://doi.org/10.7717/peerj.1114

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on author, title, journal, volume 3, article number e1114 and DOI. Published 21 July 2015, open access. Not retracted or corrected.

**Platform and pages read.** PeerJ, HTML full text (open access), read 21 November 2026: Abstract. Places are given by section.

## Claims checked

1. spec/registry/checks/identifiability.residual_confounding.yaml and structure.cluster_sizes.yaml: for binomial outcomes with trials, a random intercept with one row per level is an observation-level random effect, a term for overdispersion (Harrison, 2014, 2015).
   **Supported.** The paper studies observation-level random effects (OLRE) as a means of absorbing extra-binomial variation in binomial proportion data, beside Beta-Binomial models, and concludes that OLRE are useful for binomial data but do not perform well in all circumstances (Abstract).
2. review-catalogue.md (L3 entry on dispersion): OLRE give biased intercepts and slopes when overdispersion is Beta-Binomial generated, and both OLRE and Beta-Binomial models perform poorly with fewer than 5 levels of the random intercept. **Confirmed** (Abstract). OLRE failed with overdispersion generated from a Beta-Binomial mixture, biasing slopes and intercepts, but did well when the overdispersion came from noise added to the linear predictor; Beta-Binomial models did well throughout but tended to underestimate effects for non-Beta-Binomial data; both performed poorly with fewer than five levels of the random intercept, especially for variance components, independently of total sample size. The author recommends comparing an OLRE model with its Beta-Binomial counterpart as a check.

## Fields that differ from the repository's records

None. As for Harrison (2014), the APA form names the article number ('Article e1114').

## Questions for a person

None.
