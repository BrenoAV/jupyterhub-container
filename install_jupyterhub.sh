#!/usr/bin/env bash
# =============================================================================
#  JupyterHub Container Installer — Rocky Linux 9
#  Installs: Docker, NVIDIA Container Toolkit, Quota Storage, builds images,
#            and starts the JupyterHub stack.
# =============================================================================
set -euo pipefail

# ── Colors & Formatting ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── Logging helpers ───────────────────────────────────────────────────────────
log_section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}"; \
                echo -e "${BOLD}${BLUE}  $1${RESET}"; \
                echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${RESET}\n"; }
log_step()    { echo -e "${CYAN}  ▶  $1${RESET}"; }
log_ok()      { echo -e "${GREEN}  ✔  $1${RESET}"; }
log_warn()    { echo -e "${YELLOW}  ⚠  $1${RESET}"; }
log_error()   { echo -e "${RED}  ✖  $1${RESET}" >&2; }
die()         { log_error "$1"; exit 1; }

# ── Configuration (edit these before running) ─────────────────────────────────
DISK_IMAGE="/jupyterhub_disk.img"
MOUNT_POINT="/jupyterhub"
DISK_SIZE="50G"

IMAGES=(
  "custom-tiny-base:latest|--build-arg BASE_IMAGE=quay.io/jupyter/minimal-notebook:latest -f Dockerfile.tiny_base ."
  "custom-lsd-env:cuda12.8|-f Dockerfile.lsd ."
  "custom-pytorch-cv:cuda12|-f Dockerfile.pytorch_cv ."
  "custom-yolo-sam:cuda12|-f Dockerfile.yolo_sam ."
)

# ── Guards ────────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run this script as root (or with sudo)."
grep -qi 'rocky' /etc/os-release 2>/dev/null || \
  log_warn "This script targets Rocky Linux 9 — proceeding anyway."

# ── Step selector ─────────────────────────────────────────────────────────────
STEPS="${1:-all}"   # pass: all | docker | nvidia | storage | images | hub
                    # e.g.: sudo ./install_jupyterhub.sh nvidia

# =============================================================================
#  STEP 1 — Docker & Docker Compose
# =============================================================================
step_docker() {
  log_section "Step 1 · Install Docker & Docker Compose"

  log_step "Installing dnf-plugins-core..."
  dnf install -y dnf-plugins-core

  log_step "Adding Docker CE repository..."
  dnf config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

  log_step "Installing Docker CE, CLI, containerd, buildx, and compose plugin..."
  dnf install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  log_step "Enabling and starting Docker service..."
  systemctl enable --now docker
  log_ok "Docker service is active."

  # Add the *invoking* user (not root) to the docker group
  REAL_USER="${SUDO_USER:-$USER}"
  if [[ "$REAL_USER" != "root" ]]; then
    log_step "Adding '${REAL_USER}' to the docker group..."
    usermod -aG docker "$REAL_USER"
    log_warn "Log out and back in (or run 'newgrp docker') for group membership to take effect."
  fi

  log_ok "Docker installation complete."
}

# =============================================================================
#  STEP 2 — NVIDIA Container Toolkit
#  NOTE: This step installs the driver and will REBOOT the server.
#        Re-run with 'nvidia_post' after reboot to complete the toolkit setup.
# =============================================================================
step_nvidia_pre() {
  log_section "Step 2a · NVIDIA Driver (pre-reboot)"

  log_step "Installing EPEL and enabling CRB..."
  dnf install -y epel-release
  /usr/bin/crb enable

  log_step "Adding CUDA repository..."
  dnf config-manager --add-repo \
    https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo

  log_step "Cleaning DNF cache and refreshing metadata..."
  dnf clean all && dnf makecache

  log_step "Installing nvidia-driver and nvidia-driver-cuda..."
  dnf install -y nvidia-driver nvidia-driver-cuda
  ldconfig

  log_warn "A reboot is required to load the NVIDIA kernel modules."
  log_warn "After reboot, re-run this script with the 'nvidia_post' argument:"
  log_warn "  sudo $0 nvidia_post"
  echo ""
  read -rp "  Reboot now? [y/N]: " REBOOT_NOW
  if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
    log_step "Rebooting..."
    reboot
  fi
}

step_nvidia_post() {
  log_section "Step 2b · NVIDIA Container Toolkit (post-reboot)"

  log_step "Verifying NVIDIA driver with nvidia-smi..."
  if ! nvidia-smi; then
    die "nvidia-smi failed — ensure the driver was installed and the system was rebooted."
  fi
  log_ok "NVIDIA driver is working."

  log_step "Adding NVIDIA Container Toolkit repository..."
  curl -fsSL \
    https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    | tee /etc/yum.repos.d/nvidia-container-toolkit.repo > /dev/null

  log_step "Installing nvidia-container-toolkit..."
  dnf install -y nvidia-container-toolkit

  log_step "Configuring Docker runtime for NVIDIA..."
  nvidia-ctk runtime configure --runtime=docker

  log_step "Restarting Docker service..."
  systemctl restart docker
  log_ok "NVIDIA Container Toolkit setup complete."
}

