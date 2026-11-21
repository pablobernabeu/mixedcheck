# H0: environment and pilot on ARC

This folder records the H0 pilot of 03-execution-plan.md (H0): the environment built on Oxford's ARC, the cluster's limits, and reruns of the evidence scripts with current engines. The runs took place on 21 November 2026 on ARC's htc cluster, with jobs charged to the project educ-intract under the standard QoS. Each run read only simulated data or the example datasets that ship with lme4 and glmmTMB; the project had not been preregistered.

The evidence scripts in `../decisions/` ran unchanged in a copy of that folder in the project space. Only job settings differ from the original runs: the commands run inside the image below, wrappers replace the original queue and batch scripts, hard-coded paths point at the copy, and cores, memory and time limits fit ARC. Each change is stated in the wrapper that makes it (`slurm/`) and in that wrapper's commit message.

## ARC

A summary of what ARC reported on 21 November 2026, from login node arc-login02 and an htc compute node:

- **Software.** ARC provides R modules from 4.1.2 to 4.5.2 (4.5.1-gfbf-2025a and 4.5.2-gfbf-2025b are the newest). Apptainer 1.3.5 is installed on the compute nodes only.
- **Slurm limits (htc).** Slurm 20.11.7 with MaxArraySize 1001, so an array holds at most 1,000 tasks, and MaxJobCount 30000. Cores and memory are allocated separately (CR_CORE_MEMORY), and no default memory per CPU is set.
- **QoS.** The project's association has the QoS basic, priority and standard, with standard as the default, and no job or submission limits of its own. Of these QoS, only basic sets limits: one job per user and one day of wall time.
- **Partitions.** short (12 hours), medium (2 days), long (30 days, the default), devel (10 minutes, one node) and interactive (12 hours, two nodes).
- **CPU features.** The `cpu_gen:` feature names on htc are Cascade_Lake (Platinum 8268, 48 cores, 384 GB; also 96-core nodes with 3 TB) and Genoa (EPYC 9634 with 84 or 168 cores, EPYC 9645 with 192). GPU nodes add Skylake, Icelake, SapphireRapids and EmeraldRapids.
- **Network.** htc compute nodes have outbound network access. Posit Package Manager, Docker Hub's registry, CRAN, PyPI, conda-forge, GitHub and the Julia downloads all answered from a compute node, so the image pull and the builds ran as ordinary batch jobs and needed no interactive node.
- **Scratch.** `$SCRATCH` is the shared /scratch file system, not a per-job folder, so the wrappers use folders under the project space instead.

The project's credit was confirmed sufficient for H0; the balance is not recorded here.

## Environment

- **Image.** `rocker/r-ver:4.6.2`, pulled with `apptainer pull` by its linux/amd64 digest `sha256:1ca5bfbc810a4e176d74e05267a670e84de86b23a4a5791fa06862bfa35369ba` (read from Docker Hub and the registry on 21 November 2026). It is Ubuntu 26.04.1 with R 4.6.2 (2026-10-29) and R's recommended packages. The SIF file's SHA-256 is `26dc08355623001d859b98ce2b1c035ffbfb06408575a89e2956627d427052d6`.
- **R library.** Posit Package Manager snapshot of **2026-11-20**, Linux binaries for Ubuntu resolute. It holds lme4 2.1-0, glmmTMB 1.1.15.2, lmerTest 3.2-1, pbkrtest 0.5.5, clubSandwich 0.7.0 and jsonlite 2.0.0, beside the image's Matrix 1.7-6 and MASS 7.3-66. On that date these were CRAN's current lme4 (published 23 October 2026) and glmmTMB (29 September 2026). `LC_ALL=C.UTF-8` throughout.
- **Python.** CPython 3.12.16 (a standalone build installed by uv 0.13.9), run inside the image. There are two environments, limited to PyPI uploads before 21 November 2026:
  - venv312: statsmodels 0.15.0, mixedlm 1.3.0, glmm 0.9.3, gpboost 1.8.0, numpy 2.5.5, pandas 3.1.1 and scipy 1.18.1.
  - venv_pymer4: rpy2 3.5.17 with the same numpy, pandas and scipy.
- **rpy2 version.** rpy2 is held at 3.5.17, the version of the earlier benchmark, because `A/bench/engines.py` reads `rpy2.__version__`, which the split rpy2 3.6 packages no longer provide.
- **Embedded R.** The image builds R from source and does not register `libR.so` with the linker, so the rpy2 engine runs with R's lib directory on `LD_LIBRARY_PATH`. Ubuntu's own R needs no such setting.
- **Lockfile and record.** [`h0-lock-2026-11-20.csv`](h0-lock-2026-11-20.csv) lists every R package (91) and Python package (40, plus the interpreter of each environment) with its version and source, and [`h0-image.txt`](h0-image.txt) records the image and the snapshot date. Both were written inside the build job.

