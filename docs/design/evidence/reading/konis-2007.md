# Konis (2007)

**Reference as checked.** Konis, K. (2007). *Linear programming algorithms for detecting separated data in binary logistic regression models* [Doctoral thesis, University of Oxford]. Oxford University Research Archive. https://ora.ox.ac.uk/objects/uuid:8f9ee0d0-d78e-4101-9ab4-f9cbceed2a2a

**Match.** The ORA record and the thesis's title page (read 21 November 2026) agree on author, title, degree, institution and year. Theses have no Crossref record.

**Platform and pages read.** ORA: the record and abstract in the browser; the thesis PDF (Konis2007.pdf, 120 pages), downloaded with the maintainer's permission to a temporary folder outside the repository and read as extracted text, 21 November 2026: abstract (p. 3, the PDF's page numbering), the introduction (pp. 7–10), the existence results it restates (p. 23), the review of earlier methods (pp. 41–44), Section 4.5 on numerical considerations (pp. 93–95) and the contents. The PDF was deleted afterwards.

## Claims checked

1. spec/registry/checks/outcome.separation.yaml: the check tests by linear programming whether the fixed-effects columns separate the events from the non-events completely or quasi-completely, citing Konis (2007).
   **Confirmed.** The thesis proposes a test based on a linear programme with a non-negative objective whose optimum is positive when separation is present among the sample points and zero otherwise (pp. 3 and 8); of the ways to solve it, determining the feasibility of the dual programme gave a numerically reliable test, and a simulation showed it takes about as long as fitting the model by iteratively reweighted least squares, so it can be run routinely (p. 3). The method is implemented in the R package safeBinaryRegression (pp. 3 and 8). The thesis also explains why quasi-complete separation is the harder case for ordinary fitting, whose convergence criterion tends to be met before any sign of separation (p. 3).
2. The registry's separation_tolerance (1e-6 on columns scaled to a largest absolute value of 1) is labelled a convention of the project. The thesis does not fix such a value for its test: Section 4.5 discusses representation and rounding error and the zero tolerances of the solver used (pp. 93–95), and its account of Santner and Duffy's mixed-integer programme uses a tolerance M of about 1e-9 (p. 44). The registry's own value therefore remains its convention.
3. Related, for the note on Albert and Anderson (1984): the thesis restates the existence result (p. 23) and reviews Albert and Anderson's suggestion to rerun the fit with standardised columns and watch the dispersion matrix (p. 41), and Santner and Duffy's programme (p. 44).

## Fields that differ from the repository's records

None.

## Questions for a person

None. With this reading, the registry may set `full_text_read: true` for this source once the maintainer confirms the note.
