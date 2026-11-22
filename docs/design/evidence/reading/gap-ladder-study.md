# Literature search for the ladder study

**Question.** Whether any study has evaluated, by simulation, a rule that starts from the maximal random-effects structure and simplifies it in a fixed order only when the fit fails to converge or is singular, keeping the random effects that protect the tested fixed effects, and judged the rule by the Type I error and power of those tests. The ladder and stopping-rule study (02-decisions.md, Q3 and Q9) proposes such an evaluation across crossed and nested designs, against selection by likelihood-ratio tests and AIC and against the maximal model, counting failed fits as outcomes.

**Inclusion.** A study counts as a close precedent if it (a) simulates data, (b) compares ways of specifying, selecting or simplifying the random-effects structure of linear or generalised linear mixed models, including ways of responding to non-convergence or singular fits, and (c) judges them by inference on fixed effects (Type I error, power, coverage or standard-error bias). Tutorials, Bayesian model comparison, selection of fixed effects, penalised selection in high dimensions and other model families are recorded as related work only.

## Search

Run on 22 November 2026; scripts and record files kept outside the repository.

- **OpenAlex, topic queries.** Eight Boolean queries on titles and abstracts, 2008 to 2026, combining terms for the random-effects structure, random slopes, maximal models, non-convergence and singular fits, model selection (LRT, AIC, BIC), zero-correlation and parsimonious models, cross-level interactions and crossed subjects and items with terms for simulation: 303 records.
- **OpenAlex, forward citations** of nine seed works (Barr et al., 2013; Matuschek et al., 2017; Seedorff et al., 2019; Luo & Li, 2023; Scandola & Tidoni, 2024; Schielzeth & Forstmeier, 2009; Heisig & Schaeffer, 2019; Bates et al., 2015; Eager & Roy, 2017), filtered on simulation and topic terms in title and abstract, then on topic terms in titles alone, and every citing work of the four seeds with fewer than 150 citations.
- **Semantic Scholar, forward citations** of the same seeds, filtered locally on simulation and topic terms in title and abstract. The API stops at 9,000 citing records, which truncated those of Barr et al. (2013).
- **Known-item checks** for two preprints found in an earlier scan (Kim & Lee, 2025; Le, 2026) and for the R package buildmer.

After removing duplicates, 567 records remained, 513 with an abstract. Screening titles left 47, and screening their abstracts left the studies below. Full texts were read for the closest ones; the others are described from their abstracts, as marked.

**Limits.** OpenAlex and Semantic Scholar lack abstracts for some publishers, so filters on abstracts miss some records; the title filters and the complete citer lists of the smaller seeds partly offset this. The forward citations of Barr et al. (2013) were read only to the API's limit. One OSF preprint (Le, 2026) could not be retrieved beyond its title. Grey literature beyond PsyArXiv, OSF and arXiv, and work in languages other than English, were not searched.

## Closest precedents

| Study | Design | What is compared | Failed fits | Judged by | Read |
|---|---|---|---|---|---|
| Barr et al. (2013) | Crossed, 24 subjects, 12 or 24 items, one binary predictor | Maximal, no correlations, random intercepts, LRT-based forward and backward selection | More than 99% converged (Park et al., 2020, p. 103) | Type I error, power | Parts (barr-et-al-2013.md) |
| Matuschek et al. (2017) | Crossed, 50 × 20 and 30 × 10 | Maximal, four simpler structures, backward LRT selection at α = .2 along a fixed order, AIC | Not the object of study | Type I error, power | Parts (matuschek-2017.md) |
| Seedorff et al. (2019), preprint | Crossed, with a between-subject factor; linear and logistic | AIC and other criteria over the model space, incremental searches; fallbacks after non-convergence | Dropping covariances kept Type I error, dropping a slope raised it (pp. 37–38) | Type I error, power | In full (seedorff-2019.md) |
| Park et al. (2020) | Crossed, 24 × 24, one to three binary predictors | Fixed candidate structures, AIC and BIC selection | Non-convergence rates by fitted and generating model | Convergence, selection accuracy, estimates; not Type I error or power (p. 106) | In full |
| Martínez-Huertas et al. (2021) | Crossed, 30 to 500 subjects, 12 to 96 items, within and between effects | LRT, AIC and BIC selection, model averaging | Not reported | True-model selection, standard-error bias | Method and results |
| Luo and Li (2023) | Nested, two levels, 10 to 100 clusters | Minimal, maximal, forward and backward searches at α = .20, all possible structures | Not the object of study | Type I error, power | Parts (luo-li-2023.md) |
| Liu et al. (2024) | Crossed, within-subject factor, items nested in conditions | Three fixed structures, REML against Bayesian estimation, AIC and DIC | Redundant random effects caused convergence problems (abstract) | Type I error, coverage, R² | Method |
| Scandola and Tidoni (2024) | Fully crossed repeated measures | Random slopes against complex random intercepts (CRIs); a pipeline that removes the lowest-variance CRI while the fit is singular and changes the optimiser on non-convergence (Steps 2 and 3), applied to each dataset | The reduced models had no singular fits and almost no convergence failures; the full models were singular in up to 80% of fits (Tables 6 and 7) | Type I error, power | Pipeline and Simulation Studies 4 and 5 |

