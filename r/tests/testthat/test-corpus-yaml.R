# The YAML corpus: declarations written in YAML, read with every scalar as a
# string, converted to JSON and validated (fixtures/conformance/yaml/README.md).
# Reading YAML needs the suggested package yaml.

for (file in c("valid.json", "reading.json", "conversion.json", "validation.json",
               "precedence.json")) {
  test_that(paste("every case of yaml", file, "passes"), {
    skip_if_not_installed("yaml")
    run_declaration_cases("yaml", file)
  })
}
