# Shared specification

This directory is the source of the artefacts that the R and Python packages share. It will hold the schema bundle, the registry source in YAML and the compiled registry in JSON (Q7 in 02-decisions.md and M1 in 03-execution-plan.md).

- `versions.json` records the versions of the registry, the schemas and the canonicaliser as strings. Each package returns them through `spec_versions()`.
- `vendoring.json` lists every artefact to vendor, as a path from the repository root under spec/ or fixtures/.
- `tools/vendor.py` copies the listed artefacts into the packages and checks the copies. It uses the Python standard library only.

## Vendoring

Each artefact listed in `vendoring.json` is copied byte for byte from spec/ into r/inst/spec/ and python/src/mixedcheck/_spec/, and from fixtures/ into r/inst/fixtures/ and python/src/mixedcheck/_fixtures/. Each of these directories also holds a MANIFEST.json of the SHA-256 digests of its files, which the packages' tests compare with the installed files. Edit the sources here or in fixtures/, never the copies, and then run, from the repository root:

```bash
python3 spec/tools/vendor.py sync    # write the copies and the manifests
python3 spec/tools/vendor.py check   # change nothing, and exit with status 1 on any problem
python3 -m unittest discover -s spec/tools -v   # test the script
```

`check` names each problem: a copy that is missing, differs from its source or is a symbolic link, a listed source that is missing, a file in a vendored directory that is not listed, a missing or stale manifest, a listed name that R CMD build would leave out or R CMD check would reject and a carriage return or byte-order mark in any file under spec/. The files here are UTF-8 text with LF line endings and no byte-order mark. `.gitattributes` turns off Git's line-ending conversion for spec/, fixtures/ and the vendored directories, so that a checkout on any platform keeps the bytes that were hashed.
