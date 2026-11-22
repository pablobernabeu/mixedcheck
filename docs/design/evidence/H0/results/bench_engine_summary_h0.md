| engine | models run ok | unsupported | errors/timeouts | at optimum (gap <= 1e-4 abs or 1e-9 rel) | near (gap <= 1e-2) | worse (gap > 1e-2) | max dbeta (SE units) | max rel dSE | median fit time ratio vs lme4 |
|---|---|---|---|---|---|---|---|---|---|
| R:lme4 | 27 | 0 | 0 | 27 | 0 | 0:  | 0.0e+00 | 0.0e+00 | 1.00 |
| R:glmmTMB | 25 | 0 | 0 | 20 | 0 | 5: crossed_REML, crossed_zcp_REML, jq_REML, weighted_REML, weighted_ML | 1.4e-01 | 5.9e-01 | 3.76 |
| rpy2_lme4 | 27 | 0 | 0 | 27 | 0 | 0:  | 5.5e-05 | 3.7e-06 | 1.33 |
| glmm | 27 | 0 | 0 | 26 | 0 | 1: weighted_REML | 7.1e-03 | 8.8e-02 | 0.09 |
| mixedlm | 27 | 0 | 0 | 27 | 0 | 0:  | 8.7e-05 | 3.1e-02 | 0.40 |
| statsmodels | 19 | 8 | 0 | 13 | 0 | 6: cbpp_agq25, cbpp_laplace, jq_REML, nearsing_ML, nearsing_REML, nearsing_zcp_ML | 4.6e-02 | 5.2e-01 | 7.28 |
| statsmodels:map | 2 | 0 | 0 | 0 | 0 | 2: cbpp_agq25, cbpp_laplace | 4.9e-01 | 3.8e-01 | 1.26 |
| gpboost_chol | 9 | 18 | 0 | 6 | 3 | 0:  | 1.1e-02 | 1.4e-02 | 0.06 |
| gpboost | 9 | 18 | 0 | 4 | 4 | 1: pastes_ML | 1.1e-02 | 6.3e-02 | 0.24 |
