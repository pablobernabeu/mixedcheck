# Attack (a), inference by consistency search (sim/disclosure/README.md).
# Every table of a family is audited in shareable mode, each document is
# reduced to what the adversary can use, and the tables whose reduced
# documents are identical form a group: the adversary who holds the document
# knows only that the table is one of its group. A hidden value that takes
# one value across a group, while the family lets it vary among the tables
# that hide it with the same detail, is determined by the document.

# The reals whose values depend on the values of predictors as well as on
# counts. A family whose predictors are not all two-valued, with the counts
# of each value among its parameters, would hand the adversary predictor
# values that no document gives, so the reductions of its documents mask
# these reals and the numbers with a decimal point that messages render.
dh_predictor_reals <- c(
  "design.collinearity" = "gvif", "design.collinearity" = "gvif_per_df",
  "design.scale_disparity" = "condition_number", "design.scale_disparity" = "sd_largest",
  "design.scale_disparity" = "sd_ratio", "design.scale_disparity" = "sd_smallest",
  "identifiability.gram_rank" = "smallest_eigenvalue",
  "structure.within_between" = "within_share", "structure.within_between" = "icc",
  "outcome.separation" = "margin", "outcome.separation" = "optimum",
  "outcome.separation" = "bounds"
)

dh_mask_reals <- function(document) {
  document$findings <- lapply(document$findings, function(finding) {
    masked <- dh_predictor_reals[names(dh_predictor_reals) == finding$check]
    for (name in intersect(names(finding$statistics), masked)) {
      if (!is.null(finding$statistics[[name]]$value)) {
        finding$statistics[[name]]$value <- "masked"
      }
    }
    if (!is.null(finding$message$text) && length(masked)) {
      finding$message$text <- gsub("[0-9]+\\.[0-9]+", "#", finding$message$text)
    }
    finding
  })
  document
}

# The number of the n values behind a quantile that equal its value, for the
# quantiles of registry 0.1.0: the level sizes of structure.cluster_sizes
# and the minority counts by level of outcome.minority_events. privacy.md
# (Guarantees) accepts a quantile that k or more of its n values share.
dh_quantile_shared <- function(ns, result, finding) {
  run <- result$run
  factor <- finding$scope$factor
  if (is.null(factor)) {
    return(NA_integer_)
  }
  codes <- ns$value_codes(run, ns$factor_keys(run, factor))
  if (finding$check == "structure.cluster_sizes") {
    sizes <- tabulate(codes[run$design])
    return(sizes[sizes > 0L])
  }
  if (finding$check == "outcome.minority_events") {
    level <- codes[run$analysis]
    trials <- run$trials %||% rep(1, length(level))
    present <- !is.na(level)
    events <- tapply(run$response[present], level[present], sum)
    totals <- tapply(trials[present], level[present], sum)
    return(as.numeric(pmin(events, totals - events)))
  }
  NA_integer_
}

# Whether no member of the disclosure unit lies in two levels of an item in
# the table, as a function of the item's name in the interval audit, whose
# parts joined by ':' are columns, declared units or the terms of a scope,
# which are left out. Each level of an item whose counts resolve as
# non-person then holds two contributors or more, which bounds the
# contributors by twice the levels (iv_firing_bounds()). Members of crossed
# subjects and items lie in several levels of the items, and the bound does
# not hold.
dh_members_within <- function(case, run) {
  members <- run$disclosure$codes
  if (is.null(members)) {
    return(NULL)
  }
  units <- case$args$declaration$units
  function(item) {
    parts <- strsplit(item, ":", fixed = TRUE)[[1L]]
    columns <- unlist(lapply(parts, function(part) {
      if (part %in% names(case$data)) {
        return(part)
      }
      unit <- Find(function(u) identical(u$name, part), units)
      if (is.null(unit)) NULL else unlist(unit$columns)
    }))
    if (!length(columns) || !all(columns %in% names(case$data))) {
      return(FALSE)
    }
    levels <- do.call(paste, c(lapply(case$data[unique(columns)], as.character), sep = "\r"))
    keep <- !is.na(members)
    all(tapply(levels[keep], members[keep], function(x) length(unique(x)) == 1L))
  }
}

# The disclosure unit that the document names, as the interval audit models
# it (iv_unit_relations()): the grouping factor whose columns are the
# columns that the declaration gives the unit, or NULL, and whether the
# observation key consists of those columns. NULL when the document names no
# unit or the declaration does not declare it.
dh_unit_shape <- function(case, document, shape) {
  name <- document$privacy$disclosure_unit$name
  declaration <- case$args$declaration
  if (is.null(name) || is.null(declaration)) {
    return(NULL)
  }
  unit <- Find(function(u) identical(u$name, name), declaration$units)
  if (is.null(unit)) {
    return(NULL)
  }
  columns <- unlist(unit$columns)
  key <- unlist(declaration$observation$key)
  list(factor = iv_shape_item(shape, columns),
       key = length(key) > 0L && setequal(key, columns) && length(key) == length(columns))
}

