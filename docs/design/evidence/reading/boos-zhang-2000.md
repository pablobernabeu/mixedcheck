# Boos and Zhang (2000)

**Reference as checked.** Boos, D. D., & Zhang, J. (2000). Monte Carlo evaluation of resampling-based hypothesis tests. *Journal of the American Statistical Association, 95*(450), 486–492. https://doi.org/10.1080/01621459.2000.10474226

**Match.** Crossref (queried 21 November 2026) and the article agree on authors, title, journal, volume 95, issue 450, pages 486–492 and DOI. Not retracted or corrected.

**Platform and pages read.** Taylor & Francis Online, PDF reader through Oxford's subscription, read 21 November 2026: all seven pages, with the abstract and introduction (p. 486) and the Summary (p. 492) read closely.

## Claims checked

1. open_items_local_session.csv: 'Extrapolation that shrinks the bootstrap inner loop; could cut V4/V10 cost several-fold'.
   **Supported.** When the power of a resampling-based test is estimated by Monte Carlo, the inner resampling loop can be made small as long as the resulting bias in the power estimate is corrected; a simple linear extrapolation in 1/I (I being the number of inner resamples), similar to SIMEX, does this well (abstract, p. 486). The Summary reports at least four-fold reductions in computing time (p. 492). Power at a null value is the size, so the method applies to the Type I error rates of V4 and V10 as well as to their power.
2. Settings the paper recommends, for the V4 and V10 protocols. At α = .05, I = 59 or 99; linear extrapolation when the number of outer datasets is below 4,000, quadratic when it is 4,000 or more and I is at least 99; choose the number of outer datasets from the binomial variance of the power, then I = 59, 99, 199 and so on to fit the computing budget (p. 492). Without extrapolation, choose I so that (I + 1)α is an integer, with an expected RMSE of about 1.2 times the binomial standard error in their study (p. 492). The inner loop of B = 199 in open_items_local_session.csv (HPC-4) satisfies that integer condition at α = .05.

## Fields that differ from the repository's records

None. The reference in open_items_local_session.csv gives no DOI; the DOI is 10.1080/01621459.2000.10474226.

## Questions for a person

None.
