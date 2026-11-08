# mixedcheck (R)

The R package of mixedcheck, which audits study designs before mixed-effects
models are fitted and diagnoses and reports fitted models. It shares the
registry of checks, the schemas and the test fixtures with the Python package
of the same name. Each component is built in R first.

The package is in development and has not been released. So far it provides
`spec_versions()`, which returns the versions of the shared specification
installed with the package.

``` r
library(mixedcheck)
spec_versions()
```

It needs R 4.2.0 or later. To install it from a clone of the repository:

``` sh
R CMD INSTALL r
```

The [repository](https://github.com/pablobernabeu/lmecheck) holds the design
documents and both packages. Changes are listed in
[NEWS.md](https://github.com/pablobernabeu/lmecheck/blob/main/r/NEWS.md). The
package is MIT-licensed.
