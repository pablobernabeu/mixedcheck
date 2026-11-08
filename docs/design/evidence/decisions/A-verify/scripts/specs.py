"""Model specifications for the verification, transcribed from report A's r_reference.R formulas."""
M = {}
def add(mid, data, y, blocks, family="gaussian", reml=None, weights=None, offset=None, trials=None, nagq=1):
    M[mid] = dict(data=data, y=y, blocks=blocks, family=family, reml=reml, weights=weights,
                  offset=offset, trials=trials, nagq=nagq)

for reml, s in [(True, "REML"), (False, "ML")]:
    add(f"sleep_{s}", "sleep", "Reaction", [("Subject", ["1", "Days"])], reml=reml)
    add(f"pen_{s}", "penicillin", "diameter", [("plate", ["1"]), ("sample", ["1"])], reml=reml)
    add(f"pastes_{s}", "pastes", "strength", [("batch", ["1"]), ("sample", ["1"])], reml=reml)
    add(f"crossed_{s}", "crossed", "y", [("subj", ["1", "cond"]), ("item", ["1", "cond"])], reml=reml)
    add(f"crossed_zcp_{s}", "crossed", "y", [("subj", ["1"]), ("subj", ["cond"]), ("item", ["1"]), ("item", ["cond"])], reml=reml)
    add(f"school_{s}", "school", "y", [("school", ["1", "x"]), ("schoolclass", ["1"])], reml=reml)
    add(f"nearsing_{s}", "nearsing", "y", [("g", ["1", "t"])], reml=reml)
    add(f"weighted_{s}", "weighted", "y", [("g", ["1"])], reml=reml, weights="w")
add("sleep_zcp_ML", "sleep", "Reaction", [("Subject", ["1"]), ("Subject", ["Days"])], reml=False)
add("school_zcp_ML", "school", "y", [("school", ["1"]), ("school", ["x"]), ("schoolclass", ["1"])], reml=False)
add("nearsing_zcp_ML", "nearsing", "y", [("g", ["1"]), ("g", ["t"])], reml=False)
add("crossedbig_REML", "crossedbig", "y", [("subj", ["1", "cond"]), ("item", ["1", "cond"])], reml=True)
add("crossedbig_zcp_REML", "crossedbig", "y", [("subj", ["1"]), ("subj", ["cond"]), ("item", ["1"]), ("item", ["cond"])], reml=True)
add("cbpp_laplace", "cbpp", "incidence", [("herd", ["1"])], family="binomial", trials="size")
add("cbpp_agq25", "cbpp", "incidence", [("herd", ["1"])], family="binomial", trials="size", nagq=25)
add("owls_pois", "owls", "SiblingNegotiation", [("Nest", ["1"])], family="poisson", offset="logBroodSize")
add("owls_pois_agq25", "owls", "SiblingNegotiation", [("Nest", ["1"])], family="poisson", offset="logBroodSize", nagq=25)
add("binxd_laplace", "binxd", "y", [("subj", ["1", "cond"]), ("item", ["1"])], family="binomial", trials="n")
add("jq_REML", "jq", "y", [("g", ["1", "x1", "x2"])], reml=True)

FORMULA = {
    "sleep": "Reaction ~ Days + (Days | Subject)",
}
