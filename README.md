# jupyterhub-container

### Step 1: Install Docker & Docker Compose on Rocky Linux 9

```bash
# 1. Add the Docker repository
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo

# 2. Install Docker and Docker Compose
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 3. Start Docker and enable it to run on boot
sudo systemctl enable --now docker

# 4. Add your user to the docker group so you don't need 'sudo' every time
sudo usermod -aG docker $USER
newgrp docker
```

### Step 2: Install the NVIDIA Container Toolkit (RHEL/Rocky 9)

```bash
# 1. Add the NVIDIA repository for RHEL/Rocky 9
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo

# 2. Install the toolkit
sudo dnf install -y nvidia-container-toolkit

# 3. Configure Docker to use it
sudo nvidia-ctk runtime configure --runtime=docker

# 4. Restart Docker to apply changes
sudo systemctl restart docker
```

### Step 3: Prepare the Dedicated Hard Drive for User Data
To protect the Rocky Linux OS drive, format the empty extra disk and mount it for JupyterHub users.

```bash
# 1. Verify your empty drive name (Assuming /dev/sdb here)
lsblk

# 2. Format the drive to XFS
sudo mkfs.xfs /dev/sdb

# 3. Create the directory and mount the drive
sudo mkdir -p /jupyterhub/data
sudo mount /dev/sdb /jupyterhub/data

# 4. Find the UUID to make the mount permanent
sudo blkid /dev/sdb

# 5. Edit fstab to mount on reboot
sudo nano /etc/fstab
# Add this line to the bottom (Replace YOUR-UUID):
# UUID=YOUR-UUID   /jupyterhub/data   xfs   defaults   0 0
```

### Step 4: Create your Project Folder and Files

Create a new directory for your server and create the 4 required files. 

```bash
mkdir ~/jupyterhub
cd ~/jupyterhub
```

**1. `Dockerfile.hub`**

```dockerfile
FROM jupyterhub/jupyterhub:latest

# Added jupyterhub-idle-culler to the pip install list
RUN pip install --no-cache-dir \
    dockerspawner \
    jupyterhub-nativeauthenticator \
    docker \
    jupyterhub-idle-culler
```

**2. `Dockerfile.singleuser`**

```dockerfile
ARG BASE_IMAGE=jupyter/scipy-notebook:latest
FROM ${BASE_IMAGE}

USER root
RUN apt-get update && apt-get install -y tmux && rm -rf /var/lib/apt/lists/*

# 1. Copy uv binaries to a standard path
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 2. Use uv to install the extensions
# Note: --system is correct here since we want to install into the system python
RUN uv pip install --no-cache --system \
    jupyter-scheduler \
    jupyter-resource-usage \
    jupyterlab-nvdashboard

USER ${NB_UID}
```

**3. `docker-compose.yml`**

```yaml
services:
  jupyterhub:
    build:
      context: .
      dockerfile: Dockerfile.hub
    container_name: jupyterhub
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      - ./jupyterhub_config.py:/srv/jupyterhub/jupyterhub_config.py:ro
      - /var/run/docker.sock:/var/run/docker.sock
      - jupyterhub_data:/srv/jupyterhub/data
    environment:
      - DOCKER_NETWORK_NAME=jupyterhub_network
    networks:
      - jupyterhub_network
    deploy:
      resources:
        limits:
          cpus: '2.4'  # 4 cores * 60% = 2.4
          memory: 16G
        reservations:
          cpus: '0.5'
          memory: 2G

volumes:
  jupyterhub_data:

networks:
  jupyterhub_network:
    name: jupyterhub_network
    driver: bridge
```

**4. `jupyterhub_config.py`**

