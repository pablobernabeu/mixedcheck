# Matuschek et al. (2017)

**Reference as checked.** Matuschek, H., Kliegl, R., Vasishth, S., Baayen, H., & Bates, D. (2017). Balancing Type I error and power in linear mixed models. *Journal of Memory and Language, 94*, 305–315. https://doi.org/10.1016/j.jml.2017.01.001

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 94, pages 305–315 and DOI. Licence CC BY 4.0. Not retracted or corrected.

**Platform and pages read.** ScienceDirect, HTML full text (open access), read 21 November 2026: 'Specification of the simulation models', 'Two simulation scenarios', 'Model selection', Results ('Worst case scenario', with Table 1, and 'Small random slopes') and Discussion. The HTML has no page numbers, so places are given by section.

## Claims checked

1. 02-decisions.md, Q3: protected likelihood-ratio selection at α = .2, 'the level reportedly used by Matuschek et al., 2017, still to be confirmed from the full text'; 03-execution-plan.md: 'the design and the α of .2'.
   **Confirmed.** The simulations use α_LRT = 0.2 ('Model selection'). The authors explain the choice: α_LRT is a weight between fit and complexity, not a Type I error rate for model selection; .05 penalises complexity too strongly; and an LRT of two nested models at α ≈ .157 is equivalent to AIC, so .2 keeps the more complex model slightly more often than AIC would (Appendix A evaluates AIC). The phrase 'reportedly used' and the pending confirmation can be dropped.
2. The design. **Recorded.** 50 subjects and 20 items crossed, two conditions coded −0.5 and +0.5, every item seen by every subject in both conditions (2,000 observations); intercept 2,000 and effect 0 or 25; intercept SDs of 100 for subjects and items; slope SDs for subjects and items varied together from 0 to 120; intercept–slope correlations 0.6; residual SD 300 ('Specification of the simulation models'). A second run used 30 subjects and 10 items (600 observations) ('Small random slopes'). The five candidate models are the maximal model, the zero-correlation model, the model without the item slope, the model without the subject slope, and random intercepts only. The worst case scenario (no slope variance) used 10,000 iterations per model.
3. review-catalogue.md (L4 entries) and reports.json: maximal models can cost power, and selection that keeps only data-supported random effects can raise power 'without inflating Type I error' in their simulations.
   **Partly supported.** Power fell with the complexity of the model in the worst case scenario, where every model kept Type I error near or below .05 (Table 1: .030 for the maximal model, .051 for random intercepts only), and the maximal model was over-conservative for small slope SDs ('Small random slopes'). But the authors describe the Type I error of the LRT-selected model as larger than .05, though not substantially larger than the maximal model's own largest rate, and its power as substantially better for slope SDs up to about 40. 'Comparable Type I error' is their claim, not 'no inflation'. The Discussion concludes that a standard selection criterion is a defensible middle ground, and that more conservatism should come from a smaller α rather than from the maximal model.
4. B/sim/sim1_stopping_rules.R and B/tables/hpc_simulation_plan.tsv (H1) describe the LRT(.2) rule of this paper as backward selection with a data-driven order. **Not supported.** The paper's heuristic is backward selection along a fixed sequence, model 1 → 2 → 3 → 4 → 5 (correlations first, then the item slope, then the subject slope), stopping when a further reduction loses significant fit ('Model selection'). The order is set in advance, not chosen from the data.

## Fields that differ from the repository's records

None. The reference in 02-decisions.md matches the published record.
