# Meteyard and Davies (2020)

**Reference as checked.** Meteyard, L., & Davies, R. A. I. (2020). Best practice guidance for linear mixed-effects models in psychological science. *Journal of Memory and Language, 112*, Article 104092. https://doi.org/10.1016/j.jml.2020.104092

**Match.** Crossref (queried 21 November 2026) and the publisher's page agree on authors, title, journal, volume 112, article number 104092 and DOI. Crossref lists only Elsevier's text-and-data-mining licence. Not retracted or corrected.

**Platform and pages read.** ScienceDirect, HTML full text through Oxford's subscription, read 21 November 2026: Abstract, 'Review of current practice in use and reporting of LMMs' (method, Table 6, and the opening of the results), Section 4.1 where it bears on estimation and p-values, and Table 7. Appendix 4's count tables and Appendix 5's example tables are in the supplementary material, which was not read. Places are given by section and table.

## Claims checked

03-execution-plan.md lists the paper for 'the checklist and survey figures'. The evidence (C/q5_standards_to_report_elements.csv, C/q2_model_class_matrix.csv, C/references_C.csv and reports.json, research:scope-reports and research:re-structure) takes the following from it.

1. Survey of 163 researchers and review of 400 papers. **Confirmed** (Abstract). The review covers papers in psychology, linguistics, cognitive science and neuroscience that use LMMs or GLMMs (Review, method; Table 6).
2. 'Gaussian LMMs dominate (Meteyard & Davies, 2020, reviewed 400 LMM papers)' (reports.json, research:scope-reports, recommendation 1). **Partly supported.** Of the 400 papers, 193 used LMMs, 88 GLMMs, 95 both and 5 additive models (start of the review's results, citing Table A4.1). LMMs alone are the largest group and appear in 288 papers, but GLMMs appear in 183, so 'dominate' overstates the contrast. The verifiers had flagged this claim as unsupported at abstract level; the full text gives the figures.
3. The checklist (C/q5_standards_to_report_elements.csv): report random-effect variances, how models were compared and selected, estimation (REML for the final model), the p-value method (Satterthwaite or Kenward–Roger), whether assumptions were checked, and the model equations; reporting was the most worrying problem.
   **Mostly supported.** Table 7 asks for the software and version; any a priori power analysis; data cleaning, transformations and whether the model meets its assumptions; random effects specified from the sampling units, data structure and expected interactions; the sample size in data points and in sampling units; a clear statement of how models were compared or selected, the comparison method (LRT, AIC or BIC) with a justification, and every model compared; the handling of convergence problems with the formula of each model and the rationale for the simplification; equations defining the reported model; a table of all fixed-effect estimates with standard errors or intervals, test statistics and p-values if used, all random-effect SDs or variances and correlations, and a measure of fit; and shared code and, where possible, data. The Abstract calls the variation in reporting the most worrying. Two elements of the CSV are not in Table 7: REML for the final model (the text, Section 4.1, recommends ML when comparing models that differ in fixed effects and does not prescribe REML for the reported model) and a named df method (the text describes Satterthwaite and Kenward–Roger as available options and the review coded which was used, but Table 7 asks only for the test statistics and p-values). 'LRT for nested, AIC otherwise' paraphrases the text's point that models compared by LRT must be nested.

## Fields that differ from the repository's records

None. Some files give the article number as '104092' and others as 'Article 104092'; the APA form is the latter.

## Questions for a person

None.
