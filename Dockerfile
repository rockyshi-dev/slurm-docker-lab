# One image for every role (slurmctld, slurmdbd, slurmd). CPU only: no CUDA, no GPU device is ever mapped in.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        slurm-wlm slurmdbd slurm-client munge mariadb-client \
        python3 python3-venv iproute2 iputils-ping procps less vim-tiny ca-certificates \
    && rm -rf /var/lib/apt/lists/*
# torch, CPU wheel only (the DDP exercise uses the gloo backend)
RUN python3 -m venv /opt/venv && /opt/venv/bin/pip install --no-cache-dir \
        --index-url https://download.pytorch.org/whl/cpu torch
# the job-submitting user; uid 1000 = the host user, so files in the bind-mounted /shared are writable on both sides
RUN userdel -r ubuntu 2>/dev/null || true; useradd -m -u 1000 -s /bin/bash lab
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
