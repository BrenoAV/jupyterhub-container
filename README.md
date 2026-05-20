# JupyterHub on Rocky Linux 9 — Manual Setup Guide

This guide walks through everything `install_jupyterhub.sh` does, step by step, so you understand each decision and can adapt it to your environment. Run all commands as **root** (or with `sudo`) unless otherwise noted.

---

## Overview

The setup has four phases, which can be done in any order but are best run in sequence:

1. [Install Docker CE & Compose](#phase-1-install-docker-ce--compose)
2. [Install NVIDIA drivers & Container Toolkit](#phase-2-install-nvidia-drivers--container-toolkit) *(skip if CPU-only)*
3. [Create loopback XFS storage](#phase-3-create-loopback-xfs-storage)
4. [Build Docker images & start JupyterHub](#phase-4-build-images--start-jupyterhub)

---

## Phase 1 — Install Docker CE & Compose

Docker CE is installed from Docker's official CentOS repository (compatible with Rocky Linux 9).

### 1.1 — Install the DNF plugins package

```bash
dnf install -y dnf-plugins-core
```

This provides `dnf config-manager`, needed to add third-party repositories.

### 1.2 — Add the Docker CE repository

```bash
dnf config-manager --add-repo \
  https://download.docker.com/linux/centos/docker-ce.repo
```

This writes a `.repo` file to `/etc/yum.repos.d/` pointing at Docker's CentOS package mirror.

### 1.3 — Install Docker CE and related components

```bash
dnf install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
```

| Package | Purpose |
|---|---|
| `docker-ce` | The Docker daemon |
| `docker-ce-cli` | The `docker` command-line tool |
| `containerd.io` | Low-level container runtime |
| `docker-buildx-plugin` | Extended image build capabilities (multi-platform, cache, etc.) |
| `docker-compose-plugin` | Enables `docker compose` (v2) sub-command |

### 1.4 — Enable and start the Docker service

```bash
systemctl enable --now docker
```

`enable` makes Docker start on boot; `--now` starts it immediately.

### 1.5 — (Optional) Allow your user to run Docker without sudo

```bash
usermod -aG docker YOUR_USERNAME
```

Replace `YOUR_USERNAME` with your login name. You must **log out and back in** (or run `newgrp docker`) for this to take effect. Root does not need this step.

---

## Phase 2 — Install NVIDIA Drivers & Container Toolkit

> **Skip this phase entirely if you are running CPU-only workloads.**

This is a two-part process because loading kernel modules requires a reboot between driver installation and toolkit configuration.

### Part A — Install the NVIDIA driver

#### 2.1 — Install EPEL and enable the CRB repository

```bash
dnf install -y epel-release
/usr/bin/crb enable
```

EPEL (Extra Packages for Enterprise Linux) and CRB (Code Ready Builder) provide build tools and libraries that the NVIDIA driver depends on.

#### 2.2 — Install build dependencies

```bash
dnf install -y \
  gcc gcc-c++ make git perl \
  python3 python3-pip \
  curl wget tar bzip2 which pciutils pkg-config \
  elfutils-libelf-devel libglvnd-devel dkms \
  kernel-devel-$(uname -r) \
  kernel-headers-$(uname -r)
```

`kernel-devel` and `kernel-headers` must match your **currently running** kernel exactly — this is why `$(uname -r)` is used. DKMS will use these to compile the NVIDIA kernel module.

#### 2.3 — Add the NVIDIA CUDA repository

```bash
dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
```

#### 2.4 — Refresh metadata and install the driver

```bash
dnf clean all && dnf makecache
dnf install -y nvidia-driver nvidia-driver-cuda
ldconfig
```

`ldconfig` updates the shared library cache so NVIDIA libraries are immediately discoverable.

#### 2.5 — Build the DKMS kernel module

```bash
# Detect the installed driver version
NVIDIA_VER=$(dkms status | grep -oP '^nvidia/\K[^,]+' | head -1)

# Fallback if dkms status is empty
NVIDIA_VER=$(rpm -q --queryformat '%{VERSION}' nvidia-driver | head -1)

dkms install "nvidia/${NVIDIA_VER}"
```

DKMS compiles and registers the NVIDIA kernel module against your current kernel. It will automatically recompile on future kernel updates.

#### 2.6 — Reboot

```bash
reboot
```

The NVIDIA kernel modules cannot be loaded until the system reboots.

---

### Part B — Install the NVIDIA Container Toolkit (after reboot)

#### 2.7 — Verify the driver loaded correctly

```bash
nvidia-smi
```

You should see a table listing your GPU(s), driver version, and CUDA version. If this fails, the driver did not load — check `dmesg` for errors.

#### 2.8 — Add the NVIDIA Container Toolkit repository

```bash
curl -fsSL \
  https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
  | tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null
```

#### 2.9 — Install the toolkit

```bash
dnf install -y nvidia-container-toolkit
```

This installs the runtime shim that allows Docker containers to access GPU resources.

#### 2.10 — Configure Docker to use the NVIDIA runtime

```bash
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

This adds the NVIDIA runtime to `/etc/docker/daemon.json` and restarts Docker so it picks up the change. Containers can then request GPU access via `--gpus all` or the `deploy.resources.reservations.devices` key in Compose.

---

## Phase 3 — Create Loopback XFS Storage

JupyterHub user notebooks and data are stored on a dedicated loopback-mounted XFS volume. This gives you quota control and keeps user data isolated from the OS disk.

The disk image lives at `/jupyter/jupyterhub_disk.img` and is mounted at `/jupyterhub`.

### 3.1 — Create the parent directory for the image file

```bash
mkdir -p /jupyter
```

### 3.2 — Create a sparse disk image

```bash
truncate -s 5000G /jupyter/jupyterhub_disk.img
```

`truncate` creates a **sparse** file — it reserves 5 TB of address space but consumes only the blocks actually written. Actual disk usage starts near zero and grows with data.

### 3.3 — Format the image as XFS

```bash
mkfs.xfs /jupyter/jupyterhub_disk.img
```

XFS is chosen for its performance, scalability, and support for project-based quotas.

### 3.4 — Mount the image

```bash
mkdir -p /jupyterhub
mount -o loop /jupyter/jupyterhub_disk.img /jupyterhub
```

The `loop` option tells the kernel to attach a loop device to the image file before mounting.

### 3.5 — Set permissions and SELinux context

```bash
chmod 775 /jupyterhub
chown root:root /jupyterhub
chcon -Rt svirt_sandbox_file_t /jupyterhub
```

The `chcon` command sets the SELinux label that allows Docker containers to read/write this path. Without it, containers will get permission-denied errors even if the UNIX permissions are correct.

### 3.6 — Make the mount persistent across reboots

```bash
echo "/jupyter/jupyterhub_disk.img  /jupyterhub  xfs  loop,defaults  0 0" >> /etc/fstab
```

This ensures the loopback image is remounted automatically on every boot.

### 3.7 — Verify

```bash
df -h /jupyterhub
```

You should see the 5 TB XFS filesystem listed at `/jupyterhub`.

---

## Phase 4 — Build Images & Start JupyterHub

### 4.1 — Build the single-user images

Choose the image(s) that match your workload and build them before starting JupyterHub so they're available locally when the first user logs in.

**Base image** (scipy stack — no deep learning framework):

```bash
docker build -t custom-base:latest -f Dockerfile.base .
```

**PyTorch image** (CUDA 12):

```bash
docker build -t custom-torch:latest -f Dockerfile.torch .
```

Each user's Jupyter server runs inside whichever image is configured in `jupyterhub_config.py` via `c.DockerSpawner.image`.

### 4.2 — Review the Compose configuration

`docker-compose.yml` defines the JupyterHub service:

| Setting | Value | Purpose |
|---|---|---|
| Port | `8000:8000` | JupyterHub web UI / API |
| `jupyterhub_config.py` | bind-mounted read-only | Your hub configuration |
| `/var/run/docker.sock` | bind-mounted | Allows hub to spawn user containers |
| `jupyterhub_data` | named volume | Hub database and internal state |
| `/jupyterhub/data` | bind-mounted (shared) | User notebook files on the XFS volume |
| CPU limit | 2 cores / 1 reserved | Prevents hub from starving user containers |
| Memory limit | 4 GB / 2 GB reserved | Same |
| Network | `jupyterhub_network` (bridge) | Isolated network; user containers join the same network |

### 4.3 — Create the required data directory on the XFS volume

```bash
mkdir -p /jupyterhub/data
```

This is the directory bind-mounted into the hub container at `/jupyterhub/data`.

### 4.4 — Start JupyterHub

```bash
docker compose up -d --build
```

`--build` rebuilds `Dockerfile.hub` if it has changed. On the first run this will pull the base image and install the pip packages. The hub is then available at:

```
http://<your-server-ip>:8000
```

### 4.5 — Check logs

```bash
docker compose logs -f jupyterhub
```

### 4.6 — Stop JupyterHub

```bash
docker compose down
```

User data on `/jupyterhub/data` and the named `jupyterhub_data` volume are preserved across restarts.

---

## Quick-Reference Command Summary

```bash
# Phase 1 — Docker
dnf install -y dnf-plugins-core
dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

# Phase 2 — NVIDIA (Part A, then reboot, then Part B)
dnf install -y epel-release && /usr/bin/crb enable
dnf install -y gcc gcc-c++ make dkms kernel-devel-$(uname -r) kernel-headers-$(uname -r) elfutils-libelf-devel libglvnd-devel
dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo
dnf clean all && dnf makecache
dnf install -y nvidia-driver nvidia-driver-cuda && ldconfig
dkms install "nvidia/$(rpm -q --queryformat '%{VERSION}' nvidia-driver)"
reboot
# --- after reboot ---
nvidia-smi
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
  | tee /etc/yum.repos.d/nvidia-container-toolkit.repo
dnf install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker && systemctl restart docker

# Phase 3 — Storage
mkdir -p /jupyter
truncate -s 5000G /jupyter/jupyterhub_disk.img
mkfs.xfs /jupyter/jupyterhub_disk.img
mkdir -p /jupyterhub
mount -o loop /jupyter/jupyterhub_disk.img /jupyterhub
chmod 775 /jupyterhub && chown root:root /jupyterhub
chcon -Rt svirt_sandbox_file_t /jupyterhub
echo "/jupyter/jupyterhub_disk.img  /jupyterhub  xfs  loop,defaults  0 0" >> /etc/fstab

# Phase 4 — Images & Hub
docker build -t custom-base:latest -f Dockerfile.base .
mkdir -p /jupyterhub/data
docker compose up -d --build
```

---

## File Layout

```
.
├── Dockerfile.base          # Single-user notebook image (scipy stack)
├── Dockerfile.hub           # JupyterHub control plane image
├── docker-compose.yml       # Service definition
├── jupyterhub_config.py     # Hub configuration (you provide this)
└── install_jupyterhub.sh    # Automated installer (reference implementation)

/jupyter/
└── jupyterhub_disk.img      # Sparse XFS disk image (5 TB)

/jupyterhub/                 # Mount point for the XFS image
└── data/                    # User notebook files (bind-mounted into hub)
```
