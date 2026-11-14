# The declaration corpus: declarations written in JSON, read with the strict
# reader and checked in the five stages of the validator
# (fixtures/conformance/declarations/README.md).

for (file in c("valid.json", "reading.json", "version.json", "structure.json",
               "references.json", "meaning.json", "precedence.json")) {
  test_that(paste("every case of declarations", file, "passes"), {
    run_declaration_cases("declarations", file)
  })
}
