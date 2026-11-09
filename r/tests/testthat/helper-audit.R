# Helpers for the tests that run audit(): the time that MIXEDCHECK_TIME
# fixes, a seed that is restored when a test ends and the sources of keys.

# Evaluates code with MIXEDCHECK_TIME set to a time, by default 0, and
# restores the variable afterwards.
with_audit_time <- function(code, time = "0") {
  old <- Sys.getenv("MIXEDCHECK_TIME", unset = NA)
  Sys.setenv(MIXEDCHECK_TIME = time)
  on.exit(if (is.na(old)) Sys.unsetenv("MIXEDCHECK_TIME") else
    Sys.setenv(MIXEDCHECK_TIME = old), add = TRUE)
  force(code)
}

# Sets the seed of R's random number generator for the rest of the calling
# frame and restores the generator's state, or its absence, when the frame
# ends, so that the tests leave .Random.seed as they found it. Handlers run
# in reverse order, so that a seed set in a loop restores the first state.
local_seed <- function(seed, envir = parent.frame()) {
  had <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  old <- if (had) get(".Random.seed", envir = globalenv())
  restore <- function() {
    if (had) {
      assign(".Random.seed", old, envir = globalenv())
    } else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
      rm(".Random.seed", envir = globalenv())
    }
  }
  do.call(on.exit, list(bquote(.(restore)()), add = TRUE, after = FALSE), envir = envir)
  set.seed(seed)
}

# Skips a test that creates a key when the platform has no secure source.
skip_without_key_source <- function() {
  skip_if(!file.exists("/dev/urandom") && !requireNamespace("openssl", quietly = TRUE),
          "neither /dev/urandom nor openssl is available")
}
