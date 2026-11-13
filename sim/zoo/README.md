# Generators of the pathology zoo

This directory holds the seeded generators of the pathology zoo ([fixtures/zoo/](../../fixtures/zoo/README.md)), the helpers they share and the script that writes or checks every stored instance (02-decisions.md, Q8, and 03-execution-plan.md, M2). The validation studies of M6 reuse the generators as their data-generating mechanisms on the HPC, and the families of the disclosure-attack harness call them with varied parameters. Everything here is base R, calls neither mixedcheck package and gives the same bytes under any locale, apart from the last digits of the reals of expected.json that the helpers compute, which depend on the long double and the BLAS of the R that runs them (Regeneration). Nothing in it ships with either package.

| Path | Content |
|---|---|
| regenerate.R | writes every directory of fixtures/zoo/ and index.json, or checks them |
| R/zoo.R | the shared helpers: the registry of definitions, the pinned random number generator, the checks of drawn properties, the builders of expected findings, the standard expectations, computations of statistics from their definitions in the registry, the order of findings and the writers |
| R/Z01.R … R/Z31.R | one file for each fixture, which defines its generator and registers the fixture and its matched negative. Z09.R and Z31.R call the generators of Z08 and Z03 and register one definition each |

R/Z01.R is the worked example that every other generator file follows.

## Regeneration

From the repository root:

```bash
Rscript sim/zoo/regenerate.R                   # write every directory of fixtures/zoo/ and index.json
Rscript sim/zoo/regenerate.R --only Z01,Z01N   # write these directories and index.json
Rscript sim/zoo/regenerate.R --check           # change nothing, compare, exit 1 on any difference
```

The script sources R/zoo.R and then R/Z*.R in code-point order. For each definition it calls the generator with its stored parameters, prints the number of redraws, writes data.csv, declaration.json, formula.txt and expected.json, and writes index.json from every definition present, --only included, so that a merge that conflicts in index.json is resolved by running the script again. --check writes everything into a temporary directory and compares it with fixtures/zoo/, every file byte for byte apart from the reals of expected.json, which it compares within a relative tolerance of 1e-10. It prints one line for each file that differs, with its first differing byte or, for expected.json, the first value that differs, each file it would write that is missing, each file or directory of fixtures/zoo/ other than README.md that no generator writes, and each generator that stops, and it exits with status 1 when it prints any. With --only, it compares the directories named and index.json. Without --check, a generator that stops makes the script write nothing, so that index.json keeps every entry, and any argument other than --check and --only with its list stops the script, so that a mistyped --check cannot rewrite the zoo. Both modes also check the limits on sizes, the reference values of zoo_gram() and the known answers of the helpers. The limits keep the installed packages small: at most 16 KB for one data.csv, 250 KB for all of them, 24 KB for one expected.json and 2.2 MB for fixtures/zoo/ on disk, measured as du measures it, with each file rounded up to a multiple of 4096 bytes and 4096 bytes for each directory. spec/tools/test_zoo.py checks the same limits. Some reals of expected.json, such as the smallest eigenvalue of zoo_gram() and the sums of zoo_anova() and zoo_sd(), come from sums that R accumulates in long double, whose precision depends on the platform, and from matrix products whose last bits depend on the BLAS, so that an R on arm64 macOS, or with OpenBLAS or R's own products, computes them differently in the last few digits. The writers round the reals of expected.json to 12 significant digits, which lie well within the tolerance of conventions.md (Comparison across languages), and the tolerance of --check covers a value that falls on the other side of a boundary of the 12th digit. The CI workflow zoo.yaml runs `--check` under LC_ALL=C.UTF-8 and under LC_ALL=C, which must give the same bytes, and with `options(matprod = "internal")`, R's own matrix products in place of the BLAS, and checks that the script refuses an option that it does not know.

After a regeneration, `python3 spec/tools/vendor.py sync` copies the files into both packages, and `python3 -m unittest discover -s spec/tools` checks them against the schema and the compiled registry.

## Generators