## Runs

The wrappers are in [`slurm/`](slurm/) and the summary script in [`scripts/`](scripts/). Outputs stay on ARC under `/data/educ-intract/educ1242/mixedcheck-h0/`, abbreviated to `H0` below, in the copy of the evidence `runs/h0-2026-11-21/decisions/`. CPU-hours are allocated CPUs times elapsed time; peak memory is Slurm's MaxRSS of the batch step (blank where the job was too short to sample).

| Run | Wrapper | Job IDs | Node | Wall time | CPU-hours | Peak memory | Full output |
|---|---|---|---|---|---|---|---|
| Network and runtime check | h0_nettest.sbatch | 9448117 | htc-c028 (Platinum 8268) | 26 s | 0.01 | | Slurm log |
| Image pull | h0_pull.sbatch | 9448125 | htc-c028 | 9 min 23 s | 0.63 | 0.30 GB | H0/images |
| Library and environments | h0_build.sbatch | 9448234 (after 9448135, 9448193 and 9448213 failed, see below) | htc-c021 (Platinum 8268) | 4 min 58 s | 0.66 | 0.12 GB | H0/lib, H0/envs, H0/lock |
| Benchmark, R reference | h0_bench_r.sbatch | 9448235 | htc-c021 | 1 min 29 s | 0.02 | 0.50 GB | A/bench/r_reference.json, A/bench/data |
| Benchmark, Python engines | h0_bench_py.sbatch | 9448236, tasks 1 to 6 | htc-c021 | 2 min 52 s to 5 min 43 s per task | 0.42 | 0.11 to 0.40 GB per task | A/bench/out |
| Benchmark, comparison | h0_bench_cmp.sbatch | 9448237 | htc-c028 | 27 s | 0.01 | | A/bench/comparison_rows.json, benchmark_table.csv |
| V1 pilot | h0_v1.sbatch | 9448238, tasks 1 to 6 | htc-c021 | 28 s to 54 s per task | 0.07 | 0.16 to 0.19 GB per task | H0/results/V1a-pilot |
| V1 collection | h0_v1_collect.sbatch | 9448239 | htc-c028 | 6 s | 0.00 | | H0/results/V1a-pilot_summary.csv |
| Re-time | h0_timing.sbatch | 9448240 | htc-c028 | 6 min 53 s | 0.46 | 0.67 GB | F/timing/out_h0 |
| Random-effects simulations | h0_bsim.sbatch | 9448241 | htc-c068 (EPYC 9634) | running | | | B/sim/out |
| Summaries | h0_summarise.sbatch | 9448284, 9448393 | | under 30 s | 0.01 | | H0/summaries |

Three builds failed before the one that succeeded, each on an environment detail rather than on the packages: the host's PATH does not reach the container (uv was then called by its path), `libR.so` was not found by rpy2 (fixed by `LD_LIBRARY_PATH`), and rpy2 3.6 lacks `rpy2.__version__` (fixed by rpy2 3.5.17). They used 0.83 CPU-hours together. The jobs that waited on them were cancelled before they started and resubmitted.

The summary tables in [`results/`](results/) pair each H0 value with the earlier value stored in the evidence, produced by [`scripts/summarise_h0.py`](scripts/summarise_h0.py) in an htc job.

## Results

### Objective-match tolerances

The benchmark ran all 27 models with lme4 and glmmTMB in R and with six Python engine configurations, with no errors or timeouts ([`results/bench_engine_summary_h0.md`](results/bench_engine_summary_h0.md), [`results/bench_engines_earlier_vs_h0.csv`](results/bench_engines_earlier_vs_h0.csv)). The classes are those of `A/bench/compare.py`: an engine is at the optimum when its common-objective gap to the best fit is at most 1e-4 absolute or 1e-9 relative, near when the gap is at most 1e-2, and worse otherwise.

- **lme4, in R and through rpy2.** At the optimum on all 27 models, with the largest gap 9.0e-7 (3.5e-5 with lme4 1.1-35.1). The rpy2 fits differ from the R fits by at most 5.5e-5 standard errors in the fixed effects (2.2e-8 earlier).
- **mixedlm.** At the optimum on all 27 models, with the largest gap 6.0e-11.
- **glmm.** At the optimum on 26 of 27 models, against 27 of 27 before. With glmm 0.9.3 its weighted REML fit is now 0.08 worse in the common objective, and its reported objective moved by 0.10.
- **glmmTMB.** At the optimum on 20 of 25 models, against 21 of 25 before. Its crossed ML fit now reaches the optimum, but its crossed REML fits with and without correlations fall 17.4 and 15.8 short, with a Hessian that is not positive definite in the first ([`results/bench_class_changes.csv`](results/bench_class_changes.csv)). The jq REML and weighted fits stay worse, as before.
- **statsmodels and gpboost.** Unchanged in class: statsmodels at the optimum on 13 of 19 models it supports, and gpboost on 4 (6 with Cholesky inversion) of 9.