Scandola and Tidoni's evaluation of their pipeline is the closest precedent. In a 3 × 3 repeated-measures design with 30 participants, the reduced CRI models kept Type I error at 5.10%, 5.78% and 3.65% against about 22% for random intercepts only (Simulation Study 4, Table 6), and in the crossed design of Matuschek et al. (2017) at 2.55% (Simulation Study 5, Table 7). The pipeline works on CRI structures, and its rule as stated removes the CRI with the lowest variance without exempting the CRI of a tested effect. It was evaluated in two crossed designs.

## Related work

- **Why convergence is a poor guide.** Eager and Roy (2017) found frequent non-convergence in lme4 when every generating variance was non-zero, so dropping terms because a fit failed can remove real random effects (eager-roy-2017.md). Bates et al. (2015) argue the opposite, that non-convergence usually signals an over-parameterised model, and propose diagnostics to guide simplification (abstract).
- **Pre-specification.** Häckl et al. (2023) showed that ambiguous specification of mixed models for repeated measures inflates Type I error, up to 7.6%. Their models always converged, so no fallback strategy was needed or evaluated, and they note that simplifying the model, as a fallback would, enlarges the set of compatible models, so that their figures may understate the inflation (Discussion). Gurka et al. (2011) recommend backward selection of the covariance model from an unstructured pattern for longitudinal data (abstract).
- **Alternatives to simplification.** McNeish and Bauer (2020) propose factor-analytic covariance structures in place of removing random effects (abstract). Huang and Zhang (2025) and Ouyang et al. (2024) study cluster-robust standard errors in place of random slopes (abstracts).
- **Software.** buildmer (Voeten, 2026, version 2.13) adds terms in order of their contribution until the model no longer converges, counting singular fits as failures by default, keeps the terms listed in its `include` option 'at all times' and exempts them from elimination, and then optionally eliminates terms stepwise (reference manual, read 22 November 2026). Its documentation cites no evaluation of the procedure's Type I error or power.
- **Protected terms.** Schielzeth and Forstmeier (2009), Barr (2013) and Heisig and Schaeffer (2019) show the cost of omitting slopes of tested within-unit and cross-level effects.
- **Bayesian approaches**, outside the question: Oberauer (2022), Veríssimo (2023), Rodriguez et al. (2024), Kim and Lee (2025, likelihood-ratio null distributions) and Le (2026, Bayes factors for response times).

## Verdict

No study found evaluates a pre-specified, outcome-blind reduction order with protected terms for the tested effects, triggered only by failed or singular fits, against selection by fit criteria and the maximal model, across crossed and nested designs, with failed fits counted as outcomes. The gap is narrower than a first reading suggests. Scandola and Tidoni (2024) evaluated a singularity-driven pipeline in two crossed designs, Seedorff et al. (2019) compared fallbacks after non-convergence in one crossed design, Luo and Li (2023) covered nested designs with fit-based searches only, and buildmer implements a convergence-driven search without a published evaluation.

The ladder study can therefore claim to be the first systematic comparison of these rules, not the first study of convergence-driven reduction. It would make that claim most firmly by including the closest existing procedures as comparators: Scandola and Tidoni's CRI pipeline for crossed designs, and a maximal-feasible search in the manner of buildmer with and without its `include` list.

**Venue precedent.** AMPPS has published a simulation study as a Registered Report: Fossum, J., Montoya, A., & Anderson, S. F. (2026). How does model (mis)specification affect statistical power, Type I error rate, and parameter bias in moderated mediation? A registered report. *Advances in Methods and Practices in Psychological Science, 9*(3), Article 25152459261432211. https://doi.org/10.1177/25152459261432211 (Crossref and abstract, read 22 November 2026).

