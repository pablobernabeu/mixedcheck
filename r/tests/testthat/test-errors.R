# The error catalogue and the rendering of messages (docs/spec/errors.md).

test_that("every code of the catalogue renders with arguments of each kind", {
  catalogue <- mixedcheck:::error_catalogue()
  expect_gt(length(catalogue), 100L)
  sample_values <- list(
    text = "x", integer = 3L, number = 0.5, codepoint = 0x1FL,
    values = list("a", 1, TRUE, NULL), words = c("a", "b")
  )
  for (entry in catalogue) {
    args <- lapply(entry$args, function(kind) sample_values[[kind]])
    location <- switch(entry$location, none = list(), offset = list(offset = 0L),
                       pointer = list(pointer = "/a"),
                       offset_or_pointer = list(pointer = ""))
    issue <- do.call(mixedcheck:::new_issue, c(list(entry$code, args), location))
    expect_false(grepl("{", issue$message, fixed = TRUE), label = entry$code)
    expect_identical(issue$code, entry$code)
  }
})

test_that("messages are rendered as errors.md describes", {
  new_issue <- mixedcheck:::new_issue
  key <- paste0("go", intToUtf8(9L), "al")
  expect_identical(new_issue("E1029", list(key = key), offset = 45L)$message,
                   "Duplicate key 'go\\u0009al' at byte 45.")
  expect_identical(
    new_issue("E1405", list(allowed = list("occasion", "timestamp", "trial_index",
                                           "duration_since_start")),
              pointer = "/observation/time/kind")$message,
    "The value at /observation/time/kind must be 'occasion', 'timestamp', 'trial_index' or 'duration_since_start'."
  )
  expect_identical(new_issue("E1101", pointer = "")$message,
                   "A null at (root) is not allowed in the hashable profile.")
  expect_identical(new_issue("E1024", list(codepoint = 9L), offset = 2L)$message,
                   "Unescaped control character U+0009 in a string at byte 2.")
  expect_error(new_issue("E1029", list(key = "a")), "wrong location")
  expect_error(new_issue("E0000"), "unknown error code")
})

test_that("text is escaped for display and truncated to 60 code points", {
  display_text <- mixedcheck:::display_text
  expect_identical(display_text(c(0L, 0x7FL, 0x9FL, 0xA0L, 0x2028L, 0x2029L)),
                   paste0("\\u0000\\u007F\\u009F", intToUtf8(0xA0L), "\\u2028\\u2029"))
  expect_identical(display_text(strrep("a", 60L)), strrep("a", 60L))
  expect_identical(display_text(strrep("a", 61L)), paste0(strrep("a", 57L), "..."))
  # An escape counts as six code points and can be cut.
  expect_identical(display_text(paste0(strrep("a", 55L), intToUtf8(1L), "bbbb")),
                   paste0(strrep("a", 55L), "\\u...", ""))
  expect_identical(display_text(intToUtf8(rep(0xE9L, 70L))),
                   paste0(intToUtf8(rep(0xE9L, 57L)), "..."))
  expect_identical(display_text("/a/b", limit = NA), "/a/b")
})

test_that("conditions join the messages of several issues", {
  issues <- list(mixedcheck:::new_issue("E1001"), mixedcheck:::new_issue("E1002"))
  condition <- tryCatch(mixedcheck:::signal_issues(issues), error = function(e) e)
  expect_s3_class(condition, "mixedcheck_error")
  expect_identical(conditionMessage(condition),
                   "The file does not exist.\nThe file cannot be read.")
  expect_identical(condition$issues, issues)
})
