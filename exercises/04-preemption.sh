#!/bin/bash
# Exercise 4 (optional): partition preemption. slurm.conf has PreemptType=preempt/partition_prio, PreemptMode=REQUEUE,
# partitions low (PriorityTier=1) and high (PriorityTier=2). A job in high requeues a running job in low.
# For gang scheduling instead: set PreemptMode=SUSPEND,GANG in slurm.conf and `scontrol reconfigure`; the low job is
# then suspended rather than requeued, and resumed when the high job ends.
# Run inside slurmctld as lab: docker exec -u lab -w /shared/logs slurmctld bash /home/lab/exercises/04-preemption.sh
set -u
l=$(sbatch --parsable -p low -N 4 --exclusive --requeue -t 5 --job-name=low --wrap 'sleep 300'); sleep 4
echo "low job $l: $(squeue -h -j $l -o '%T %N')"
h=$(sbatch --parsable -p high -N 4 --exclusive -t 2 --job-name=high --wrap 'sleep 20'); sleep 8
squeue -o "%.8i %.6j %.5P %.9T %.6p %R"
for i in $(seq 1 10); do sleep 5; squeue -h -o "%.8i %.6j %.5P %.9T %R"; done
scontrol show job $l | grep -E "JobState|Restarts|Reason"; scancel $l
