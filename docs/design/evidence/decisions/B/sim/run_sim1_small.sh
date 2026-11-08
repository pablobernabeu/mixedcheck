#!/bin/bash
cd /tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim
seed=1000
for beta in 0 0.25; do
  for tau in 0 0.1 0.2 0.4; do
    seed=$((seed+1))
    if [ "$beta" = "0" ]; then n=1000; else n=600; fi
    Rscript sim1_stopping_rules.R 24 16 $tau $beta $n $seed out/sim1_S24_I16_tau${tau}_b${beta}.csv >> out/sim1_small.log 2>&1
  done
done
echo ALLDONE >> out/sim1_small.log
