# Scandola and Tidoni (2024)

**Reference as checked.** Scandola, M., & Tidoni, E. (2024). Reliability and feasibility of linear mixed models in fully crossed experimental designs. *Advances in Methods and Practices in Psychological Science, 7*(1), Article 25152459231214454. https://doi.org/10.1177/25152459231214454

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 7, issue 1 and DOI. The journal uses an article number (e-locator) in place of pages; the page range 1–21 that report B gives is the PDF's own pagination. First published online 9 February 2024, issue January–March 2024. Licence CC BY-NC 4.0. Not retracted or corrected.

**Platform and pages read.** Sage Journals, HTML full text (open access), read 21 November 2026: Abstract, introduction (aims), Simulation Studies 1 and 2 (design), 'A Step-by-Step Procedure for Efficient and Reliable Random-Effects Structures' (Preliminary considerations; Model reduction from full CRI models) and Discussion, 'Recommendations for model reduction'. Places are given by section.

## Claims checked

03-execution-plan.md lists the paper for 'the procedure and simulation grids'. The evidence (B/tables/literature_extraction.tsv, L08, and reports.json, research:re-structure) takes the following from it.

1. Excluding a within-subject factor or interaction from the random-effects structure inflates Type I error. **Supported.** Step 5 of the procedure notes that models with only main effects in the random part (Models s3 and i2) had higher Type I error for interactions than Models s1, i1 and i3 in Simulation Study 1, so random intercepts for main effects do not protect the tests of interactions. The Discussion ('Recommendations for model reduction') says that removing random effects can raise Type I error sharply.

2. Complex random intercepts (CRIs) have low Type I error and more power. **Partly supported.** The authors write that CRI models had low Type I error and greater power (start of Simulation Study 2), but their own Table 2, as summarised under 'Preliminary considerations', gives a mean Type I error of 6.26% for the full CRI model against 3.58% for the full random-slopes model, with mean power of 88% against 66%. 'Low Type I error' is therefore the authors' reading of a rate above the nominal 5%; the gain in power comes with a liberal Type I error.

3. Larger samples may favour random-slopes models. **Supported as a question, not a finding.** Simulation Study 2 (50 participants) found all three compared models comparable in Type I error and power, with more singular and non-convergent fits for the correlated maximal model.

4. CRIs need fewer resources and avoid many singular or non-convergent fits. **Supported** ('Preliminary considerations', with Table 3): full CRI models had fewer singularity or convergence problems, took less time to fit and to compute Kenward–Roger tables and used less memory.

5. The procedure. **Recorded.** The authors still recommend starting from a maximal random-slopes model (best balance of Type I and Type II error) and offer their pipeline only when that model or its p values cannot be computed. The pipeline: (1) a full CRI model covering every main effect and interaction that varies within subjects and stimuli; (2) if singular, remove the CRI with the lowest variance, one at a time, until the fit is not singular; (3) if it does not converge, change the optimiser, recheck singularity, and simplify as in step 2 if needed; (4) check the residuals and random-effect distributions; (5) F tests with Kenward–Roger degrees of freedom, and for any significant effect whose CRI was removed, refit with that CRI and report both analyses if they disagree; (6) marginal and conditional R² and post hoc tests.

6. Simulation grids. **Recorded.** Study 1: a 3 × 3 within-subject design with 15 participants and participant as the only grouping factor, eight scenarios crossing three binary factors (homogeneous or heterogeneous variance of the fixed-effect levels, homogeneous or heterogeneous random-effect SDs, random-effect correlation .8 or .2), data under the null and under an alternative with an interaction but no main effects, and models s1–s4 (random slopes), i1–i4 (CRIs) and o1–o3 (from buildmer). Study 2: 50 participants, homogeneous fixed-effect variance and weakly correlated random effects, with Satterthwaite degrees of freedom. Studies 3 to 6 cover post hoc tests, the pipeline on simulated data, the scripts of Matuschek et al. (2017) and a reanalysis of Singmann and Klauer (2011). The number of replicates per scenario is given in the Supplemental Material, which was not read.

## Fields that differ from the repository's records

- reports.json gives pages '1-21'; the published record has article number 25152459231214454 and no page range. The verifier's corrected entry in reports.json already uses the article number. reports.json is frozen evidence and is not edited.
