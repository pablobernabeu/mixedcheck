#!/bin/bash
# Job-array template for the lmecheck validation study on Oxford ARC 'htc' (key F).
# Sources: ARC User Guide (job-scheduling, arc-storage, slurm-reference, slurm-faq) and
# ARC Software Guide (arc-serial, R/arc_r_module, R/arc_r_packages), read from
# github.com/oxford-arc on 2026-11-07. Items marked CHECK must be confirmed on ARC first.
#
# Submit one array per study, e.g. for V1a with 12 tasks (array_plan.csv):
#   sbatch --job-name=lmc-V1a --array=1-12%12 --time=09:00:00 \
#          --export=ALL,STUDY=V1a lmc_array.sbatch
# Before the first submission: mkdir -p /data/educ-intract/educ1242/lmecheck-sim/logs
#   (SLURM does not create the --output directory; jobs fail silently without it).
# Resubmit only failed or missing tasks (chunks already on $DATA are skipped):
#   sbatch --job-name=lmc-V1a --array=3,7 --export=ALL,STUDY=V1a lmc_array.sbatch
#
#SBATCH --clusters=htc
#SBATCH --partition=short             # max 12 h; highest priority; 7,872 cores (arc-systems page)
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1             # one replicate stream per core; parallelism comes from the array
#SBATCH --mem-per-cpu=2G              # measured peak < 0.3 GB per fit; ARC default is 8000 MB per CPU
#SBATCH --constraint='cpu_gen:Cascade_Lake'   # same CPU family as the interactive build nodes
#SBATCH --signal=B:SIGINT@180         # warn 3 min before the time limit (arc-storage page)
#SBATCH --output=/data/educ-intract/educ1242/lmecheck-sim/logs/%x_%A_%a.out
#SBATCH --error=/data/educ-intract/educ1242/lmecheck-sim/logs/%x_%A_%a.err
#SBATCH --mail-type=FAIL,ARRAY_TASKS
# CHECK: scontrol show config | grep -Ei 'MaxArraySize|MaxJobCount'  (SLURM default MaxArraySize is 1001)
# CHECK: sacctmgr show assoc user=$USER format=account,qos,maxjobs,maxsubmit ; mybalance

set -euo pipefail
PROJ=/data/educ-intract/educ1242/lmecheck-sim          # project space ($DATA quota 5 TiB, shared, no backups)
STUDY_DIR=$PROJ/studies/$STUDY                         # cells.csv, plan.csv, study.R (frozen at a git tag)
RESULTS=$PROJ/results/$STUDY

module purge
module load R/4.4.0-gfbf-2023a                         # CHECK: module spider R (use the newest; record it)
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 FLEXIBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1
export R_LIBS=$PROJ/Rlib/R-4.4.0-cascadelake            # built once on an interactive node (srun -p interactive)
export R_LIBS_USER=$R_LIBS
# Alternative for exact reproducibility: an Apptainer image built off-cluster (ARC cannot build images):
#   apptainer exec $PROJ/containers/lmc-sim-<digest>.sif Rscript ...

mkdir -p "$RESULTS" "$PROJ/logs"
cd "$SCRATCH" || exit 1                                # per-job scratch, removed at job exit
mkdir -p out
# copy back anything already complete if SLURM signals an impending timeout
trap 'echo "SIGINT: saving completed chunks"; rsync -a --exclude="*.part" out/ "$RESULTS/"; exit 2' INT
# do not repeat chunks finished by an earlier attempt of this task
rsync -a --include='*/' --include='*.csv' --include='*.json' --exclude='*' "$RESULTS/" out/ 2>/dev/null || true

rc=0
Rscript --vanilla $PROJ/code/run_task.R "$STUDY_DIR" "$SLURM_ARRAY_TASK_ID" "$SCRATCH/out" &
wait $! || rc=$?                                       # keep going so completed chunks are copied back
rsync -a --exclude="*.part" out/ "$RESULTS/"
echo "done: $STUDY task $SLURM_ARRAY_TASK_ID rc=$rc on $(hostname) $(date -Is)"
exit $rc
