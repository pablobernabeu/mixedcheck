| engine | models run ok | unsupported | errors/timeouts | at optimum (gap <= 1e-4 abs or 1e-9 rel) | near (gap <= 1e-2) | worse (gap > 1e-2) | max dbeta (SE units) | max rel dSE | median fit time ratio vs lme4 |
|---|---|---|---|---|---|---|---|---|---|
| R:lme4 | 27 | 0 | 0 | 27 | 0 | 0:  | 0.0e+00 | 0.0e+00 | 1.00 |
| R:glmmTMB | 25 | 0 | 0 | 21 | 0 | 4: crossed_ML, weighted_REML, weighted_ML, jq_REML | 1.4e-01 | 5.9e-01 | 13.46 |
| rpy2_lme4 | 27 | 0 | 0 | 27 | 0 | 0:  | 2.2e-08 | 1.2e-06 | 1.33 |
| glmm | 27 | 0 | 0 | 27 | 0 | 0:  | 5.3e-03 | 1.3e-02 | 0.07 |
| mixedlm | 27 | 0 | 0 | 27 | 0 | 0:  | 5.3e-03 | 2.2e-02 | 2.52 |
| statsmodels | 19 | 8 | 0 | 13 | 0 | 6: cbpp_agq25, cbpp_laplace, jq_REML, nearsing_ML, nearsing_REML, nearsing_zcp_ML | 4.8e-02 | 5.2e-01 | 5.38 |
| statsmodels:map | 2 | 0 | 0 | 0 | 0 | 2: cbpp_agq25, cbpp_laplace | 4.9e-01 | 3.8e-01 | 0.99 |
| gpboost_chol | 9 | 18 | 0 | 6 | 3 | 0:  | 1.1e-02 | 9.5e-03 | 15.66 |
| gpboost | 9 | 18 | 0 | 4 | 4 | 1: pastes_ML | 1.1e-02 | 6.3e-02 | 22.67 |
