# Goldstein et al. (1993)

**Reference as checked.** Goldstein, H., Rasbash, J., Yang, M., Woodhouse, G., Pan, H., Nuttall, D., & Thomas, S. (1993). A multilevel analysis of school examination results. *Oxford Review of Education, 19*(4), 425–433. https://doi.org/10.1080/0305498930190401

**Match.** Crossref (queried 21 November 2026; found by bibliographic search, since the repository records no DOI) and the article's first page agree on the seven authors, title, journal, volume 19, issue 4, pages 425–433 and year. Not retracted or corrected.

**Platform and pages read.** Taylor & Francis Online, PDF reader through Oxford's subscription, read 21 November 2026: pp. 425–427 (abstract, introduction, data, the model for total examination score and Table II) and the remaining pages for the counts of students and schools.

## Claims checked

03-execution-plan.md lists the paper 'for the Exam data'; E/tables/q8_datasets.csv gives mlmRev::Exam as '4,059 pupils, 65 inner-London schools' with the source 'Goldstein et al. 1993 per Rd'; reports.json (research:declarations-data and its verifier) asks the paper to explain the four duplicated (school, student) pairs.

1. The paper is the source of the Exam data. **Partly supported.** The study analyses GCSE examination results of students in inner London schools with the London Reading Test at age 11, verbal-reasoning group, gender, school gender and school denomination as explanatory variables, and normal-scores the outcomes (pp. 425–427). These are the variables of mlmRev::Exam. But the analysis sample is 5,748 students in 66 schools, selected from 8,857 students in 74 schools by requiring both intake measures (pp. 425–426), not the 4,059 students in 65 schools of mlmRev::Exam. The paper does not describe the smaller dataset, which is a teaching subset distributed with MLwiN; the paper is its origin, not its documentation.
2. The paper explains the duplicated (school, student) pairs. **Not supported.** The paper reports no student identifiers and says nothing about how students were numbered, so it cannot explain the four duplicated pairs or the student labels shared across schools. 02-decisions.md (Q4) uses the Exam data for that point, which rests on the data and mlmRev's documentation ('Student id (within school)'), not on this paper.
3. The data licence. **Not addressed** by the paper. The licence of mlmRev::Exam remains unstated (E/tables/q8_datasets.csv).
4. Noted for any later use: excluded students had lower examination scores (mean total 20.0 against 23.7 in the analysed sample), which the authors flag as a selection problem (p. 426); confidence intervals for school effects are wide, so few schools can be separated and no fine ranking is legitimate (abstract, p. 425).

## Fields that differ from the repository's records

- The repository gives no DOI for the paper; the DOI is 10.1080/0305498930190401. The author list in reports.json ('Goldstein, Rasbash et al.') is abbreviated; the paper has seven authors.

## Questions for a person

- Where the 4,059-student, 65-school version of the Exam data was derived from the 5,748-student analysis sample, and under what licence it is distributed (the MLwiN data documentation or the Centre for Multilevel Modelling).