# Audits every table of a family at the family's k and returns the grid
# with, for each table, the two reductions of its document, its hidden
# values and the issues of validation.
dh_run_family <- function(ns, family, grid = dh_grid(family), cores = 1L, intervals = FALSE) {
  old <- dh_set_k(ns, family$k)
  on.exit(dh_set_k(ns, old), add = TRUE)
  reals <- isTRUE(family$reals)
  # The interval audit runs once for each document that a worker has not yet
  # audited.
  audited <- new.env(parent = emptyenv())
  one <- function(i) tryCatch(one_table(i), error = function(e) list(error = conditionMessage(e)))
  one_table <- function(i) {
    case <- family$build(as.list(grid[i, , drop = FALSE]))
    design <- dh_design_key(case)
    result <- dh_run(ns, case)
    if (!is.null(result$error)) {
      return(c(result[c("error", "empty")], list(design = design)))
    }
    document <- if (reals) result$document else dh_mask_reals(result$document)
    targets <- dh_targets(result)
    # Every hidden value has a tier (privacy.md, Tiers), or the harness
    # cannot gate it.
    unclassified <- unique(paste(targets$finding, "|", targets$member)[is.na(targets$tier)])
    if (length(unclassified)) {
      return(list(error = paste("hidden values without a tier:",
                                paste(unclassified, collapse = "; ")), design = design))
    }
    targets$shared <- NA_real_
    quantiles <- which(targets$member %in% c("smallest", "lower_quartile", "median",
                                             "upper_quartile", "largest", "median_minority"))
    for (j in quantiles) {
      finding <- Find(function(f) isTRUE(f$available) && dh_finding_id(f) == targets$finding[j],
                      result$findings)
      values <- dh_quantile_shared(ns, result, finding)
      value <- suppressWarnings(as.numeric(targets$value[j]))
      targets$shared[j] <- if (is.na(value)) NA_real_ else sum(values == value)
    }
    full <- dh_reduce(document)
    lp <- NULL
    if (intervals && is.null(audited[[full]])) {
      assign(full, TRUE, envir = audited)
      shared <- stats::setNames(as.list(targets$shared), paste0(targets$finding, " | ",
                                                               targets$member))
      shape <- iv_shape(result$run$ir)
      shape$within <- dh_members_within(case, result$run)
      shape$unit <- dh_unit_shape(case, result$document, shape)
      lp <- iv_audit(result$document, dh_capture$entries, iv_internal(result), shared, shape)
    }
    list(full = full, strict = dh_reduce(document, strict = TRUE),
         targets = targets, issues = result$issues, lp = lp, design = design)
  }
  runs <- if (cores > 1L) {
    parallel::mclapply(seq_len(nrow(grid)), one, mc.cores = cores, mc.preschedule = TRUE)
  } else {
    lapply(seq_len(nrow(grid)), one)
  }
  list(family = family, grid = grid, runs = runs)
}

