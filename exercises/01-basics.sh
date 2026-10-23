#!/bin/bash
# Exercise 1: sinfo / sbatch / squeue / scancel, partitions, time limits, priorities, GRES. Run inside slurmctld as lab:
#   docker exec -u lab -w /shared/logs slurmctld bash /home/lab/exercises/01-basics.sh  (job output lands in the cwd)
set -u
say() { echo; echo "### $*"; }
say "partitions and nodes"; sinfo; sinfo -N -o "%N %c %m %G %t %P"
say "submit a job, watch it, cancel it"
j=$(sbatch --parsable -t 5 --wrap 'hostname; sleep 60'); sleep 3; squeue -j "$j"; scancel "$j"; sleep 3
sacct -j "$j" --format=JobID,JobName,State,ExitCode,NodeList -X
say "time limit: a 90 s job with --time=1 (one minute) ends in TIMEOUT"
j=$(sbatch --parsable --time=1 --wrap 'sleep 90'); echo "job $j submitted at $(date +%T); waiting..."
for i in $(seq 1 40); do st=$(sacct -j "$j" -X -n -o State | tr -d ' '); case "$st" in TIMEOUT|COMPLETED|CANCELLED) break;; esac; sleep 5; done
sacct -j "$j" --format=JobID,State,Elapsed,Timelimit -X
say "priorities: fill the cluster, then two pending jobs; the later one with a lower nice value is ordered first"
f=$(sbatch --parsable -N 4 --exclusive -t 3 --wrap 'sleep 120')
a=$(sbatch --parsable -N 4 --exclusive --nice=5000 -t 2 --job-name=nice5000 --wrap 'sleep 5')
b=$(sbatch --parsable -N 4 --exclusive -t 2 --job-name=nice0 --wrap 'sleep 5')
sleep 5; squeue -o "%.8i %.10j %.8T %.10Q %.6p %r" --sort=-p; sprio -l; scancel "$f" "$a" "$b"
say "GRES: 4 fake GPUs per node (slurm.conf has DefMemPerCPU=1000, so a job reserves memory per CPU, not the whole node)"
srun --gres=gpu:4 -N1 bash -c 'echo "$(hostname): SLURM_GPUS_ON_NODE=$SLURM_GPUS_ON_NODE CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"'
echo "asking for 5 GPUs on one node must be refused:"; srun --gres=gpu:5 -N1 hostname 2>&1 | head -1
echo "two 3-GPU jobs cannot share one node: the second pends while the first runs"
g1=$(sbatch --parsable --gres=gpu:3 -w c1 -t 2 --wrap 'sleep 30'); g2=$(sbatch --parsable --gres=gpu:3 -w c1 -t 2 --wrap 'sleep 5')
sleep 4; squeue -o "%.8i %.8T %.6b %R" -j "$g1,$g2"; scancel "$g1" "$g2"; sleep 4
echo "control: two 2-GPU jobs fit on one node and run together"
g3=$(sbatch --parsable --gres=gpu:2 -w c1 -t 2 --wrap 'sleep 30'); g4=$(sbatch --parsable --gres=gpu:2 -w c1 -t 2 --wrap 'sleep 30')
sleep 4; squeue -o "%.8i %.8T %.6b %R" -j "$g3,$g4"; sacct -j "$g1,$g3,$g4" -X -o JobID,AllocTRES%40; scancel "$g3" "$g4"
say "accounting"; sacct -S now-10minutes -X --format=JobID,JobName,Partition,State,Elapsed,NodeList | tail -n 12
