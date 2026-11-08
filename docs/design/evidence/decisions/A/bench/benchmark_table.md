| model | engine | status | -2logL (common objective) | gap vs best | max abs dbeta (SE units) | max rel dSE | max rel dSD (boundary-safe) | max abs dcor | rel dsigma | reported minus common | conv | sing | warn | fit time s (median) | x lme4 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sleep_REML | R:lme4 | ok | 1743.6283 | 1.5e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 2.3e-13 | True | False | 0 | 0.0130 | 1.0 |
| sleep_REML | R:glmmTMB | ok | 1743.6283 | 1.6e-10 | 0.0e+00 | 5.0e-06 | 7.4e-06 | 1.2e-06 | 1.3e-06 | 4.5e-13 | True | None | 0 | 0.1860 | 14.3 |
| sleep_REML | rpy2_lme4 | ok | 1743.6283 | 1.5e-09 | 8.0e-15 | 6.7e-16 | 6.0e-16 | 5.6e-17 | 2.0e-15 | -2.3e-13 | None | False | 0 | 0.0168 | 1.3 |
| sleep_REML | glmm | ok | 1743.6283 | 2.0e-12 | 5.0e-14 | 5.7e-06 | 8.2e-06 | 2.7e-07 | 7.8e-07 | 1.5e-11 | True | False | 0 | 0.0008 | 0.1 |
| sleep_REML | mixedlm | ok | 1743.6283 | 0.0e+00 | 2.1e-13 | 5.9e-06 | 8.3e-06 | 8.3e-08 | 7.8e-07 | 0.0e+00 | True | False | 0 | 0.0639 | 4.9 |
| sleep_REML | statsmodels | ok | 1743.6283 | 6.6e-10 | 2.9e-14 | 2.1e-06 | 3.0e-06 | 1.6e-06 | 3.6e-07 | 0.0e+00 | True | None | 0 | 0.0408 | 3.1 |
| sleep_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| sleep_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| pen_REML | R:lme4 | ok | 330.8606 | 8.5e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -1.8e-12 | True | False | 0 | 0.0130 | 1.0 |
| pen_REML | R:glmmTMB | ok | 330.8606 | 1.8e-11 | 3.7e-13 | 2.6e-05 | 2.8e-05 | NA | 6.1e-07 | 1.2e-12 | True | None | 0 | 0.1750 | 13.5 |
| pen_REML | rpy2_lme4 | ok | 330.8606 | 8.5e-09 | 1.8e-14 | 2.2e-16 | 4.6e-16 | NA | 6.7e-16 | -6.8e-13 | None | False | 0 | 0.0160 | 1.2 |
| pen_REML | glmm | ok | 330.8606 | 3.0e-12 | 1.4e-12 | 2.7e-05 | 2.9e-05 | NA | 8.0e-07 | -2.6e-11 | True | False | 0 | 0.0008 | 0.1 |
| pen_REML | mixedlm | ok | 330.8606 | 0.0e+00 | 2.5e-12 | 2.7e-05 | 2.9e-05 | NA | 8.3e-07 | -4.0e-13 | True | False | 0 | 0.0720 | 5.5 |
| pen_REML | statsmodels | ok | 330.8606 | 1.3e-07 | 5.7e-14 | 2.6e-05 | 4.4e-05 | NA | 6.8e-06 | -5.1e-13 | True | None | 0 | 0.0174 | 1.3 |
| pen_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| pen_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| pastes_REML | R:lme4 | ok | 246.9907 | 3.4e-13 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -4.3e-13 | True | False | 0 | 0.0130 | 1.0 |
| pastes_REML | R:glmmTMB | ok | 246.9907 | 1.9e-11 | 1.0e-12 | 6.2e-07 | 2.3e-06 | NA | 2.7e-07 | -9.9e-13 | True | None | 0 | 0.1780 | 13.7 |
| pastes_REML | rpy2_lme4 | ok | 246.9907 | 2.8e-13 | 6.3e-14 | 4.4e-16 | 5.2e-16 | NA | 4.4e-16 | 5.7e-14 | None | False | 0 | 0.0176 | 1.4 |
| pastes_REML | glmm | ok | 246.9907 | 4.5e-10 | 4.7e-12 | 4.6e-06 | 1.5e-05 | NA | 6.7e-07 | 9.1e-10 | True | False | 0 | 0.0007 | 0.1 |
| pastes_REML | mixedlm | ok | 246.9907 | 0.0e+00 | 1.3e-12 | 2.9e-08 | 2.0e-07 | NA | 3.7e-08 | 5.7e-14 | True | False | 0 | 0.0720 | 5.5 |
| pastes_REML | statsmodels | ok | 246.9907 | 2.4e-07 | 9.6e-13 | 9.2e-05 | 3.3e-04 | NA | 3.1e-06 | -2.0e-13 | True | None | 0 | 0.0432 | 3.3 |
| pastes_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| pastes_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossed_REML | R:lme4 | ok | 25833.2265 | 9.0e-07 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 9.8e-11 | True | False | 0 | 0.1950 | 1.0 |
| crossed_REML | R:glmmTMB | ok | 25833.2265 | 5.0e-09 | 3.4e-12 | 3.1e-05 | 9.3e-05 | 1.2e-04 | 7.2e-07 | 1.3e-10 | True | None | 0 | 0.5760 | 3.0 |
| crossed_REML | rpy2_lme4 | ok | 25833.2265 | 9.0e-07 | 8.0e-14 | 1.1e-15 | 1.4e-15 | 5.0e-16 | 1.0e-15 | 0.0e+00 | None | False | 0 | 0.2121 | 1.1 |
| crossed_REML | glmm | ok | 25833.2265 | 1.1e-09 | 3.9e-12 | 3.6e-05 | 9.7e-05 | 1.3e-04 | 1.3e-06 | 4.0e-10 | True | False | 0 | 0.0171 | 0.1 |
| crossed_REML | mixedlm | ok | 25833.2265 | 0.0e+00 | 3.1e-12 | 3.6e-05 | 9.8e-05 | 1.3e-04 | 1.2e-06 | -7.3e-12 | True | False | 0 | 0.1688 | 0.9 |
| crossed_REML | statsmodels | unsupported: correlated random slopes for more than one grouping factor (crossed) a | | | | | | | | | | | | | |
| crossed_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossed_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossed_zcp_REML | R:lme4 | ok | 25834.8453 | 4.6e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | 3.3e-11 | True | False | 0 | 0.1190 | 1.0 |
| crossed_zcp_REML | R:glmmTMB | ok | 25834.8453 | 7.3e-12 | 1.4e-12 | 3.7e-06 | 9.2e-06 | NA | 1.3e-07 | -1.4e-10 | True | None | 0 | 0.4900 | 4.1 |
| crossed_zcp_REML | rpy2_lme4 | ok | 25834.8453 | 4.6e-09 | 9.1e-14 | 4.4e-16 | 1.4e-15 | NA | 6.7e-16 | 7.3e-12 | None | False | 0 | 0.1387 | 1.2 |
| crossed_zcp_REML | glmm | ok | 25834.8453 | 1.7e-09 | 6.4e-12 | 4.6e-06 | 1.4e-05 | NA | 1.7e-07 | 7.3e-10 | True | False | 0 | 0.0113 | 0.1 |
| crossed_zcp_REML | mixedlm | ok | 25834.8453 | 0.0e+00 | 8.0e-12 | 3.6e-06 | 9.0e-06 | NA | 1.6e-07 | -3.6e-12 | True | False | 0 | 0.1981 | 1.7 |
| crossed_zcp_REML | statsmodels | ok | 25834.8453 | 3.9e-08 | 1.9e-11 | 1.3e-05 | 2.7e-05 | NA | 1.8e-07 | 0.0e+00 | True | None | 0 | 37.2998 | 313.4 |
| crossed_zcp_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossed_zcp_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| school_REML | R:lme4 | ok | 14103.6695 | 2.8e-07 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 1.8e-12 | True | False | 0 | 0.0540 | 1.0 |
| school_REML | R:glmmTMB | ok | 14103.6695 | 5.7e-10 | 6.2e-05 | 2.4e-02 | 4.1e-05 | 4.5e-05 | 1.6e-06 | 1.6e-11 | True | None | 0 | 0.4010 | 7.4 |
| school_REML | rpy2_lme4 | ok | 14103.6695 | 2.8e-07 | 7.8e-15 | 4.0e-15 | 5.7e-16 | 1.1e-16 | 6.7e-16 | 1.8e-12 | None | False | 0 | 0.0804 | 1.5 |
| school_REML | glmm | ok | 14103.6695 | 7.1e-11 | 6.7e-05 | 3.7e-05 | 4.1e-05 | 4.8e-05 | 1.5e-06 | -2.0e-11 | True | False | 0 | 0.0036 | 0.1 |
| school_REML | mixedlm | ok | 14103.6695 | 0.0e+00 | 6.6e-05 | 3.7e-05 | 4.2e-05 | 4.7e-05 | 1.5e-06 | -3.6e-12 | True | False | 0 | 0.1360 | 2.5 |
| school_REML | statsmodels | ok | 14103.6695 | 1.7e-06 | 1.2e-04 | 2.4e-02 | 7.9e-05 | 7.6e-05 | 1.7e-06 | 1.8e-12 | True | None | 0 | 0.3001 | 5.6 |
| school_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| school_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| nearsing_REML | R:lme4 | ok | 140.9206 | 5.4e-10 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | -5.7e-14 | True | True | 0 | 0.0120 | 1.0 |
| nearsing_REML | R:glmmTMB | ok | 140.9206 | 5.7e-07 | 1.3e-11 | 6.8e-06 | 4.3e-05 | 4.2e-06 | 6.2e-07 | 6.1e-11 | False | None | 3 | 0.2080 | 17.3 |
| nearsing_REML | rpy2_lme4 | ok | 140.9206 | 5.4e-10 | 6.5e-15 | 8.9e-16 | 4.6e-16 | 1.1e-15 | 3.3e-16 | -5.7e-14 | None | True | 0 | 0.0168 | 1.4 |
| nearsing_REML | glmm | ok | 140.9206 | 0.0e+00 | 2.0e-14 | 6.5e-06 | 3.6e-05 | 1.1e-15 | 6.2e-07 | 1.1e-13 | True | True | 4 | 0.0010 | 0.1 |
| nearsing_REML | mixedlm | ok | 140.9206 | 2.8e-14 | 9.6e-15 | 6.5e-06 | 3.6e-05 | 8.9e-16 | 6.2e-07 | 0.0e+00 | True | True | 3 | 0.1921 | 16.0 |
| nearsing_REML | statsmodels | ok | 141.4554 | 5.3e-01 | 1.8e-14 | 9.6e-02 | 1.8e+00 | 8.1e-01 | 1.8e-03 | -2.8e-14 | False | None | 8 | 0.1321 | 11.0 |
| nearsing_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| nearsing_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| weighted_REML | R:lme4 | ok | 866.7729 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -4.5e-13 | True | False | 0 | 0.0120 | 1.0 |
| weighted_REML | R:glmmTMB | ok | 1602.9947 | 7.4e+02 | 1.3e-01 | 5.9e-01 | 1.5e-02 | NA | 5.9e-01 | 2.1e+03 | True | None | 0 | 0.1910 | 15.9 |
| weighted_REML | rpy2_lme4 | ok | 866.7729 | 1.1e-13 | 5.8e-14 | 1.3e-15 | 3.9e-16 | NA | 6.7e-16 | 2.3e-13 | None | False | 0 | 0.0170 | 1.4 |
| weighted_REML | glmm | ok | 866.7729 | 0.0e+00 | 5.7e-09 | 1.6e-08 | 1.6e-08 | NA | 1.9e-09 | 2.3e-13 | True | False | 0 | 0.0008 | 0.1 |
| weighted_REML | mixedlm | ok | 866.7729 | 0.0e+00 | 6.1e-09 | 1.7e-08 | 1.7e-08 | NA | 2.0e-09 | 1.1e-13 | True | False | 0 | 0.0400 | 3.3 |
| weighted_REML | statsmodels | unsupported: MixedLM has no prior/precision weights argument | | | | | | | | | | | | | |
| weighted_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| weighted_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| sleep_ML | R:lme4 | ok | 1751.9393 | 2.6e-08 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | -1.1e-12 | True | False | 0 | 0.0120 | 1.0 |
| sleep_ML | R:glmmTMB | ok | 1751.9393 | 5.1e-10 | 8.9e-06 | 2.3e-05 | 3.4e-05 | 4.8e-06 | 3.2e-06 | 2.3e-13 | True | None | 0 | 0.2000 | 16.7 |
| sleep_ML | rpy2_lme4 | ok | 1751.9393 | 2.6e-08 | 5.1e-14 | 4.4e-16 | 3.1e-16 | 2.4e-16 | 1.4e-15 | 0.0e+00 | None | False | 0 | 0.0166 | 1.4 |
| sleep_ML | glmm | ok | 1751.9393 | 3.5e-11 | 1.6e-13 | 2.4e-05 | 3.5e-05 | 1.3e-07 | 3.7e-06 | 1.1e-11 | True | False | 0 | 0.0009 | 0.1 |
| sleep_ML | mixedlm | ok | 1751.9393 | 0.0e+00 | 2.5e-13 | 2.3e-05 | 3.4e-05 | 1.0e-06 | 3.6e-06 | -4.5e-13 | True | False | 0 | 0.0560 | 4.7 |
| sleep_ML | statsmodels | ok | 1751.9393 | 1.2e-09 | 2.2e-13 | 2.5e-05 | 3.7e-05 | 1.2e-07 | 4.4e-06 | 2.3e-13 | True | None | 0 | 0.0291 | 2.4 |
| sleep_ML | gpboost_chol | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| sleep_ML | gpboost | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| pen_ML | R:lme4 | ok | 332.1883 | 1.4e-11 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -2.3e-13 | True | False | 0 | 0.0120 | 1.0 |
| pen_ML | R:glmmTMB | ok | 332.1883 | 7.0e-12 | 6.2e-07 | 1.2e-06 | 1.3e-06 | NA | 1.5e-07 | 8.5e-13 | True | None | 0 | 0.1830 | 15.2 |
| pen_ML | rpy2_lme4 | ok | 332.1883 | 1.4e-11 | 2.9e-14 | 2.2e-16 | 6.3e-16 | NA | 6.7e-16 | 1.1e-13 | None | False | 0 | 0.0160 | 1.3 |
| pen_ML | glmm | ok | 332.1883 | 0.0e+00 | 4.8e-14 | 7.0e-07 | 7.3e-07 | NA | 1.1e-07 | 1.0e-12 | True | False | 0 | 0.0009 | 0.1 |
| pen_ML | mixedlm | ok | 332.1883 | 1.5e-12 | 4.3e-12 | 4.6e-07 | 4.6e-07 | NA | 9.6e-08 | -4.5e-13 | True | False | 0 | 0.0759 | 6.3 |
| pen_ML | statsmodels | ok | 332.1883 | 8.8e-08 | 2.1e-12 | 1.8e-06 | 4.4e-05 | NA | 7.9e-06 | 8.0e-13 | True | None | 0 | 0.0152 | 1.3 |
| pen_ML | gpboost_chol | ok | 332.1883 | 5.2e-11 | 5.9e-12 | 2.2e-06 | 2.4e-06 | NA | 7.4e-08 | 4.0e-12 | None | None | 0 | 0.2939 | 24.5 |
| pen_ML | gpboost | ok | 332.1892 | 8.3e-04 | 1.1e-11 | 1.3e-03 | 4.1e-03 | NA | 8.2e-04 | 5.4e-01 | None | None | 0 | 2.1320 | 177.7 |
| pastes_ML | R:lme4 | ok | 247.9945 | 4.7e-10 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -6.5e-13 | True | False | 0 | 0.0120 | 1.0 |
| pastes_ML | R:glmmTMB | ok | 247.9945 | 4.5e-13 | 1.6e-08 | 9.9e-07 | 1.0e-05 | NA | 1.6e-06 | 5.7e-13 | True | None | 0 | 0.1940 | 16.2 |
| pastes_ML | rpy2_lme4 | ok | 247.9945 | 4.7e-10 | 6.6e-14 | 6.7e-16 | 6.1e-16 | NA | 2.2e-16 | 5.7e-14 | None | False | 0 | 0.0151 | 1.3 |
| pastes_ML | glmm | ok | 247.9945 | 3.1e-12 | 5.2e-13 | 1.2e-06 | 1.1e-05 | NA | 1.5e-06 | 9.2e-10 | True | False | 0 | 0.0009 | 0.1 |
| pastes_ML | mixedlm | ok | 247.9945 | 0.0e+00 | 1.0e-12 | 8.8e-07 | 9.8e-06 | NA | 1.6e-06 | 5.7e-14 | True | False | 0 | 0.0639 | 5.3 |
| pastes_ML | statsmodels | ok | 247.9945 | 3.3e-08 | 7.0e-13 | 3.5e-05 | 1.4e-04 | NA | 4.9e-06 | 5.7e-14 | True | None | 0 | 0.0353 | 2.9 |
| pastes_ML | gpboost_chol | ok | 247.9945 | 2.9e-06 | 7.3e-13 | 3.4e-04 | 1.5e-03 | NA | 3.4e-05 | -1.1e-13 | None | None | 0 | 0.3579 | 29.8 |
| pastes_ML | gpboost | ok | 248.1185 | 1.2e-01 | 5.9e-12 | 6.3e-02 | 3.4e-01 | NA | 3.9e-03 | 5.1e-01 | None | None | 0 | 0.4598 | 38.3 |
| crossed_ML | R:lme4 | ok | 25842.3898 | 4.1e-08 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | -2.2e-11 | True | False | 0 | 0.2030 | 1.0 |
| crossed_ML | R:glmmTMB | ok | 25849.4846 | 7.1e+00 | 7.6e-05 | 1.7e-01 | 9.5e-01 | 9.5e-01 | 6.5e-03 | NA | False | None | 3 | 1.0540 | 5.2 |
| crossed_ML | rpy2_lme4 | ok | 25842.3898 | 4.1e-08 | 1.1e-14 | 8.9e-16 | 9.9e-16 | 2.2e-16 | 4.4e-16 | -3.6e-12 | None | False | 0 | 0.2115 | 1.0 |
| crossed_ML | glmm | ok | 25842.3898 | 9.6e-10 | 1.3e-12 | 7.7e-06 | 2.4e-05 | 2.3e-05 | 3.2e-07 | 1.5e-10 | True | False | 0 | 0.0181 | 0.1 |
| crossed_ML | mixedlm | ok | 25842.3898 | 0.0e+00 | 3.5e-13 | 7.7e-06 | 2.5e-05 | 2.6e-05 | 2.4e-07 | -3.6e-12 | True | False | 0 | 0.1041 | 0.5 |
| crossed_ML | statsmodels | unsupported: correlated random slopes for more than one grouping factor (crossed) a | | | | | | | | | | | | | |
| crossed_ML | gpboost_chol | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| crossed_ML | gpboost | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| crossed_zcp_ML | R:lme4 | ok | 25844.0226 | 4.8e-08 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -1.0e-10 | True | False | 0 | 0.1130 | 1.0 |
| crossed_zcp_ML | R:glmmTMB | ok | 25844.0226 | 4.8e-08 | 1.9e-04 | 1.0e-05 | 4.5e-05 | NA | 1.5e-07 | -4.4e-11 | True | None | 0 | 0.6390 | 5.7 |
| crossed_zcp_ML | rpy2_lme4 | ok | 25844.0226 | 4.8e-08 | 3.4e-14 | 8.9e-16 | 1.3e-15 | NA | 2.2e-16 | 0.0e+00 | None | False | 0 | 0.1368 | 1.2 |
| crossed_zcp_ML | glmm | ok | 25844.0226 | 5.5e-11 | 3.1e-12 | 1.1e-05 | 4.0e-05 | NA | 5.9e-07 | 7.1e-10 | True | False | 0 | 0.0109 | 0.1 |
| crossed_zcp_ML | mixedlm | ok | 25844.0226 | 0.0e+00 | 7.1e-12 | 1.1e-05 | 4.0e-05 | NA | 6.0e-07 | 0.0e+00 | True | False | 0 | 0.1799 | 1.6 |
| crossed_zcp_ML | statsmodels | ok | 25844.0226 | 1.3e-06 | 2.1e-11 | 5.9e-05 | 1.6e-04 | NA | 1.6e-06 | 0.0e+00 | True | None | 0 | 14.9972 | 132.7 |
| crossed_zcp_ML | gpboost_chol | ok | 25844.0260 | 3.4e-03 | 1.1e-12 | 5.5e-04 | 1.1e-02 | NA | 6.6e-05 | 0.0e+00 | None | None | 0 | 0.7150 | 6.3 |
| crossed_zcp_ML | gpboost | ok | 25844.0279 | 5.3e-03 | 5.8e-11 | 5.4e-04 | 1.3e-02 | NA | 6.2e-05 | -8.4e-02 | None | None | 0 | 2.5613 | 22.7 |
| school_ML | R:lme4 | ok | 14099.8161 | 3.8e-07 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | -7.3e-12 | True | False | 0 | 0.0490 | 1.0 |
| school_ML | R:glmmTMB | ok | 14099.8161 | 2.4e-10 | 2.5e-05 | 2.4e-02 | 6.3e-05 | 4.1e-05 | 6.2e-07 | -5.5e-12 | True | None | 0 | 0.3700 | 7.6 |
| school_ML | rpy2_lme4 | ok | 14099.8161 | 3.8e-07 | 1.6e-14 | 2.0e-15 | 3.6e-16 | 0.0e+00 | 6.7e-16 | 0.0e+00 | None | False | 0 | 0.0799 | 1.6 |
| school_ML | glmm | ok | 14099.8161 | 4.7e-11 | 2.6e-05 | 6.0e-05 | 6.3e-05 | 4.1e-05 | 7.6e-07 | -5.8e-11 | True | False | 0 | 0.0036 | 0.1 |
| school_ML | mixedlm | ok | 14099.8161 | 0.0e+00 | 2.6e-05 | 5.9e-05 | 6.3e-05 | 4.1e-05 | 7.6e-07 | 1.8e-12 | True | False | 0 | 0.1174 | 2.4 |
| school_ML | statsmodels | ok | 14099.8161 | 7.4e-08 | 6.6e-05 | 2.4e-02 | 3.3e-05 | 6.6e-05 | 3.3e-07 | 0.0e+00 | True | None | 0 | 0.2634 | 5.4 |
| school_ML | gpboost_chol | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| school_ML | gpboost | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| nearsing_ML | R:lme4 | ok | 136.6865 | 7.4e-11 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | -2.8e-14 | True | True | 0 | 0.0120 | 1.0 |
| nearsing_ML | R:glmmTMB | ok | 136.6865 | 7.4e-07 | 5.4e-09 | 2.2e-06 | 1.1e-05 | 4.9e-06 | 2.7e-07 | 2.1e-11 | False | None | 3 | 0.2140 | 17.8 |
| nearsing_ML | rpy2_lme4 | ok | 136.6865 | 7.4e-11 | 1.0e-14 | 2.2e-16 | 3.4e-16 | 2.4e-15 | 2.2e-16 | -2.8e-14 | None | True | 0 | 0.0178 | 1.5 |
| nearsing_ML | glmm | ok | 136.6865 | 0.0e+00 | 8.2e-15 | 2.1e-06 | 1.0e-05 | 2.4e-15 | 2.8e-07 | 1.4e-13 | True | True | 4 | 0.0010 | 0.1 |
| nearsing_ML | mixedlm | ok | 136.6865 | 0.0e+00 | 2.2e-14 | 2.1e-06 | 1.0e-05 | 2.7e-15 | 2.8e-07 | 2.8e-14 | True | True | 3 | 0.1253 | 10.4 |
| nearsing_ML | statsmodels | ok | 136.8307 | 1.4e-01 | 4.4e-15 | 2.3e-02 | 6.5e-01 | 4.2e-01 | 2.3e-03 | -8.5e-14 | True | None | 3 | 0.0836 | 7.0 |
| nearsing_ML | gpboost_chol | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| nearsing_ML | gpboost | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| weighted_ML | R:lme4 | ok | 862.5425 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | 1.3e-12 | True | False | 0 | 0.0110 | 1.0 |
| weighted_ML | R:glmmTMB | ok | 1597.8291 | 7.4e+02 | 1.4e-01 | 5.9e-01 | 1.6e-02 | NA | 5.9e-01 | 2.1e+03 | True | None | 0 | 0.1870 | 17.0 |
| weighted_ML | rpy2_lme4 | ok | 862.5425 | 2.3e-13 | 5.1e-14 | 6.7e-16 | 2.7e-16 | NA | 2.0e-15 | 6.8e-13 | None | False | 0 | 0.0150 | 1.4 |
| weighted_ML | glmm | ok | 862.5425 | 1.1e-13 | 9.7e-10 | 2.6e-09 | 2.7e-09 | NA | 3.2e-10 | -3.4e-13 | True | False | 0 | 0.0008 | 0.1 |
| weighted_ML | mixedlm | ok | 862.5425 | 2.3e-13 | 9.4e-10 | 2.5e-09 | 2.6e-09 | NA | 3.1e-10 | 5.7e-13 | True | False | 0 | 0.0479 | 4.4 |
| weighted_ML | statsmodels | unsupported: MixedLM has no prior/precision weights argument | | | | | | | | | | | | | |
| weighted_ML | gpboost_chol | ok | 862.5425 | 1.3e-11 | 1.6e-07 | 4.3e-07 | 4.5e-07 | NA | 5.4e-08 | 2.3e-13 | None | None | 0 | 0.1353 | 12.3 |
| weighted_ML | gpboost | ok | 862.5425 | 1.3e-11 | 1.6e-07 | 4.3e-07 | 4.5e-07 | NA | 5.4e-08 | 2.3e-13 | None | None | 0 | 0.1479 | 13.4 |
| sleep_zcp_ML | R:lme4 | ok | 1752.0033 | 4.7e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | -1.1e-12 | True | False | 0 | 0.0130 | 1.0 |
| sleep_zcp_ML | R:glmmTMB | ok | 1752.0033 | 4.5e-10 | 1.5e-05 | 1.1e-05 | 1.5e-05 | NA | 4.4e-07 | 9.1e-13 | True | None | 0 | 0.1990 | 15.3 |
| sleep_zcp_ML | rpy2_lme4 | ok | 1752.0033 | 4.7e-09 | 1.7e-14 | 2.3e-15 | 4.6e-16 | NA | 1.2e-15 | 0.0e+00 | None | False | 0 | 0.0162 | 1.2 |
| sleep_zcp_ML | glmm | ok | 1752.0033 | 0.0e+00 | 2.8e-13 | 9.5e-06 | 1.3e-05 | NA | 4.5e-07 | 1.3e-11 | True | False | 0 | 0.0008 | 0.1 |
| sleep_zcp_ML | mixedlm | ok | 1752.0033 | 0.0e+00 | 5.5e-13 | 9.5e-06 | 1.3e-05 | NA | 4.6e-07 | 0.0e+00 | True | False | 0 | 0.0975 | 7.5 |
| sleep_zcp_ML | statsmodels | ok | 1752.0033 | 1.0e-11 | 3.1e-13 | 9.0e-06 | 1.3e-05 | NA | 4.2e-07 | -2.3e-13 | True | None | 0 | 0.0568 | 4.4 |
| sleep_zcp_ML | gpboost_chol | ok | 1752.0033 | 7.5e-08 | 3.6e-13 | 4.7e-05 | 6.8e-05 | NA | 6.8e-06 | -2.3e-13 | None | None | 0 | 0.4015 | 30.9 |
| sleep_zcp_ML | gpboost | ok | 1752.0033 | 4.2e-05 | 2.0e-13 | 9.7e-04 | 1.4e-03 | NA | 1.2e-04 | 1.7e-01 | None | None | 0 | 0.0063 | 0.5 |
| school_zcp_ML | R:lme4 | ok | 14105.9310 | 1.5e-07 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | 3.6e-12 | True | False | 0 | 0.0430 | 1.0 |
| school_zcp_ML | R:glmmTMB | ok | 14105.9310 | 3.0e-10 | 1.7e-05 | 1.1e-03 | 2.8e-05 | NA | 8.5e-07 | -1.8e-11 | True | None | 0 | 0.3630 | 8.4 |
| school_zcp_ML | rpy2_lme4 | ok | 14105.9310 | 1.5e-07 | 2.5e-14 | 1.8e-15 | 7.1e-16 | NA | 8.9e-16 | 3.6e-12 | None | False | 0 | 0.0722 | 1.7 |
| school_zcp_ML | glmm | ok | 14105.9310 | 9.1e-12 | 1.1e-05 | 1.9e-05 | 2.9e-05 | NA | 8.4e-07 | -1.0e-10 | True | False | 0 | 0.0028 | 0.1 |
| school_zcp_ML | mixedlm | ok | 14105.9310 | 0.0e+00 | 1.1e-05 | 1.9e-05 | 2.8e-05 | NA | 8.4e-07 | 0.0e+00 | True | False | 0 | 0.0960 | 2.2 |
| school_zcp_ML | statsmodels | ok | 14105.9310 | 2.4e-06 | 6.8e-05 | 1.1e-03 | 2.1e-04 | NA | 3.2e-07 | -3.6e-12 | True | None | 0 | 0.3150 | 7.3 |
| school_zcp_ML | gpboost_chol | ok | 14105.9310 | 4.8e-08 | 1.5e-05 | 3.6e-05 | 4.6e-05 | NA | 4.6e-07 | -1.8e-12 | None | None | 0 | 0.6733 | 15.7 |
| school_zcp_ML | gpboost | ok | 14105.9363 | 5.3e-03 | 1.1e-03 | 5.8e-04 | 7.0e-03 | NA | 2.3e-04 | -6.0e-01 | None | None | 0 | 1.8574 | 43.2 |
| nearsing_zcp_ML | R:lme4 | ok | 136.8288 | 2.8e-14 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | 5.7e-14 | True | True | 0 | 0.0120 | 1.0 |
| nearsing_zcp_ML | R:glmmTMB | ok | 136.8288 | 1.2e-08 | 3.2e-08 | 7.9e-09 | 1.1e-02 | NA | 1.1e-09 | 2.8e-14 | True | None | 0 | 0.1920 | 16.0 |
| nearsing_zcp_ML | rpy2_lme4 | ok | 136.8288 | 2.8e-14 | 6.5e-15 | 1.1e-16 | 1.5e-16 | NA | 2.2e-16 | 2.8e-14 | None | True | 0 | 0.0168 | 1.4 |
| nearsing_zcp_ML | glmm | ok | 136.8288 | 2.8e-14 | 9.8e-15 | 2.1e-08 | 3.7e-08 | NA | 4.3e-09 | 2.3e-13 | True | True | 4 | 0.0007 | 0.1 |
| nearsing_zcp_ML | mixedlm | ok | 136.8288 | 0.0e+00 | 1.8e-14 | 9.0e-09 | 1.6e-08 | NA | 1.9e-09 | 2.8e-14 | True | True | 3 | 0.0482 | 4.0 |
| nearsing_zcp_ML | statsmodels | ok | 136.8416 | 1.3e-02 | 5.3e-15 | 1.6e-02 | 7.3e+00 | NA | 3.3e-03 | -2.8e-14 | True | None | 3 | 0.0818 | 6.8 |
| nearsing_zcp_ML | gpboost_chol | ok | 136.8289 | 1.1e-04 | 3.9e-15 | 1.5e-04 | 1.0e+00 | NA | 2.7e-05 | 0.0e+00 | None | None | 0 | 0.9684 | 80.7 |
| nearsing_zcp_ML | gpboost | ok | 136.8289 | 7.0e-05 | 4.6e-08 | 7.2e-05 | 8.3e-01 | NA | 1.7e-05 | 4.2e-05 | None | None | 0 | 3.6087 | 300.7 |
| crossedbig_REML | R:lme4 | ok | 128829.7996 | 9.7e-08 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 2.9e-11 | True | False | 0 | 1.3530 | 1.0 |
| crossedbig_REML | R:glmmTMB | ok | 128829.7996 | 8.4e-08 | 1.2e-11 | 3.1e-06 | 2.8e-05 | 2.0e-05 | 9.2e-07 | 1.2e-10 | True | None | 0 | 2.3690 | 1.8 |
| crossedbig_REML | rpy2_lme4 | ok | 128829.7996 | 9.7e-08 | 6.8e-14 | 1.1e-15 | 5.3e-16 | 2.9e-16 | 1.1e-16 | 0.0e+00 | None | False | 0 | 1.3412 | 1.0 |
| crossedbig_REML | glmm | ok | 128829.7996 | 5.5e-09 | 2.9e-11 | 4.3e-06 | 1.7e-05 | 9.3e-06 | 1.7e-07 | 3.0e-09 | True | False | 0 | 0.4225 | 0.3 |
| crossedbig_REML | mixedlm | ok | 128829.7996 | 0.0e+00 | 8.9e-12 | 5.0e-06 | 1.4e-05 | 8.3e-06 | 1.7e-07 | -1.5e-11 | True | False | 0 | 0.5039 | 0.4 |
| crossedbig_REML | statsmodels | unsupported: correlated random slopes for more than one grouping factor (crossed) a | | | | | | | | | | | | | |
| crossedbig_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossedbig_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossedbig_zcp_REML | R:lme4 | ok | 128833.9807 | 2.6e-07 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 0.0e+00 | 1.5e-10 | True | False | 0 | 0.8660 | 1.0 |
| crossedbig_zcp_REML | R:glmmTMB | ok | 128833.9807 | 1.3e-08 | 4.0e-11 | 1.6e-05 | 6.0e-05 | NA | 5.1e-07 | -3.3e-10 | True | None | 0 | 1.8040 | 2.1 |
| crossedbig_zcp_REML | rpy2_lme4 | ok | 128833.9807 | 2.6e-07 | 5.1e-14 | 1.3e-15 | 6.6e-16 | NA | 1.0e-15 | 5.8e-11 | None | False | 0 | 0.9494 | 1.1 |
| crossedbig_zcp_REML | glmm | ok | 128833.9807 | 4.8e-10 | 5.8e-11 | 1.5e-05 | 6.3e-05 | NA | 3.2e-07 | 4.0e-09 | True | False | 0 | 0.2739 | 0.3 |
| crossedbig_zcp_REML | mixedlm | ok | 128833.9807 | 0.0e+00 | 3.1e-11 | 1.5e-05 | 6.2e-05 | NA | 3.1e-07 | -2.9e-11 | True | False | 0 | 0.8479 | 1.0 |
| crossedbig_zcp_REML | statsmodels | ok | 128833.9807 | 1.5e-06 | 9.6e-12 | 2.0e-05 | 1.4e-04 | NA | 4.4e-07 | 0.0e+00 | True | None | 0 | 154.5794 | 178.5 |
| crossedbig_zcp_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| crossedbig_zcp_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| cbpp_laplace | R:lme4 | ok | 184.0526 | 8.7e-06 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | NA | 5.6e-04 | True | False | 0 | 0.0510 | 1.0 |
| cbpp_laplace | R:glmmTMB | ok | 184.0526 | 7.5e-12 | 1.4e-03 | 1.3e-02 | 3.0e-04 | NA | NA | 1.5e-12 | True | None | 0 | 0.1890 | 3.7 |
| cbpp_laplace | rpy2_lme4 | ok | 184.0526 | 8.7e-06 | 1.4e-14 | 2.0e-15 | 5.2e-16 | NA | NA | 5.6e-04 | None | False | 0 | 0.0579 | 1.1 |
| cbpp_laplace | glmm | ok | 184.0526 | 0.0e+00 | 1.4e-03 | 1.3e-02 | 3.0e-04 | NA | NA | 8.5e-14 | True | False | 0 | 0.0011 | 0.0 |
| cbpp_laplace | mixedlm | ok | 184.0526 | 5.2e-12 | 1.4e-03 | 1.6e-02 | 3.0e-04 | NA | NA | 0.0e+00 | True | False | 0 | 0.0820 | 1.6 |
| cbpp_laplace | statsmodels | ok | 184.1210 | 6.8e-02 | 4.8e-02 | 5.2e-01 | 7.5e-02 | NA | NA | NA | None | None | 0 | 0.0828 | 1.6 |
| cbpp_laplace | statsmodels:map | ok | 198.1078 | 1.4e+01 | 4.9e-01 | 3.8e-01 | 1.0e+00 | NA | NA | NA | None | None | 3 | 0.0517 | 1.0 |
| cbpp_laplace | gpboost_chol | ok | 184.0526 | 6.7e-06 | 1.0e-03 | 9.5e-03 | 1.8e-04 | NA | NA | 5.7e-08 | None | None | 0 | 0.0698 | 1.4 |
| cbpp_laplace | gpboost | ok | 184.0526 | 6.7e-06 | 1.0e-03 | 9.5e-03 | 1.8e-04 | NA | NA | 5.7e-08 | None | None | 0 | 0.0058 | 0.1 |
| cbpp_agq25 | R:lme4 | ok | 183.9667 | 3.4e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | NA | -8.4e+01 | True | False | 0 | 0.0480 | 1.0 |
| cbpp_agq25 | rpy2_lme4 | ok | 183.9667 | 3.4e-09 | 1.3e-14 | 1.1e-15 | 5.1e-16 | NA | NA | -8.4e+01 | None | False | 0 | 0.0657 | 1.4 |
| cbpp_agq25 | glmm | ok | 183.9667 | 2.9e-12 | 3.0e-05 | 3.6e-06 | 1.9e-06 | NA | NA | 5.7e-14 | True | False | 0 | 0.0032 | 0.1 |
| cbpp_agq25 | mixedlm | ok | 183.9667 | 0.0e+00 | 3.0e-05 | 2.0e-02 | 2.3e-06 | NA | NA | 8.5e-14 | True | False | 0 | 0.0890 | 1.9 |
| cbpp_agq25 | statsmodels | ok | 184.0203 | 5.4e-02 | 4.3e-02 | 5.2e-01 | 6.6e-02 | NA | NA | NA | None | None | 0 | 0.0805 | 1.7 |
| cbpp_agq25 | statsmodels:map | ok | 198.1078 | 1.4e+01 | 4.9e-01 | 3.8e-01 | 1.0e+00 | NA | NA | NA | None | None | 3 | 0.0460 | 1.0 |
| cbpp_agq25 | gpboost_chol | unsupported: Laplace approximation only (no adaptive quadrature) | | | | | | | | | | | | | |
| cbpp_agq25 | gpboost | unsupported: Laplace approximation only (no adaptive quadrature) | | | | | | | | | | | | | |
| owls_pois | R:lme4 | ok | 5202.7760 | 8.7e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | NA | 2.9e-06 | True | False | 0 | 0.0670 | 1.0 |
| owls_pois | R:glmmTMB | ok | 5202.7760 | 3.0e-11 | 7.5e-05 | 1.5e-03 | 4.5e-06 | NA | NA | 9.1e-13 | True | None | 0 | 0.2050 | 3.1 |
| owls_pois | rpy2_lme4 | ok | 5202.7760 | 8.7e-09 | 2.2e-08 | 1.2e-06 | 9.9e-08 | NA | NA | 2.9e-06 | None | False | 0 | 0.0906 | 1.4 |
| owls_pois | glmm | ok | 5202.7760 | 0.0e+00 | 7.0e-05 | 1.5e-03 | 5.1e-06 | NA | NA | 8.2e-12 | True | False | 0 | 0.0035 | 0.1 |
| owls_pois | mixedlm | ok | 5202.7760 | 2.7e-11 | 7.3e-05 | 1.5e-03 | 4.5e-06 | NA | NA | 0.0e+00 | True | False | 0 | 0.1428 | 2.1 |
| owls_pois | statsmodels | unsupported: no offset in MixedLM or the Bayesian mixed GLMs | | | | | | | | | | | | | |
| owls_pois | gpboost_chol | ok | 5202.7763 | 2.8e-04 | 1.1e-02 | 1.5e-03 | 1.7e-03 | NA | NA | 1.7e-06 | None | None | 0 | 0.0214 | 0.3 |
| owls_pois | gpboost | ok | 5202.7763 | 2.8e-04 | 1.1e-02 | 1.5e-03 | 1.7e-03 | NA | NA | 1.7e-06 | None | None | 0 | 0.0546 | 0.8 |
| owls_pois_agq25 | R:lme4 | ok | 5202.7452 | 4.6e-09 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | NA | -1.7e+03 | True | False | 0 | 0.1110 | 1.0 |
| owls_pois_agq25 | rpy2_lme4 | ok | 5202.7452 | 4.6e-09 | 2.2e-08 | 4.2e-07 | 9.9e-08 | NA | NA | -1.7e+03 | None | False | 0 | 0.1281 | 1.2 |
| owls_pois_agq25 | glmm | ok | 5202.7452 | 0.0e+00 | 5.6e-05 | 3.3e-06 | 3.7e-06 | NA | NA | 4.5e-12 | True | False | 0 | 0.0086 | 0.1 |
| owls_pois_agq25 | mixedlm | ok | 5202.7452 | 6.0e-11 | 5.5e-05 | 7.4e-04 | 2.7e-06 | NA | NA | -9.1e-13 | True | False | 0 | 0.1618 | 1.5 |
| owls_pois_agq25 | statsmodels | unsupported: no offset in MixedLM or the Bayesian mixed GLMs | | | | | | | | | | | | | |
| owls_pois_agq25 | gpboost_chol | unsupported: Laplace approximation only (no adaptive quadrature) | | | | | | | | | | | | | |
| owls_pois_agq25 | gpboost | unsupported: Laplace approximation only (no adaptive quadrature) | | | | | | | | | | | | | |
| binxd_laplace | R:lme4 | ok | 1421.6587 | 3.5e-05 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | NA | 1.6e-03 | True | False | 0 | 0.2960 | 1.0 |
| binxd_laplace | R:glmmTMB | ok | 1421.6587 | 3.3e-09 | 5.2e-03 | 8.7e-03 | 5.8e-04 | 3.6e-04 | NA | 1.4e-08 | True | None | 0 | 0.2590 | 0.9 |
| binxd_laplace | rpy2_lme4 | ok | 1421.6587 | 3.5e-05 | 2.7e-15 | 1.1e-15 | 1.9e-15 | 1.6e-15 | NA | 1.6e-03 | None | False | 0 | 0.3362 | 1.1 |
| binxd_laplace | glmm | ok | 1421.6587 | 3.4e-11 | 5.3e-03 | 8.7e-03 | 5.8e-04 | 3.7e-04 | NA | 1.8e-12 | True | False | 0 | 0.0239 | 0.1 |
| binxd_laplace | mixedlm | ok | 1421.6587 | 0.0e+00 | 5.3e-03 | 2.2e-02 | 5.8e-04 | 3.7e-04 | NA | -1.6e-12 | True | False | 0 | 0.2618 | 0.9 |
| binxd_laplace | statsmodels | unsupported: only independent variance components | | | | | | | | | | | | | |
| binxd_laplace | gpboost_chol | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| binxd_laplace | gpboost | unsupported: correlated random intercept and slope (gpboost random coefficients are | | | | | | | | | | | | | |
| jq_REML | R:lme4 | ok | 187.3452 | 1.0e-08 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | 0.0e+00 | -2.8e-14 | True | True | 0 | 0.0130 | 1.0 |
| jq_REML | R:glmmTMB | ok | 187.3590 | 1.4e-02 | 6.7e-03 | 1.5e-02 | 1.5e-02 | 6.2e-02 | 2.9e-04 | NA | False | None | 6 | 0.1780 | 13.7 |
| jq_REML | rpy2_lme4 | ok | 187.3452 | 1.0e-08 | 2.3e-16 | 6.7e-16 | 1.9e-15 | 2.8e-15 | 2.7e-15 | 2.8e-14 | None | True | 0 | 0.0194 | 1.5 |
| jq_REML | glmm | ok | 187.3452 | 8.5e-14 | 9.2e-07 | 2.0e-05 | 2.6e-05 | 1.7e-05 | 7.3e-07 | -5.7e-14 | True | True | 4 | 0.0011 | 0.1 |
| jq_REML | mixedlm | ok | 187.3452 | 0.0e+00 | 9.7e-07 | 2.0e-05 | 2.6e-05 | 1.7e-05 | 7.5e-07 | -2.8e-14 | True | True | 6 | 0.3476 | 26.7 |
| jq_REML | statsmodels | ok | 188.5061 | 1.2e+00 | 1.4e-02 | 4.6e-01 | 5.6e-01 | 7.8e-02 | 1.2e-02 | -5.7e-14 | False | None | 8 | 0.1086 | 8.4 |
| jq_REML | gpboost_chol | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
| jq_REML | gpboost | unsupported: gpboost estimates by maximum likelihood only (no REML) | | | | | | | | | | | | | |
