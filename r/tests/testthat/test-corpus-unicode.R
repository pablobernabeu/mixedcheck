# The Unicode corpus: UTF-8 validation, normalisable strings, NFC, the order
# of identifiers and labels, the NFC rule of the hashable profile and the
# cases that a locale or an encoding mark could change
# (fixtures/conformance/unicode/README.md).

codepoints <- function(text) utf8ToInt(enc2utf8(text))

test_that("every case of unicode utf8.json, hashable.json and c_locale.json passes", {
  for (file in c("utf8.json", "hashable.json", "c_locale.json")) {
    run_json_cases(corpus_cases("unicode", file))
  }
})

test_that("every case of unicode normalisation.json passes", {
  for (case in corpus_cases("unicode", "normalisation.json")) {
    expect_same(mixedcheck:::is_normalisable(case[["string"]]), case[["expected"]][["normalisable"]],
                label = case$id)
    expect_same(codepoints(mixedcheck:::comparison_form(case[["string"]])),
                codepoints(case[["expected"]][["form"]]), label = case$id)
  }
})

test_that("every case of unicode order.json passes", {
  for (case in corpus_cases("unicode", "order.json")) {
    if (!is.null(case[["first"]])) {
      expect_same(mixedcheck:::compare_identifiers(case[["first"]], case[["second"]]),
                  as.integer(case[["expected"]][["order"]]), label = case$id)
    } else {
      sorted <- mixedcheck:::sort_identifiers(unlist(case[["strings"]]))
      expect_same(lapply(sorted, codepoints),
                  lapply(unlist(case[["expected"]][["sorted"]]), codepoints), label = case$id)
    }
  }
})