The absolute tolerance of 1e-4 therefore separates the engines at the optimum from the rest with a margin of more than a hundredfold for lme4, glmmTMB, mixedlm and glmm. gpboost's largest gap at the optimum, 7.0e-5, sits just inside it.

### Registered offsets

An engine's offset is its reported objective minus the common reference objective at its own estimates ([`results/bench_offsets_earlier_vs_h0.csv`](results/bench_offsets_earlier_vs_h0.csv)). The offsets that lme4 1.1-35.1 showed under adaptive quadrature have gone with lme4 2.1-0: −83.96 for cbpp with 25 quadrature points and −1,680.82 for the Owls Poisson model are now zero to within 1e-10, in R and through rpy2. This agrees with the change to the normalising constants for nAGQ > 1 that lme4 2.1-0's NEWS records. The Laplace offset on the crossed binary design fell from 1.6e-3 to 4.3e-8, consistent with the PIRLS weight refresh of the same release. Every other offset changed by less than 1e-3, apart from glmm's weighted REML fit (above). Offsets registered for lme4 below 2.1-0 do not carry over to 2.1-0 and later.

### Memory classes

Peak memory stayed far below the 2 GB per core of the draft template. The V1 pilot tasks peaked at 0.16 to 0.19 GB, the benchmark's engine processes at most 0.56 GB (rpy2 with lme4) and 0.53 GB (statsmodels) on up to 12,000 rows ([`results/bench_engine_memory_by_engine.csv`](results/bench_engine_memory_by_engine.csv)), and the re-time with four concurrent fits 0.67 GB. One core and 2 GB per task is therefore enough for Gaussian studies of V1's size. The 1.6 to 1.7 GB that statsmodels needed on 40,000 rows (01-design-review.md) was not retested, so the conformance study's larger memory class still rests on that earlier run.

### Speed multiplier

The V1 pilot reproduced the earlier run's flag rates exactly in every cell, since the replicates use the same random-number streams and the fits agree. Its mean time per replicate was 1.64 to 1.79 times the earlier one ([`results/v1_pilot_earlier_vs_h0.csv`](results/v1_pilot_earlier_vs_h0.csv)). The re-time agrees: across the 126 groups of fits timed in both runs of `time_grid.R`, the median ratio is 1.73 ([`results/timing_raw_earlier_vs_h0.csv`](results/timing_raw_earlier_vs_h0.csv)); across the 28 harder designs of `time_grid2.R` it is 1.30 ([`results/timing_raw2_earlier_vs_h0.csv`](results/timing_raw2_earlier_vs_h0.csv)); and `lme4_timing.R` gives 1.70 to 1.75 for fits of 2,400 rows but 1.10 and 0.87 for fits of 12,000 rows ([`results/lme4_timing_earlier_vs_h0.csv`](results/lme4_timing_earlier_vs_h0.csv)). The speed multiplier against the cost model's assumption of 1.0 is therefore about 1.7 for small fits, falling towards 1 for large ones.

The ratio combines two changes that these runs cannot separate: ARC's Cascade Lake cores against the machine of the earlier runs, and lme4 2.1-0 against 1.1-35.1. pilot_V1a fits plain lme4 models without the suite, so the multiplier leaves out the suite's own overhead.

### Cost of H1

The H1 cost has not yet been re-estimated as the H0 gate requires (03-execution-plan.md, Milestones). That needs a timing of the stopping-rule walk on H1 cells, with a second optimiser and the suite's derivatives at every rung, and no script in the repository does it. Applying the multiplier above to the cost model would raise the central Phase 1 estimate of about 1,140 CPU-hours (02-decisions.md, Q9) by up to about 70%. The smaller ratios for large and harder designs suggest that the rise for H1's larger cells is smaller.

### Random-effects simulations

Pending: the rerun of Sim 1 to 6 is still running.

## Limits

- `cs()` was not tested: no script in `../decisions/B/sim` fits a `cs()` term, so one remains to be written.
- The speed multiplier leaves out the suite's overhead, and it mixes hardware with the engine version.
- The H1 stopping-rule walk with a second optimiser and suite derivatives was not timed, for want of a script.
- The re-time used the existing timing scripts (`F/timing/time_grid.R`, `time_grid2.R` and `A-verify/scripts/lme4_timing.R`) with their own time budgets, in place of a 20-fit subset, for which no script exists.
- The V1 pilot and the re-time ran on Cascade Lake nodes and the simulations on a Genoa node, since the wrappers set no CPU constraint (03-execution-plan.md, M6).
