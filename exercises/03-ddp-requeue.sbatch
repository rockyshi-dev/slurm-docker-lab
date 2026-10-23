#!/bin/bash
# Exercise 3: the same DDP job, slowed to about 5 minutes, with --requeue and a checkpoint every 20 steps.
# The checkpoint file is kept at start, so a requeued job resumes from it (the drill script removes it before submitting).
#SBATCH --job-name=ddp-requeue
#SBATCH --partition=main
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:4
#SBATCH --time=00:20:00
#SBATCH --requeue
#SBATCH --open-mode=append
#SBATCH --output=/shared/logs/%x-%j.out
export MASTER_ADDR=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)
export MASTER_PORT=29500
echo "=== start $(date -u +%FT%TZ) nodes: $SLURM_JOB_NODELIST master: $MASTER_ADDR restart count: ${SLURM_RESTART_COUNT:-0}"
srun /opt/venv/bin/python /home/lab/exercises/ddp_train.py --steps 600 --step-seconds 0.5 --ckpt-every 20 \
     --ckpt /shared/ckpt/ddp-requeue.pt
