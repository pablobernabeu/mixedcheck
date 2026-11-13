# Z31 Teacher labels reused in each school, the attribute-consistency fixture
# that joins the zoo beside the thirty of Q8. Each school numbers its own
# three teachers T1 to T3, so the labels denote 30 teachers, the relation of
# school and teacher is undeclared and the formula uses teacher alone, which
# merges the teachers that share a label. teacher_years differs between the
# teachers that share a label, so that structure.id_scope_evidence reports
# probable reuse. Its matched negative is Z03N (Z03.R), whose data differ in
# teacher_years and the outcome alone. The generator is zoo_Z03() with
# attributes 'reused' and the seed of Z03, and the declaration, the formula
# and the expected findings are those of Z03.R.

# The data of zoo_Z03() with attributes 'reused': J K teacher effects, one
# for each teacher of each school, in school order.
zoo_Z31 <- function(p, checks = "redraw", seed) {
  stopifnot(identical(p$attributes, "reused"))
  zoo_Z03(p, checks, seed)
}

zoo_define(
  id = "Z31", name = "reused-teacher-labels", title = "Teacher labels reused in each school",
  role = "fixture", matched = "Z03N", negative_of = character(0), domain = "education",
  catalogue = c("L1-01", "L2-22"),
  planted = paste("Each school numbers its own three teachers T1 to T3, the relation of school",
                  "and teacher is undeclared, and teacher_years changes between the teachers",
                  "that share a label, while the formula uses teacher alone."),
  seed = 202611030, parameters = zoo_Z03_parameters("reused"), generate = zoo_Z31,
  declaration = function(p) zoo_Z03_declaration(p, "Z31 Teacher labels reused in each school"),
  formula = function(p) "y ~ 1 + (1 | school) + (1 | teacher)",
  run = zoo_access("Z31", "T0"), expected = zoo_Z03_expected,
  signal = list(zoo_signal("structure.id_scope_evidence",
                           list(first = "school", second = "teacher"), "reuse_likely"))
)
