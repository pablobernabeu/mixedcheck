#!/bin/bash
cd /tmp/claude-0/-home-user-lmecheck/76ff8921-f521-5c13-b469-59b514d4e510/scratchpad/r2/B/sim
while ! grep -q ALLDONE out/sim1_small.log 2>/dev/null; do sleep 10; done
# Sim 2: cross-level interaction
seed=2000
for J in 15 40; do
  for tau in 0 0.15 0.3; do
    seed=$((seed+1)); Rscript sim2_crosslevel.R $J 20 $tau 0 1000 $seed out/sim2_J${J}_tau${tau}_b0.csv >> out/sim2.log 2>&1
  done
  seed=$((seed+1)); Rscript sim2_crosslevel.R $J 20 0.15 0.15 600 $seed out/sim2_J${J}_tau0.15_b0.15.csv >> out/sim2.log 2>&1
done
echo ALLDONE >> out/sim2.log
# Sim 3: nuisance slope ordering
seed=3000
for r in 0 0.5; do
  for b in 0 0.15; do
    seed=$((seed+1)); if [ "$b" = "0" ]; then n=1000; else n=600; fi
    Rscript sim3_nuisance_order.R 30 20 0.3 $r $b $n $seed out/sim3_S30_m20_tau0.3_r${r}_b${b}.csv >> out/sim3.log 2>&1
  done
done
echo ALLDONE >> out/sim3.log
# Sim 1, larger crossed design
seed=4000
for tau in 0.2 0.4; do
  for beta in 0 0.18; do
    seed=$((seed+1)); Rscript sim1_stopping_rules.R 48 32 $tau $beta 500 $seed out/sim1_S48_I32_tau${tau}_b${beta}.csv >> out/sim1_large.log 2>&1
  done
done
echo ALLDONE >> out/sim1_large.log
