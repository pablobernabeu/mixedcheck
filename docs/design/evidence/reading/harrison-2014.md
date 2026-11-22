# Harrison (2014)

**Reference as checked.** Harrison, X. A. (2014). Using observation-level random effects to model overdispersion in count data in ecology and evolution. *PeerJ, 2*, Article e616. https://doi.org/10.7717/peerj.616

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on author, title, journal, volume 2, article number e616 and DOI. Published 9 October 2014, open access. Not retracted or corrected.

**Platform and pages read.** PeerJ, HTML full text (open access), read 21 November 2026: Abstract and the opening of the Introduction and Methods (the three sources of overdispersion simulated). Places are given by section.

## Claims checked

1. spec/registry/checks/identifiability.residual_confounding.yaml and structure.cluster_sizes.yaml: for counts (and binomial outcomes with trials) a random intercept with one row per level is an observation-level random effect, a standard term for overdispersion (Harrison, 2014, 2015).
   **Supported for counts.** The paper describes observation-level random effects (OLRE), in which each data point receives its own level of a random effect that models extra-Poisson variation, as commonly used for overdispersion in count data, and shows by simulation that they give more accurate estimates than ignoring overdispersion when it comes from random extra-Poisson noise or aggregation (Abstract). The binomial case is Harrison (2015). The paper does not discuss binary outcomes, which the registry attributes, correctly, to a separate derivation.
2. review-catalogue.md (L3 entry on dispersion): OLRE do not reduce bias in zero-inflated counts; ignoring overdispersion inflates r². **Confirmed** (Abstract): OLRE failed to reduce bias in zero-inflated data and sometimes increased it at high overdispersion, bias grew with the magnitude of overdispersion, and failing to model overdispersion inflated measures of explained variance (r²). The simulations cover three sources of overdispersion: extra-Poisson noise, zero inflation and aggregation (Introduction and Methods).

## Fields that differ from the repository's records

None. The registry gives the citation as 'PeerJ, 2, e616'; the APA form names the article number ('Article e616').
