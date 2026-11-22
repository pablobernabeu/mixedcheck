# CRAN Repository Policy, live revision

**Page read.** CRAN Repository Maintainers, *CRAN Repository Policy*, https://cran.r-project.org/web/packages/policies.html, read in the browser on 21 November 2026. Version: $Revision: 6985 $ (the page served was last modified on 25 October 2026).

**Fact.**
- The revision is 6985, the one that evidence D/E records (reports.json, 'CRAN policy (rev. 6985)'), so the policy has not been revised since the evidence was gathered.
- Strong dependencies (Depends, Imports, LinkingTo) must be available from CRAN or Bioconductor. A package in Suggests or Enhances from any other repository must say where to obtain it, in an Additional_repositories field of DESCRIPTION (a comma-separated list of repository URLs) or in the Description field.
- A package in Suggests or Enhances should be used conditionally in examples and tests if it cannot be installed straightforwardly on the major platforms, and the policy notes that Writing R Extensions recommends conditional use always.
- Package names must not clash, irrespective of case, with any current or past CRAN package or any current Bioconductor package.
- Once a package is established, updates 'no more than every 1–2 months' seem appropriate; examples should each run for no more than a few seconds.

**Bearing on 03-execution-plan.md (Open checks; the fastglmm item of H0).** A CRAN release of the R package may list fastglmm, which is distributed through R-universe only, in Suggests, provided DESCRIPTION gives the R-universe repository in Additional_repositories and the package is used conditionally, as Q6 already requires of every Suggests package. The other statements that 02 and 03 take from the policy stand at revision 6985.
