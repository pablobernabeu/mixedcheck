# The plan corpus: plans checked in the four stages of validate_plan()
# (fixtures/conformance/plans/README.md).

test_that("every case of plans validate.json passes", {
  cases <- corpus_cases("plans", "validate.json")
  expect_gt(length(cases), 0L)
  for (case in cases) {
    found <- capture_issues(function() validate_plan(corpus_directory("plans", case[["plan"]])))
    expected <- case[["expected"]][["issues"]]
    if (length(expected)) {
      expect_issues(found, expected, case$id)
    } else {
      expect_same(found$issues, NULL, label = case$id)
    }
  }
})
