# Z09 Treatment mixed within a declared unit: the data of Z08 with the arm of
# the first pupil, in table order, of classes C01 and C16 switched (C16 is
# the fourth class of S3). Its matched negative is Z08 (Z08.R), whose
# declaration, formula and expected function it shares. The generator is
# zoo_Z08() with contaminated [1, 16] and the seed of Z08, so the data differ
# from those of Z08 in these two pupils' arms and outcomes alone.

zoo_Z09 <- function(p, checks = "redraw", seed) {
  stopifnot(length(p$contaminated) > 0)
  zoo_Z08(p, checks, seed)
}

zoo_define(
  id = "Z09", name = "mixed-assignment", title = "Treatment mixed within a declared unit",
  role = "fixture", matched = "Z08", negative_of = character(0), domain = "education",
  catalogue = "L7-03",
  planted = paste("Classes were randomised within schools, and the first pupil of classes C01",
                  "and C16 is recorded in the other arm, so arm varies within two classes."),
  seed = 202611080, parameters = zoo_Z08_parameters(c(1, 16)), generate = zoo_Z09,
  declaration = function(p) zoo_Z08_declaration(p, "Z09 Treatment mixed within a declared unit"),
  formula = function(p) "y ~ arm + (1 | school)",
  run = zoo_access("Z09", "T0"), expected = function(p, data) zoo_Z08_expected(p, data),
  signal = list(zoo_signal("assignment.constant_within_unit",
                           list(column = "arm", unit = "class"), "mixed"))
)
