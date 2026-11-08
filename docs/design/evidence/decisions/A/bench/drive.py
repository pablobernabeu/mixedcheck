import subprocess, sys, os, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import S
HERE = os.path.dirname(os.path.abspath(__file__))
PY = {"default": os.path.join(HERE, "..", "venv312", "bin", "python"),
      "rpy2_lme4": os.path.join(HERE, "..", "venv_pymer4", "bin", "python")}
engines = sys.argv[1].split(",")
models = sys.argv[2].split(",") if len(sys.argv) > 2 and sys.argv[2] != "all" else list(S)
timeout = int(os.environ.get("BENCH_TIMEOUT", "900"))
os.makedirs(os.path.join(HERE, "out"), exist_ok=True)
for e in engines:
    for m in models:
        outf = os.path.join(HERE, "out", f"{e}__{m}.json")
        if os.path.exists(outf) and not os.environ.get("FORCE"):
            continue
        reps = "1" if "big" in m and e == "statsmodels" else "3"
        env = dict(os.environ, R_HOME="/usr/lib/R", BENCH_DATA=os.path.join(HERE, "data"))
        t0 = time.time()
        try:
            p = subprocess.run([PY.get(e, PY["default"]), "-I", os.path.join(HERE, "run_one.py"), e, m, outf, reps],
                               capture_output=True, text=True, timeout=timeout, env=env, cwd=HERE)
            log = (p.stdout or "") + "\n" + (p.stderr or "")
            if p.returncode != 0 and not os.path.exists(outf):
                json.dump(dict(engine=e, model=m, status="crash", reason=f"exit {p.returncode}", log=log[-3000:]), open(outf, "w"))
            else:
                r = json.load(open(outf)); r["stdout_tail"] = log[-2000:]; json.dump(r, open(outf, "w"), indent=1)
        except subprocess.TimeoutExpired:
            json.dump(dict(engine=e, model=m, status="timeout", reason=f">{timeout}s"), open(outf, "w"))
        r = json.load(open(outf))
        print(f"{e:14s} {m:22s} {r['status']:12s} {time.time()-t0:7.1f}s {str(r.get('reason',''))[:120]}", flush=True)
