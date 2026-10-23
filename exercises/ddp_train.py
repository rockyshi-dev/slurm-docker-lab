"""Tiny DDP training on CPU with the gloo backend, launched by `srun` (one process per task).
Rank and world size come from Slurm's environment; MASTER_ADDR/MASTER_PORT from the sbatch script.
Saves a checkpoint every --ckpt-every steps (rank 0, atomic rename) and resumes from it if present, so a requeued
job continues where the last checkpoint left off (exercise 3)."""
import argparse, os, socket, time
import torch, torch.distributed as dist, torch.nn as nn

p = argparse.ArgumentParser()
p.add_argument('--steps', type=int, default=200)
p.add_argument('--ckpt', default='/shared/ckpt/ddp.pt')
p.add_argument('--ckpt-every', type=int, default=20)
p.add_argument('--step-seconds', type=float, default=0.0, help='sleep per step, to make a job last long enough to kill')
a = p.parse_args()

rank = int(os.environ['SLURM_PROCID']); world = int(os.environ['SLURM_NTASKS']); local = int(os.environ['SLURM_LOCALID'])
os.environ.setdefault('RANK', str(rank)); os.environ.setdefault('WORLD_SIZE', str(world))
dist.init_process_group('gloo', init_method='env://', rank=rank, world_size=world)
torch.manual_seed(0); torch.set_num_threads(1)
model = nn.Sequential(nn.Linear(32, 64), nn.ReLU(), nn.Linear(64, 1))
ddp = nn.parallel.DistributedDataParallel(model)
opt = torch.optim.SGD(ddp.parameters(), lr=0.05)
start = 0
if os.path.exists(a.ckpt):
    ck = torch.load(a.ckpt, map_location='cpu')
    ddp.module.load_state_dict(ck['model']); opt.load_state_dict(ck['opt']); start = ck['step']
    if rank == 0: print(f'resumed from {a.ckpt} at step {start}', flush=True)
if rank == 0:
    print(f'world {world} ranks; node {socket.gethostname()} rank {rank} local {local}; '
          f'SLURM_JOB_ID {os.environ.get("SLURM_JOB_ID")} restart {os.environ.get("SLURM_RESTART_COUNT", "0")}; '
          f'fake GPUs on this node: SLURM_GPUS_ON_NODE={os.environ.get("SLURM_GPUS_ON_NODE")}', flush=True)
g = torch.Generator().manual_seed(1000 + rank)
for step in range(start, a.steps):
    x = torch.randn(64, 32, generator=g); y = (x.sum(1, keepdim=True) > 0).float()
    loss = nn.functional.binary_cross_entropy_with_logits(ddp(x), y)
    opt.zero_grad(); loss.backward(); opt.step()
    if a.step_seconds: time.sleep(a.step_seconds)
    if (step + 1) % a.ckpt_every == 0:
        dist.barrier()
        if rank == 0:
            tmp = a.ckpt + '.tmp'
            torch.save({'model': ddp.module.state_dict(), 'opt': opt.state_dict(), 'step': step + 1}, tmp)
            os.replace(tmp, a.ckpt)
            print(f'step {step + 1}/{a.steps} loss {loss.item():.4f} checkpoint saved', flush=True)
dist.barrier()
if rank == 0: print('done', flush=True)
dist.destroy_process_group()