# The determinations of a run of a family. Returns a data frame with one row
# for each hidden value or person-count parameter that a group of interior
# tables determines, with the mode of the reduction, the target, its value,
# the size of the group, its first table and its tier (dh_tier()), and the
# verdict: 'leak' when the strict reduction determines an outcome-derived
# value, 'residual' when it determines a design-structure value, 'accepted'
# when only the full reduction determines it, or when the value is a
# quantile shared by k or more values or a count derived through
# suppress_with from written statistics.
dh_determinations <- function(ran, k = ran$family$k) {
  family <- ran$family
  grid <- ran$grid
  runs <- ran$runs
  failed <- vapply(runs, function(r) !is.list(r) || !is.null(r$error), NA)
  interior <- dh_interior(family, grid) & !failed
  targets <- do.call(rbind, lapply(which(!failed), function(i) {
    t <- runs[[i]]$targets
    if (!nrow(t)) {
      return(NULL)
    }
    t$table <- i
    t
  }))
  if (is.null(targets)) {
    targets <- data.frame(table = integer(0), finding = character(0), member = character(0),
                          detail = character(0), value = character(0), kind = character(0),
                          class = character(0), shared = numeric(0), derived = logical(0),
                          tier = character(0), stringsAsFactors = FALSE)
  }
  # Determinations of reals and names are left to the counts that they
  # derive from, which the families vary.
  targets <- targets[!targets$kind %in% c("real", "reals", "names"), , drop = FALSE]
  # A family probes the hidden values whose counts it varies independently.
  targets <- targets[grepl(family$probe, paste(targets$finding, "|", targets$member)), ,
                     drop = FALSE]
  targets$key <- paste(targets$finding, targets$member, targets$detail, sep = " | ")
  variation <- tapply(targets$value, targets$key, function(v) length(unique(v)))
  persons <- names(family$params)[vapply(family$params, function(p) p$person, NA)]
  found <- list()
  for (mode in c("strict", "full")) {
    keys <- vapply(runs, function(r) if (is.list(r) && is.null(r$error)) r[[mode]] else NA_character_,
                   "")
    groups <- split(seq_along(keys), keys)
    for (group in groups) {
      inside <- group[interior[group]]
      if (!length(inside)) {
        next
      }
      mine <- targets[targets$table %in% group, , drop = FALSE]
      common <- names(which(table(mine$key) == length(group)))
      for (key in common) {
        values <- unique(mine$value[mine$key == key])
        if (length(values) == 1L && variation[[key]] > 1L) {
          row <- mine[mine$key == key, , drop = FALSE][1L, ]
          found[[length(found) + 1L]] <- data.frame(
            mode = mode, target = key, value = values, class = row$class,
            shared = row$shared, derived = any(mine$derived[mine$key == key]),
            group = length(group), table = inside[1L], tier = row$tier, stringsAsFactors = FALSE)
        }
      }
      for (p in persons) {
        values <- unique(grid[[p]][group])
        below <- unique(grid[[p]][!failed & grid[[p]] < k])
        if (length(values) == 1L && values < k && length(below) > 1L) {
          found[[length(found) + 1L]] <- data.frame(
            mode = mode, target = paste("parameter", p), value = as.character(values),
            class = "person", shared = NA_real_, derived = FALSE, group = length(group),
            table = inside[1L], tier = dh_tier(paste("parameter", p), family),
            stringsAsFactors = FALSE)
        }
      }
    }
  }
  if (!length(found)) {
    return(data.frame(mode = character(0), target = character(0), value = character(0),
                      class = character(0), shared = numeric(0), derived = logical(0),
                      group = integer(0), table = integer(0), tier = character(0),
                      verdict = character(0), stringsAsFactors = FALSE))
  }
  found <- do.call(rbind, found)
  strict <- paste(found$table, found$target)[found$mode == "strict"]
  found$verdict <- ifelse(found$mode == "strict", "leak", "accepted")
  found <- found[found$mode == "strict" | !paste(found$table, found$target) %in% strict, ,
                 drop = FALSE]
  # A quantile shared by k or more of its values, and a count derived from a
  # written statistic through suppress_with, are accepted (privacy.md,
  # Guarantees).
  shared <- !is.na(found$shared) & found$shared >= k
  found$verdict[shared | found$derived] <- "accepted"
  # A design-structure value is protected against the linear relations of
  # the document alone, which attack (b) models. The search cannot tell a
  # linear determination from another, so its determinations of
  # design-structure values are residual risk (privacy.md, Guarantees,
  # Residual risk), reported without failing the run.
  found$verdict[found$verdict == "leak" & found$tier == "B"] <- "residual"
  found
}

# The search on one family: every table of the family, and, when that finds
# a determination, the tables of the family widened by widen values beyond
# every end of a range that is not a natural bound. The widened tables can
# join a group and so remove a determination that only the limits of the
# family made, and they are never reported themselves, so a determination
# that remains does not rest on those limits.
dh_search <- function(ns, family, cores = 1L, widen = 1L, intervals = FALSE) {
  base <- dh_grid(family)
  ran <- dh_run_family(ns, family, base, cores = cores, intervals = intervals)
  found <- dh_determinations(ran)
  if (!any(found$verdict == "leak") || widen < 1L) {
    return(list(ran = ran, found = found, widened = 0L))
  }
  wide <- dh_grid(family, widen = widen)
  key <- function(grid) do.call(paste, c(unname(as.list(grid)), sep = ","))
  extra <- wide[!key(wide) %in% key(base), , drop = FALSE]
  # Only the widened tables next to a group that makes a leak can join it.
  strict <- vapply(ran$runs, function(r) if (is.list(r) && is.null(r$error)) r$strict else
    NA_character_, "")
  groups <- which(strict %in% strict[found$table[found$verdict == "leak"]])
  near <- vapply(seq_len(nrow(extra)), function(i) {
    distance <- apply(abs(sweep(as.matrix(base[groups, , drop = FALSE]), 2L,
                                unlist(extra[i, , drop = FALSE]))), 1L, max)
    any(distance <= widen)
  }, NA)
  extra <- extra[near, , drop = FALSE]
  more <- dh_run_family(ns, family, extra, cores = cores)
  ran <- list(family = family, grid = rbind(base, extra), runs = c(ran$runs, more$runs))
  list(ran = ran, found = dh_determinations(ran), widened = nrow(extra))
}
