# Fox and Monette (1992)

**Reference as checked.** Fox, J., & Monette, G. (1992). Generalized collinearity diagnostics. *Journal of the American Statistical Association, 87*(417), 178–183. https://doi.org/10.1080/01621459.1992.10475190

**Match.** Crossref (queried 21 November 2026) and JSTOR (stable 2290467) agree on authors, title, journal, volume 87, issue 417, pages 178–183 and DOI. Not retracted or corrected.

**Platform and pages read.** JSTOR, page images with their text layer, through Oxford's subscription, read 21 November 2026: all six pages, with the abstract (p. 178), the invariance results (p. 179) and the definition of the generalised variance-inflation factor (p. 180) read closely. Oxford's access through Taylor & Francis does not cover this volume.

## Claims checked

1. spec/registry/checks/design.collinearity.yaml (source of threshold moderate, and its derivation): Fox and Monette (1992) define the generalised variance-inflation factor (GVIF) and the dimension-adjusted GVIF^(1/(2 df)), which car's documentation describes as comparable across terms of different dimension; for a term with one column the GVIF reduces to the VIF.
   **Supported, and the paper itself makes the comparability point.** The paper generalises variance inflation to a subset of coefficients, such as the dummy regressors of a factor or the polynomial terms of a variable, through the size of their joint confidence ellipsoid (abstract, p. 178), and gives the GVIF as a ratio of determinants of correlation matrices (p. 180). To keep subspaces of different dimension comparable it recommends examining GVIF^(1/(2p)), the geometric mean of the eigenvalue ratios, in place of the GVIF, and notes that for a single coefficient the GVIF is the usual VIF (p. 180). The registry need not lean on car's documentation for this.
2. review-catalogue.md (L2 entry on collinearity): the GVIF of a whole term does not change with the coding of the factor. **Supported.** The eigenvalues behind the GVIF are invariant under nonsingular linear transformations of the variables within the subset and of the unalterable columns (p. 179), and the determinant index for several sets is invariant to changes of basis within each set (p. 180).
3. The thresholds of 5 and 10 come from James et al. (2013), not from this paper; their extension to GVIF^(1/df) is, as the registry says, the project's own.

## Fields that differ from the repository's records

None.

## Questions for a person

None.
