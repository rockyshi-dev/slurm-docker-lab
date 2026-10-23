#!/bin/bash
# ROLE=slurmctld | slurmdbd | slurmd. Config is bind-mounted read-only at /etc/slurm-lab and copied into place here.
set -eu
install -o munge -g munge -m 0400 /etc/slurm-lab/munge.key /etc/munge/munge.key
mkdir -p /run/munge && chown munge:munge /run/munge
runuser -u munge -- /usr/sbin/munged
mkdir -p /etc/slurm /var/spool/slurmctld /var/spool/slurmd /var/log/slurm /shared/logs /shared/ckpt
for f in slurm.conf gres.conf cgroup.conf; do install -m 0644 /etc/slurm-lab/$f /etc/slurm/$f; done
install -o slurm -g slurm -m 0600 /etc/slurm-lab/slurmdbd.conf /etc/slurm/slurmdbd.conf
chown slurm:slurm /var/spool/slurmctld /var/log/slurm
chown lab:lab /shared/logs /shared/ckpt 2>/dev/null || true
wait_port() { for i in $(seq 1 60); do (exec 3<>/dev/tcp/$1/$2) 2>/dev/null && return 0; sleep 2; done; echo "timeout waiting for $1:$2"; return 1; }
case "${ROLE:?}" in
  slurmdbd)
    for i in $(seq 1 60); do mysqladmin ping -h mariadb -u slurm -pslurmlab --silent 2>/dev/null && break; sleep 2; done
    /usr/sbin/slurmdbd -D -v &
    wait_port localhost 6819
    sacctmgr -i add cluster lab 2>/dev/null || true
    sacctmgr -i add account lab description=lab 2>/dev/null || true
    sacctmgr -i add user lab account=lab 2>/dev/null || true
    wait ;;
  slurmctld)
    wait_port slurmdbd 6819
    # Docker DNS only resolves running containers; slurmctld reads the node addresses once, when it reads slurm.conf.
    for n in c1 c2 c3 c4; do for i in $(seq 1 60); do getent hosts $n >/dev/null && break; sleep 1; done; done
    exec /usr/sbin/slurmctld -D -v ;;
  slurmd)
    wait_port slurmctld 6817
    exec /usr/sbin/slurmd -D -v ;;
  *) echo "unknown ROLE $ROLE"; exit 2 ;;
esac
