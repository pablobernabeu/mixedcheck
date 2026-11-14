# The check of the prefix labels (spec/registry/checks/labels.unicode_forms.yaml).

# labels.unicode_forms: for each column that holds labels, the distinct
# strings of the table that share their NFC form with another distinct
# string, and the NFC forms they share. A string that is not normalisable
# stands for itself.
audit_check_labels_unicode_forms <- function(run, entry, elements) {
  labelled <- label_columns(run)
  lapply(elements, function(element) {
    key <- element$column
    if (!key %in% labelled) {
      return(NULL)
    }
    j <- column_index(run, key)
    values <- run$table$values[[j]]
    spellings <- 0
    labels <- 0
    if (is.character(values)) {
      distinct <- unique(values[!run$table$missing[[j]]])
      forms <- comparison_form(distinct)
      shared <- forms %in% forms[duplicated(forms)]
      spellings <- sum(shared)
      labels <- length(unique(forms[shared]))
    }
    check_element(list(spellings = spellings, labels = labels), rules = spellings > 0)
  })
}

# The keys of the columns that hold labels (applies_when of
# labels.unicode_forms): the grouping columns, the categorical predictors of
# the IR, the columns of the observation key, the columns of the entries of
# the assignment block and the columns that the declaration gives the role
# assigned, without the outcome columns, which the check does not read.
label_columns <- function(run) {
  declaration <- run$declaration
  ir <- run$ir
  categorical <- names(Filter(function(p) p$kind == "categorical", ir$predictors))
  assigned <- vapply(assignment_elements(declaration), function(element) element$column, "")
  roles <- role_columns(declaration, "assigned")
  found <- c(run$grouping_columns, categorical,
             comparison_form(as.character(c(observation_key_columns(declaration), assigned, roles))))
  outcome <- c(ir$response$variable, ir$response$trials,
               declared_role_columns(declaration, c("outcome", "outcome_derived")))
  setdiff(unique(found), outcome)
}