# =============================================================================
#  STEP 3 — Quota-Limited Loopback Storage
# =============================================================================
step_storage() {
  log_section "Step 3 · Setup Quota-Limited Storage (${DISK_SIZE} loopback disk)"

  if mountpoint -q "$MOUNT_POINT"; then
    log_warn "${MOUNT_POINT} is already mounted — skipping disk creation."
  else
    if [[ -f "$DISK_IMAGE" ]]; then
      log_warn "Disk image ${DISK_IMAGE} already exists — skipping truncate/mkfs."
    else
      log_step "Creating ${DISK_SIZE} sparse disk image at ${DISK_IMAGE}..."
      truncate -s "$DISK_SIZE" "$DISK_IMAGE"

      log_step "Formatting as XFS..."
      mkfs.xfs "$DISK_IMAGE"
    fi

    log_step "Creating mount point ${MOUNT_POINT}..."
    mkdir -p "$MOUNT_POINT"

    log_step "Mounting loopback image..."
    mount -o loop "$DISK_IMAGE" "$MOUNT_POINT"
  fi

  log_step "Setting permissions and SELinux context..."
  chmod -R 775 "$MOUNT_POINT"
  chown -R root:root "$MOUNT_POINT"
  # Apply SELinux label so Docker containers can access the path
  if command -v chcon &>/dev/null; then
    chcon -Rt svirt_sandbox_file_t "$MOUNT_POINT"
  fi

  FSTAB_ENTRY="${DISK_IMAGE}  ${MOUNT_POINT}  xfs  loop,defaults  0 0"
  if grep -qF "$DISK_IMAGE" /etc/fstab; then
    log_warn "fstab entry already present — skipping."
  else
    log_step "Adding fstab entry for persistence across reboots..."
    echo "$FSTAB_ENTRY" | tee -a /etc/fstab > /dev/null
  fi

  log_ok "Loopback storage mounted:"
  df -h "$MOUNT_POINT"
}

# =============================================================================
#  STEP 4 — Build Single-User Docker Images
# =============================================================================
step_images() {
  log_section "Step 4 · Build Single-User Images"

  for entry in "${IMAGES[@]}"; do
    TAG="${entry%%|*}"
    BUILD_ARGS="${entry##*|}"
    DOCKERFILE=$(echo "$BUILD_ARGS" | grep -oP '(?<=-f )\S+')

    if [[ ! -f "$DOCKERFILE" ]]; then
      log_warn "Dockerfile not found: ${DOCKERFILE} — skipping ${TAG}"
      continue
    fi

    log_step "Building image: ${BOLD}${TAG}${RESET}${CYAN} (${DOCKERFILE})..."
    # shellcheck disable=SC2086
    docker build -t "$TAG" $BUILD_ARGS
    log_ok "Built: ${TAG}"
  done

  log_ok "All available images built."
}

# =============================================================================
#  Entrypoint — dispatch based on argument
# =============================================================================
echo -e "\n${BOLD}${CYAN}  JupyterHub Container Installer — Rocky Linux 9${RESET}\n"

case "$STEPS" in
  all)
    step_docker
    step_nvidia_pre   # will prompt for reboot; use nvidia_post after
    ;;
  docker)       step_docker ;;
  nvidia)       step_nvidia_pre ;;
  nvidia_post)  step_nvidia_post ;;
  storage)      step_storage ;;
  images)       step_images ;;
  full_post)
    # Run everything that's safe after reboot (no driver install, no reboot prompt)
    step_nvidia_post
    step_storage
    step_images
    ;;
  *)
    echo "Usage: sudo $0 [all|docker|nvidia|nvidia_post|storage|images|full_post]"
    echo ""
    echo "  all          — Steps 1 + 2a (installs Docker then NVIDIA driver; prompts reboot)"
    echo "  docker       — Step 1 only  (Docker & Compose)"
    echo "  nvidia       — Step 2a only (NVIDIA driver; prompts reboot)"
    echo "  nvidia_post  — Step 2b only (NVIDIA toolkit, post-reboot)"
    echo "  storage      — Step 3 only  (loopback disk)"
    echo "  images       — Step 4 only  (build Docker images)"
    echo "  full_post    — Steps 2b+3+4 (everything after first reboot)"
    exit 1
    ;;
esac

echo -e "\n${BOLD}${GREEN}  Done!${RESET}\n"
