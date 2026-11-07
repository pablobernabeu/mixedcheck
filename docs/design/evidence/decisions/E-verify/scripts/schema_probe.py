"""Adversarial probes of report E's draft design schema (design.schema.json).

1. Re-validate the report's 6 examples and 7 invalid files with jsonschema
   (Draft 2020-12) and with fastjsonschema (pure Python, no dependencies).
2. Probe loopholes the report's prose implies are closed:
   - confirmatory goal with empty estimands / empty variables / no outcome role
   - trial feature with an empty assignment list
   - 'x-inferred' markers inside a unit (decision 4 says draft_design() marks
     inferred entries with x-inferred)
   - misspelt unit names in nested_in / assignment.unit (referential integrity)
   - nested_in cycles
   - membership 'may_change_over_time' without observation.time
   - misspelt Frictionless property inside a table field (silently accepted?)
   - schema_version bump
Usage: python -I schema_probe.py <schema.json> <examples_dir> <invalid_dir> <out_tsv>
"""
import copy
import json
import os
import sys

import fastjsonschema
import jsonschema


def load(p):
    with open(p, encoding="utf-8") as fh:
        return json.load(fh)


def js_errors(validator, doc):
    errs = list(validator.iter_errors(doc))
    return [("/".join(map(str, e.absolute_path)) or "(root)") + ": " + e.message[:90] for e in errs]


def fjs_result(fvalidate, doc):
    try:
        fvalidate(doc)
        return "valid"
    except fastjsonschema.JsonSchemaException as e:
        return "invalid: " + str(e)[:90]


def main():
    schema_p, ex_dir, bad_dir, out = sys.argv[1:5]
    schema = load(schema_p)
    jsonschema.Draft202012Validator.check_schema(schema)
    v = jsonschema.Draft202012Validator(schema)
    try:
        fv = fastjsonschema.compile(schema)
        fjs_ok = True
    except Exception as e:  # noqa: BLE001
        fv, fjs_ok = None, False
        print("fastjsonschema compile failed:", e)
    rows = []
    for d, expect in ((ex_dir, "valid"), (bad_dir, "invalid")):
        for f in sorted(os.listdir(d)):
            p = os.path.join(d, f)
            try:
                doc = load(p)
            except Exception as e:  # noqa: BLE001
                rows.append((f, expect, "json-error", str(e)[:60], ""))
                continue
            e = js_errors(v, doc)
            rows.append((f, expect, "valid" if not e else "invalid", "; ".join(e)[:200],
                         fjs_result(fv, doc) if fjs_ok else "n/a"))

    base = load(os.path.join(ex_dir, "ex2_crt_education.json"))
    probes = {}
    p = copy.deepcopy(base); p["estimands"] = []; probes["confirmatory_empty_estimands"] = p
    p = copy.deepcopy(base); p["variables"] = {}; probes["confirmatory_empty_variables"] = p
    p = copy.deepcopy(base); p["variables"] = {"pre": {"role": "baseline_covariate"}}
    probes["confirmatory_no_outcome_no_assigned_role"] = p
    p = copy.deepcopy(base); p["assignment"] = []; probes["cluster_randomised_empty_assignment"] = p
    p = copy.deepcopy(base); p["units"][1]["x-inferred"] = True; probes["x_inferred_inside_unit"] = p
    p = copy.deepcopy(base); p["x-inferred"] = {"units": [1]}; probes["x_inferred_top_level"] = p
    p = copy.deepcopy(base); p["units"][1]["nested_in"] = "schol"; probes["nested_in_misspelt_unit_name"] = p
    p = copy.deepcopy(base); p["assignment"][0]["unit"] = "klass"; probes["assignment_unit_misspelt"] = p
    p = copy.deepcopy(base)
    p["units"][0]["nested_in"] = "pupil"; p["units"][0]["id_scope"] = "global"
    probes["nested_in_cycle"] = p
    p = copy.deepcopy(base); p["features"] = ["cluster_randomised"]
    del p["observation"]["time"]; p["units"][2]["membership"] = "may_change_over_time"
    probes["mobility_without_time"] = p
    p = copy.deepcopy(base); p["table"]["fields"][3]["categoriesOrderd"] = True
    probes["table_field_typo_property"] = p
    p = copy.deepcopy(base); p["table"]["primaryKey"] = ["school", "klass"]
    probes["primaryKey_unknown_column"] = p
    p = copy.deepcopy(base); p["schema_version"] = "0.1.1"; probes["schema_version_patch_bump"] = p
    p = copy.deepcopy(base); p["features"] = ["multisite"]
    del p["assignment"]; probes["observational_multisite_without_assignment"] = p
    p = copy.deepcopy(base); p["estimands"][0]["term"] = "arm_typo"; probes["estimand_term_not_in_data"] = p
    for name, doc in probes.items():
        e = js_errors(v, doc)
        rows.append((name, "probe", "valid" if not e else "invalid", "; ".join(e)[:200],
                     fjs_result(fv, doc) if fjs_ok else "n/a"))
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("case\texpected\tjsonschema_4.26\tjsonschema_messages\tfastjsonschema_2.22.3\n")
        for r in rows:
            fh.write("\t".join(r) + "\n")
    for r in rows:
        print(f"{r[0]:<45} {r[1]:<8} js={r[2]:<8} fjs={r[4][:40]:<40} {r[3][:110]}")


if __name__ == "__main__":
    main()
