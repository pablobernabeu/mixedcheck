"""Print how PyYAML (safe_load, YAML 1.1) types each scalar in a YAML file."""
import sys, yaml, datetime
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for k, v in d.items():
    t = type(v).__name__
    print(f"{k}\t{t}\t{v!r}")
