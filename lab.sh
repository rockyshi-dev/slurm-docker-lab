#!/bin/bash
# Lab driver: start and stop the cluster, open a shell on the controller, run the exercises.
set -u
cd "$(dirname "$0")"
case "${1:-}" in
  up)
    [ -f config/munge.key ] || { dd if=/dev/urandom of=config/munge.key bs=1024 count=1 status=none; chmod 600 config/munge.key; }
    mkdir -p data/shared/logs data/shared/ckpt data/state data/log/{slurmdbd,slurmctld,c1,c2,c3,c4}
    docker compose build && docker compose up -d || exit 1
    for i in $(seq 1 60); do n=$(docker exec slurmctld sinfo -h -p main -N -o %T 2>/dev/null | grep -c "^idle$"); [ "$n" = 4 ] && break; sleep 3; done
    docker exec slurmctld sinfo ;;
  down)    docker compose down ;;
  sh)      docker exec -u lab -w /shared/logs -it slurmctld bash ;;
  ex1)     docker exec -u lab -w /shared/logs slurmctld bash /home/lab/exercises/01-basics.sh ;;
  ex2)     j=$(docker exec -u lab -w /shared/logs slurmctld sbatch --parsable /home/lab/exercises/02-ddp.sbatch); echo "job $j"
           for i in $(seq 1 120); do s=$(docker exec -u lab -w /shared/logs slurmctld sacct -j "$j" -X -n -o State | tr -d ' '); case "$s" in COMPLETED|FAILED|CANCELLED|TIMEOUT) break;; esac; sleep 3; done
           echo "state $s"; cat data/shared/logs/ddp-cpu-$j.out ;;
  ex3)     bash exercises/03-fault-drill.sh ;;
  ex4)     docker exec -u lab -w /shared/logs slurmctld bash /home/lab/exercises/04-preemption.sh ;;
  *) echo "usage: $0 up|down|sh|ex1|ex2|ex3|ex4"; exit 2 ;;
esac
