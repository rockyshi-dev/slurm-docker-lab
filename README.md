# slurm-docker-lab: a four-node Slurm cluster in Docker, for learning

A practice cluster that runs on one Linux machine with Docker. One image (Ubuntu 24.04, Slurm 23.11 from the
distribution packages, a CPU-only PyTorch in `/opt/venv`) runs every role: the controller `slurmctld`, the
accounting daemon `slurmdbd` (backed by MariaDB 11.4) and four compute nodes `c1`-`c4`. Each node is declared with
4 CPUs, 4000 MB of memory and **4 fake GPUs**: `--gres=gpu:N` is scheduled against a count, and no real GPU is
mapped into any container. No GPU is needed on the host.

The walkthrough that explains every file and every output is the blog post
[Learning Slurm on one machine](https://rockyshi.dev/posts/slurm-cluster-in-docker/).

## Requirements

- Docker with the compose plugin (`docker compose version`).
- Your host user should have uid 1000. The job-submitting user `lab` inside the containers has uid 1000, and the
  shared job directory `data/shared` is bind-mounted, so it must be writable by that uid. With another uid, change
  `useradd -u 1000` in the `Dockerfile`.
- A few GB of disk for the image. The compute containers are capped at 4 CPUs each; the exercises run on a desktop.

## Use

```bash
./lab.sh up        # create the munge key, build the image, start 7 containers, wait until 4 nodes are idle
./lab.sh sh        # a shell in slurmctld as user lab (the "login node")
./lab.sh ex1       # exercise 1: sbatch/squeue/scancel, time limit -> TIMEOUT, nice/priority order, GPUs
./lab.sh ex2       # exercise 2: DDP on 2 nodes x 4 tasks, gloo backend, launched by srun
./lab.sh ex3       # exercise 3: fault drill, stop one compute node mid-job and watch the requeue and resume
./lab.sh ex4       # exercise 4: partition preemption, a job in `high` requeues a job in `low`
./lab.sh down      # stop and remove the containers; data/ and the MariaDB volume stay
```

`data/shared` is the cluster's shared file system (`/shared` in every container): job output in `data/shared/logs`,
checkpoints in `data/shared/ckpt`. Daemon logs are in `data/log/<container>`.

## Exercises

1. **Basics** (`exercises/01-basics.sh`): partitions `main` (default), `low`, `high`; submit, watch and cancel a
   job; a job with `--time=1` that sleeps 90 s ends `TIMEOUT`; with the cluster full, a job with `--nice=5000` is
   ordered after a later job without it (`sprio -l` shows the parts); `--gres=gpu:4` works, `--gres=gpu:5` is
   refused, two `--gres=gpu:3` jobs cannot share a node while two `--gres=gpu:2` jobs run on one node together.
2. **DDP** (`exercises/02-ddp.sbatch`, `exercises/ddp_train.py`): `--nodes=2 --ntasks-per-node=4`, the first node of
   the allocation as `MASTER_ADDR`, `srun python ddp_train.py`. Each task reads its rank from `SLURM_PROCID`, joins a
   gloo process group and trains a small MLP on synthetic data; rank 0 writes a checkpoint every 20 steps (to a
   temporary file, then renamed).
3. **Fault drill** (`exercises/03-fault-drill.sh`, run on the host): submits `exercises/03-ddp-requeue.sbatch`
   (`--requeue`, 600 slow steps, checkpoint every 20), stops the container of the job's second node after the second
   checkpoint, and follows the node to `DOWN`, the job back to `PENDING`, the node back to `idle` after
   `docker start`, and the job's restart, which resumes from its last checkpoint. The requeued job waits about two
   minutes with `Reason=BeginTime` before it runs again: Slurm 23.11 sets its begin time to the requeue time plus
   the launch credential's lifetime (120 s by default) plus 1 s.
4. **Preemption** (`exercises/04-preemption.sh`): a job in `high` (PriorityTier 2) requeues a running job in `low`.
   For gang scheduling set `PreemptMode=SUSPEND,GANG` in `config/slurm.conf` and run `scontrol reconfigure` in
   slurmctld; the low job is then suspended and resumed instead of requeued.

## What differs from a real cluster

- `ProctrackType=proctrack/linuxproc`, `TaskPlugin=task/none`: no cgroups inside the containers, so memory and CPU
  limits are bookkeeping only. A real cluster uses `proctrack/cgroup` and `task/cgroup`.
- `config/cgroup.conf` says `CgroupPlugin=cgroup/v1`. slurmd 23.11 initialises a cgroup plugin even when no
  cgroup-based plugin is configured; `cgroup/v2` needs dbus and a writable `/sys/fs/cgroup`, which an unprivileged
  container does not have, and `disabled` only exists from 24.05. `cgroup/v1` loads without touching anything.
- `config/gres.conf` names four pseudo devices (`/dev/null`, `/dev/zero`, `/dev/full`, `/dev/random`) as the GPUs.
  The gres/gpu plugin of 23.11 drops a GPU line without `File=`, and the node is then rejected for reporting 0 of
  its 4 GPUs. With `task/none` nothing is bound to the files; a job step only sees `CUDA_VISIBLE_DEVICES`.
- `entrypoint.sh` makes slurmctld wait until `c1`-`c4` resolve in Docker's DNS. The controller resolves node
  addresses once, when it reads `slurm.conf`, and a container that is not running yet does not resolve.
- `SlurmdParameters=config_overrides`: the declared 4 CPUs and 4000 MB per node are used whatever the container
  reports.
- `DefMemPerCPU=1000`: with `CR_Core_Memory` and no default, a job that does not pass `--mem` reserves its whole
  node's memory, and a second job on that node waits for memory whatever it asks of the GPUs.
- `SlurmdTimeout=30` (default 300), so the fault drill shows the node `DOWN` within a minute.
- The MariaDB password and the munge key are for a local lab only: `config/munge.key` is generated by
  `lab.sh up` and not committed, and the database is reachable only on the compose network.

## License

MIT
