#!/bin/bash
# Exercise 2: 2 nodes x 4 tasks, one DDP rank per task, gloo on CPU. Submit from the slurmctld container as user lab:
#   sbatch /home/lab/exercises/02-ddp.sbatch
#SBATCH --job-name=ddp-cpu
#SBATCH --partition=main
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --gres=gpu:4
#SBATCH --time=00:10:00
#SBATCH --output=/shared/logs/%x-%j.out
export MASTER_ADDR=$(scontrol show hostnames "$SLURM_JOB_NODELIST" | head -n 1)
export MASTER_PORT=29500
echo "nodes: $SLURM_JOB_NODELIST  master: $MASTER_ADDR  tasks: $SLURM_NTASKS"
[ -e /shared/ckpt/ddp-cpu.pt ] && mv /shared/ckpt/ddp-cpu.pt /shared/ckpt/ddp-cpu.pt.prev
srun /opt/venv/bin/python /home/lab/exercises/ddp_train.py --steps 200 --ckpt /shared/ckpt/ddp-cpu.pt