A generator is a function `zoo_Zn(p, checks = "redraw", seed)` of a named list of parameters, which returns the data as a data frame whose number columns already lie on the stored grid. Each value is rounded to the digits of its column, floor(x × 10^d + 0.5) / 10^d, before any property is checked, so that the generator, its checks and the expected function see the values that the packages read. A parameter digits of NA keeps full precision, for the studies of M6. The generator pins the random number generator with `zoo_with_rng()`, which sets `RNGkind("Mersenne-Twister", "Inversion", "Rejection")` and `set.seed(seed)` and restores the caller's kind and state on exit, so that a study can call it inside its own streams. The seed of Zn is 202611000 + 10 × n, and a negative shares the seed of its fixture, so that the draws of a negative with the same structure coincide with those of its fixture. Z09 uses the seed of Z08 and Z31 that of Z03.

The parameters fix sizes, labels, which units move, which rows repeat, which values are missing and every count that an expectation reads. Random draws give the outcome, the continuous covariates and, where a fixture says so, an arrangement of labels that no expected count or value depends on. Each generator file lists its draws in their order: arrangements first, then random effects in label order, then covariates and residuals in row order.

A property that an expectation reads is either structural, true by construction whatever the draws, or drawn, true with high probability, such as distinct covariate values within a family. `zoo_check()` checks the drawn properties on the stored values. The argument checks takes three values:

| checks | Behaviour | Used by |
|---|---|---|
| 'redraw' | a unit that fails a property is drawn again from the continuing stream, unit by unit in label order, until every property holds. A unit that still fails after 100 redraws stops the generator with an error that names the property and the unit | the stored instances and the families of the harness |
| 'flag' | nothing is drawn again, and the attribute zoo_failed of the data names each failing property and unit | the studies of M6, which need the unconditional draws |
| 'none' | the data are returned as drawn | |

The redraws are part of the seeded stream, so every stored instance stays reproducible. regenerate.R prints the number of redraws of each instance, and a builder reads it before writing the expected function.

## Definitions and expectations

A generator file registers each directory with `zoo_define()`: the identifier, name, title, role, matched directory and negative_of, domain, catalogue items, the planted problem, the seed and parameters, the generator, functions that return the declaration and the formula, the run, the expected function, the signal and, where they apply, planned checks, a deferred block and the CSV options (line endings, digits and the text of missing values by column).

The expected function `expected(p, data)` returns the samples and findings, or the issue that refuses the run, from the parameters alone. It reads the data only to count outcome values that random draws fix and to compute, with the helpers below, the reals that draws of a covariate fix. It calls neither package. Every expected value carries a derivation of one or two sentences in its why, and the full derivation lives in comments beside the code that computes it.

The helpers of R/zoo.R build the expectations:

| Helper | Builds |
|---|---|
| zv(), zr(), zi(), za(), zn() | a statistic with a value, a ratio of two counts, an interval given as two decimal strings, an absent statistic and a list of names, always an array |
| zoo_access(), zoo_planned() | the run of a directory, with the reason 'Pathology zoo fixture Zn.' at T1 and T2 and exploratory true at T2, and one planned check |
| zoo_finding(), zoo_not_available(), zoo_signal() | a finding, a finding that is not available and one element of a signal |
| zoo_na3(), zoo_rd(), zoo_sr(), zoo_kd(), zoo_lu(), zoo_cs(), zoo_gr(), zoo_db(), zoo_ld1(), zoo_rc1() | the expectations that recur across fixtures, such as design.rank_deficiency with full rank, from design quantities given as arguments, never from the data |
| zoo_gram(), zoo_anova(), zoo_gvif(), zoo_sd(), zoo_condition() | the smallest eigenvalue of identifiability.gram_rank, icc and within_share of structure.within_between, the GVIF of design.collinearity, a standard deviation and the condition number of design.scale_disparity, each computed from its definition in the registry |
| zoo_count_class(), zoo_sample() | the class to which a by_unit count resolves and the support of the findings on one sample |
| zoo_order() | the order of findings of documents.md (Findings) |

zoo_gram_reference holds the values of smallest_eigenvalue that the design states to seven significant digits, and regenerate.R fails when the value that a definition writes differs from its reference by more than 5e-8, so that a change to zoo_gram() that would move an expectation shows as a failure rather than as a regenerated file.

The writers format no string with sprintf(), format(), formatC(), encodeString(), print() or cat(), which escape non-ASCII characters under the C locale. Strings are built from code points with intToUtf8(), records are joined with paste0() and written as bytes with writeBin(), and numbers are written by the integer arithmetic above, the reals of expected.json with 12 significant digits and those of the declarations with the 17 that give back the double.
