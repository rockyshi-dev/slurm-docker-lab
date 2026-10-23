#!/bin/bash
# Exercise 3, run on the HOST: submit the requeue job, stop one of its compute-node containers mid-run, watch the node
# go DOWN and the job return to PENDING (NODE_FAIL -> requeue), start the container again, watch the job resume from
# its checkpoint. Only this lab's containers (c1-c4) are ever stopped.
set -u
cd "$(dirname "$0")/.."
X() { docker exec -u lab -w /shared/logs slurmctld "$@"; }
ck=data/shared/ckpt/ddp-requeue.pt
[ -e "$ck" ] && mv "$ck" "$ck.prev"
j=$(X sbatch --parsable /home/lab/exercises/03-ddp-requeue.sbatch); echo "job $j submitted"
for i in $(seq 1 60); do [ "$(X squeue -h -j "$j" -o %T)" = RUNNING ] && break; sleep 2; done
nodes=$(X scontrol show hostnames "$(X squeue -h -j "$j" -o %N)"); echo "running on: $(echo $nodes)"
log=data/shared/logs/ddp-requeue-$j.out
echo "waiting for the second checkpoint..."; for i in $(seq 1 120); do grep -q "step 40/" "$log" 2>/dev/null && break; sleep 2; done
victim=$(echo "$nodes" | tail -n 1)
case "$victim" in c1|c2|c3|c4) ;; *) echo "unexpected node name $victim"; exit 2;; esac
echo "=== $(date +%T) stopping container $victim (the non-batch node of the job)"; docker stop "$victim" >/dev/null
echo "docker stop $victim at $(date -u +%FT%TZ)"   # the controller logs are in UTC; this line is for the timeline
for i in $(seq 1 60); do st=$(X sinfo -h -n "$victim" -o %T); echo "$(date +%T) $victim $st  job $(X squeue -h -j "$j" -o '%T %r %Q')"; case "$st" in down*) break;; esac; sleep 5; done
echo "waiting for the job to be requeued (PENDING) or to fail..."
for i in $(seq 1 60); do s=$(X squeue -h -j "$j" -o %T); echo "$(date +%T) job $j ${s:-gone}"; case "$s" in PENDING|"") break;; esac; sleep 5; done
X scontrol show job "$j" | grep -E "JobState|Restarts|NodeList|Reason"
echo "=== $(date +%T) starting container $victim"; docker start "$victim" >/dev/null
for i in $(seq 1 60); do st=$(X sinfo -h -n "$victim" -o %T); case "$st" in idle|mixed|allocated) break;; esac; sleep 5; done
echo "$victim is $st again"
# sacct without -D reports the first incarnation (NODE_FAIL), so wait on the queue instead and then list both runs
echo "waiting for the requeued job to run again and finish..."
for i in $(seq 1 200); do s=$(X squeue -h -j "$j" -o '%T %r'); [ -z "$s" ] && break; echo "$(date +%T) job $j $s"; sleep 10; done
X sacct -j "$j" -D --format=JobID,State,Elapsed,NodeList,Start,End -X
X scontrol show job "$j" | grep -oE "Restarts=[0-9]+"
echo "=== job log (start lines, resume line, last line):"; grep -E "^=== start|resumed from|^done" "$log"