## References checked

Each reference below was checked against Crossref on 22 November 2026 (authors, title, journal, volume, issue, pages and date; none is retracted or corrected), apart from the preprints, the arXiv paper and the software record, which were checked on their own pages. The sources that have their own note in this folder (Barr, 2013; Barr et al., 2013; Eager & Roy, 2017; Luo & Li, 2023; Matuschek et al., 2017; Oberauer, 2022; Scandola & Tidoni, 2024; Seedorff et al., 2019; Veríssimo, 2023) are cited there.

Bates, D., Kliegl, R., Vasishth, S., & Baayen, H. (2015). *Parsimonious mixed models* [Preprint]. arXiv. https://doi.org/10.48550/arXiv.1506.04967

Heisig, J. P., & Schaeffer, M. (2019). Why you should always include a random slope for the lower-level variable involved in a cross-level interaction. *European Sociological Review, 35*(2), 258–279. https://doi.org/10.1093/esr/jcy053

Huang, F. L., & Zhang, B. (2025). Accounting for random slopes using cluster-robust standard errors in multilevel models. *The Journal of Experimental Education, 94*(4), 1131–1150. https://doi.org/10.1080/00220973.2025.2565180

Fossum, J., Montoya, A., & Anderson, S. F. (2026). See Venue precedent.

Gurka, M. J., Edwards, L. J., & Muller, K. E. (2011). Avoiding bias in mixed model inference for fixed effects. *Statistics in Medicine, 30*(22), 2696–2707. https://doi.org/10.1002/sim.4293

Häckl, S., Koch, A., & Lasch, F. (2023). Type-I-error rate inflation in mixed models for repeated measures caused by ambiguous or incomplete model specifications. *Pharmaceutical Statistics, 22*(6), 1046–1061. https://doi.org/10.1002/pst.2328

Kim, Y., & Lee, W. (2025). *Shape of the null distribution in the likelihood ratio test for selecting random effects structures in experimental data analysis* [Project materials]. OSF. https://osf.io/4t5sp

Le, Y. (2026). *Exploring the random effects structure for response time data in psychological experiments: A comprehensive comparison based on Bayes factors* [Preprint]. OSF. https://osf.io/fzgx8

Liu, Y., Hau, K.-T., & Liu, H. (2024). Linear mixed-effects models for dependent data: Power and accuracy in parameter estimation. *Multivariate Behavioral Research, 59*(5), 978–994. https://doi.org/10.1080/00273171.2024.2350236

Martínez-Huertas, J. Á., Olmos, R., & Ferrer, E. (2021). Model selection and model averaging for mixed-effects models with crossed random effects for subjects and items. *Multivariate Behavioral Research, 57*(4), 603–619. https://doi.org/10.1080/00273171.2021.1889946

McNeish, D., & Bauer, D. J. (2020). Reducing incidence of nonpositive definite covariance matrices in mixed effect models. *Multivariate Behavioral Research, 57*(2–3), 318–340. https://doi.org/10.1080/00273171.2020.1830019

Ouyang, Y., Taljaard, M., Forbes, A. B., & Li, F. (2024). Maintaining the validity of inference from linear mixed models in stepped-wedge cluster randomized trials under misspecified random-effects structures. *Statistical Methods in Medical Research, 33*(9), 1497–1516. https://doi.org/10.1177/09622802241248382

Park, J., Cardwell, R., & Yu, H.-T. (2020). Specifying the random effect structure in linear mixed effect models for analyzing psycholinguistic data. *Methodology, 16*(2), 92–111. https://doi.org/10.5964/meth.2809

Rodriguez, J. E., Williams, D. R., & Rast, P. (2024). Who is and is not 'average'? Random effects selection with spike-and-slab priors. *Psychological Methods, 29*(1), 117–136. https://doi.org/10.1037/met0000535

Schielzeth, H., & Forstmeier, W. (2009). Conclusions beyond support: Overconfident estimates in mixed models. *Behavioral Ecology, 20*(2), 416–420. https://doi.org/10.1093/beheco/arn145

Voeten, C. C. (2026). *buildmer: Stepwise elimination and term reordering for mixed-effects regression* (Version 2.13) [Computer software]. https://doi.org/10.32614/CRAN.package.buildmer