```python
import os
import docker

# ── Authenticator ─────────────────────────────────────────────────────────────
c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'
c.Authenticator.admin_users = {"admin"}
c.Authenticator.allow_all = True
c.NativeAuthenticator.open_signup = False

# ── Server & Resource Limits ──────────────────────────────────────────────────
c.JupyterHub.active_server_limit = 3
c.JupyterHub.shutdown_on_logout = True

c.DockerSpawner.mem_limit = "6G"
c.DockerSpawner.cpu_limit = 2.0
c.DockerSpawner.args = [
    "--ResourceUseDisplay.track_cpu_percent=True",
    "--ResourceUseDisplay.track_disk_usage=True"
]

# ── COMBINED PRE-SPAWN HOOK (GPU + Folder Creation) ───────────────────────────
def pre_spawn_hook(spawner):
    # 1. GPU Assignment
    user_groups = [g.name for g in spawner.user.groups]
    new_host_config = {}

    if "gpu_users" in user_groups:
        new_host_config["device_requests"] = [
            docker.types.DeviceRequest(count=-1, capabilities=[["gpu"]])
        ]
        spawner.environment.update({"GPU_ENABLED": "True"})
    else:
        new_host_config["device_requests"] = []
        spawner.environment.update({"GPU_ENABLED": "False"})

    spawner.extra_host_config = new_host_config

    # 2. Folder Creation on the Host Partition
    username = spawner.user.name
    host_path = f"/jupyterhub/data/{username}"

    if not os.path.exists(host_path):
        os.makedirs(host_path, mode=0o755, exist_ok=True)
        # Give jovyan (UID 1000) ownership so Jupyter can write to it
        os.chown(host_path, 1000, 100)

c.Spawner.pre_spawn_hook = pre_spawn_hook

# ── Idle Culling Configuration ────────────────────────────────────────────────
c.JupyterHub.services = [
    {
        "name": "idle-culler",
        "admin": True,
        "command": [
            "python3",
            "-m",
            "jupyterhub_idle_culler",
            "--timeout=120",
            "--cull-every=10",
        ],
    }
]

# ── Spawner ───────────────────────────────────────────────────────────────────
c.JupyterHub.spawner_class = "dockerspawner.DockerSpawner"
c.DockerSpawner.allowed_images = {
    "Data Science (CPU Only)": "custom-scipy-uv:latest",
    "PyTorch Deep Learning (GPU)": "custom-pytorch-uv:latest",
    "TensorFlow Deep Learning (GPU)": "custom-tensorflow-uv:latest"
}

# ── Volumes ───────────────────────────────────────────────────────────────────
c.DockerSpawner.notebook_dir = "/home/jovyan"
# Capital 'Z' is strictly required for Rocky Linux / SELinux private container mounts
c.DockerSpawner.volumes = {
    "/jupyterhub/data/{username}": {"bind": "/home/jovyan", "mode": "rw,Z"}
}

# ── Networking ────────────────────────────────────────────────────────────────
c.DockerSpawner.network_name = os.environ.get("DOCKER_NETWORK_NAME", "jupyterhub_network")
c.DockerSpawner.use_internal_ip = True
c.JupyterHub.hub_ip = "0.0.0.0"
c.JupyterHub.hub_connect_ip = "jupyterhub"

# ── Timeouts & Cleanup ────────────────────────────────────────────────────────
c.DockerSpawner.remove = True
c.Spawner.default_url = "/lab"
c.Spawner.http_timeout = 120
c.Spawner.start_timeout = 300
```

### Step 5: Build the Single-User Images

```bash
docker build -t custom-scipy-uv:latest --build-arg BASE_IMAGE=jupyter/scipy-notebook:latest -f Dockerfile.singleuser .
docker build -t custom-pytorch-uv:latest --build-arg BASE_IMAGE=quay.io/jupyter/pytorch-notebook:cuda12-latest -f Dockerfile.singleuser .
docker build -t custom-tensorflow-uv:latest --build-arg BASE_IMAGE=quay.io/jupyter/tensorflow-notebook:cuda-latest -f Dockerfile.singleuser .
```

### Step 6: Start the Hub!

```bash
docker compose up -d --build
```

### Step 7: Test it out

1. Open your browser and go to `http://<YOUR-ROCKY-LINUX-SERVER-IP>:8000` *(Ensure port 8000 is open in your server's firewall).*
2. Click **Sign Up**, create a user named `admin` with a password.
3. Log in with `admin`.
4. Choose the **PyTorch Deep Learning (GPU)** profile from the menu.
5. Open a notebook and run `!nvidia-smi`. You will see your GPU passed through directly from your Rocky Linux host into your Jupyter environment!
6. Open your server terminal and run `ls -la /jupyterhub/data/admin` to confirm your persistent volume is safely storing data on your dedicated drive.