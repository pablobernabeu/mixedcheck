#!/bin/bash
cd /tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B-verify
seed=7000
for r in 0.5 0; do
 for tf in 0 0.1 0.3; do
  for b in 0 0.15; do
   seed=$((seed+1)); if [ "$b" = "0" ]; then n=2000; else n=1000; fi
   Rscript scripts/v2_srp_global_vs_local.R 30 20 $tf 0.3 $r $b $n $seed out/v2_tf${tf}_tn0.3_r${r}_b${b}.csv >> out/v2.log 2>&1
  done
 done
done
seed=7100
Rscript scripts/v2_srp_global_vs_local.R 30 20 0 0 0.5 0 2000 $((seed+1)) out/v2_tf0_tn0_r0.5_b0.csv >> out/v2.log 2>&1
Rscript scripts/v2_srp_global_vs_local.R 30 20 0.1 0.5 0.5 0 2000 $((seed+2)) out/v2_tf0.1_tn0.5_r0.5_b0.csv >> out/v2.log 2>&1
echo ALLDONE >> out/v2.log
