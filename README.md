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
# 1. Enable required repositories
sudo dnf install -y epel-release
sudo /usr/bin/crb enable
sudo dnf config-manager --add-repo https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo

# 2. Clean and refresh
sudo dnf clean all && sudo dnf makecache

# 3. Install NVIDIA driver + nvidia-smi binary
sudo dnf install -y nvidia-driver nvidia-driver-cuda
sudo ldconfig

# 4. Reboot to load kernel modules
sudo reboot

# ── After reboot ──────────────────────────────────────────────────────────────

# 5. Verify driver is working
nvidia-smi

# 6. Add NVIDIA Container Toolkit repo and install
curl -s -L https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo | \
  sudo tee /etc/yum.repos.d/nvidia-container-toolkit.repo
sudo dnf install -y nvidia-container-toolkit

# 7. Configure Docker and restart
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# 8. Final verification — Docker can see the GPU
docker run --rm --gpus all nvidia/cuda:12.0-base-ubuntu22.04 nvidia-smi
```

### Step 3: Setup Quota-Limited Storage (Loopback Disk)
*Prevents JupyterHub from consuming the entire host OS drive by capping its data inside a 50GB virtual disk.*

```bash
# 1. Create and format a 50GB sparse file (takes up no space until filled)
sudo truncate -s 50G /jupyterhub_disk.img
sudo mkfs.xfs /jupyterhub_disk.img

# 2. Create the mount directory and mount the file
sudo mkdir -p /jupyterhub
sudo mount -o loop /jupyterhub_disk.img /jupyterhub

# 3. Set Docker ownership and SELinux contexts (prevents "Permission Denied" errors)
sudo chmod -R 775 /jupyterhub
sudo chown -R root:root /jupyterhub
sudo chcon -Rt svirt_sandbox_file_t /jupyterhub

# 4. Add to fstab to survive reboots
echo "/jupyterhub_disk.img  /jupyterhub  xfs  loop,defaults  0 0" | sudo tee -a /etc/fstab

# 5. Verify the 50GB mount is active
df -h /jupyterhub
```

### Step 4: Build the Single-User Images

```bash
docker build -t custom-scipy-uv:latest --build-arg BASE_IMAGE=jupyter/scipy-notebook:latest -f Dockerfile.singleuser .
docker build -t custom-pytorch-uv:cuda12-latest --build-arg BASE_IMAGE=quay.io/jupyter/pytorch-notebook:cuda12-latest -f Dockerfile.singleuser .
docker build -t custom-tensorflow-uv:cuda-latest --build-arg BASE_IMAGE=quay.io/jupyter/tensorflow-notebook:cuda-latest -f Dockerfile.singleuser .
```

### Step 5: Start the Hub!

```bash
docker compose up -d --build
```