# Konis (2007)

**Reference as checked.** Konis, K. (2007). *Linear programming algorithms for detecting separated data in binary logistic regression models* [Doctoral thesis, University of Oxford]. Oxford University Research Archive. https://ora.ox.ac.uk/objects/uuid:8f9ee0d0-d78e-4101-9ab4-f9cbceed2a2a

**Match.** The ORA record (read 21 November 2026) agrees on author, title, degree, institution and address. Theses have no Crossref record. ORA holds the thesis as a PDF file (Konis2007.pdf) on the record's page.

**Platform and pages read.** ORA, 21 November 2026: the record and its abstract. The thesis itself is a PDF, which the browser could not render as readable text, so the registry's `full_text_read: false` stays as it is.

## Claims checked

1. spec/registry/checks/outcome.separation.yaml: the check tests by linear programming whether the fixed-effects columns separate the events from the non-events completely or quasi-completely, citing Konis (2007).
   **Supported by the abstract.** The thesis proposes an algorithm for detecting separation in binary logistic regression based on a linear programme with a non-negative objective that has a positive optimum when separation is present; it compares ways of solving the programme and finds that testing the feasibility of the dual gives a numerically reliable test; and a simulation shows the test takes about as long as fitting the model by iteratively reweighted least squares, so it can be run routinely (abstract). The abstract also explains why quasi-complete separation is the harder case: iterative fitting tends to meet its convergence criterion before any sign of separation appears. The registry's tolerance (separation_tolerance, 1e-6 on scaled columns) is labelled a convention of the project, not a value from the thesis.

## Fields that differ from the repository's records

None.

## Questions for a person

- The thesis full text (Konis2007.pdf on ORA), to confirm the details of the dual test before the registry marks the source as read in full.
