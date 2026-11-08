# The JSON corpus: the strict reader in each mode and the serialiser, with
# the examples of RFC 8785 (fixtures/conformance/json/README.md).

for (file in c("rfc8785.json", "syntax.json", "values.json", "canonical.json", "writer.json")) {
  test_that(paste("every case of json", file, "passes"), {
    cases <- corpus_cases("json", file)
    expect_gt(length(cases), 0L)
    run_json_cases(cases)
  })
}
