#!/usr/bin/env bash
# =============================================================================
#  JupyterHub Container Installer — Rocky Linux 9
#  Usage: sudo ./install_jupyterhub.sh [docker|nvidia|disk|images]
# =============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── Logging ───────────────────────────────────────────────────────────────────
log_section() {
  echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════${RESET}"
  echo -e "${BOLD}${BLUE}  $1${RESET}"
  echo -e "${BOLD}${BLUE}══════════════════════════════════════════${RESET}\n"
}
log_step()  { echo -e "${CYAN}  ▶  $1${RESET}"; }
log_ok()    { echo -e "${GREEN}  ✔  $1${RESET}"; }
log_warn()  { echo -e "${YELLOW}  ⚠  $1${RESET}"; }
log_error() { echo -e "${RED}  ✖  $1${RESET}" >&2; }
die()       { log_error "$1"; exit 1; }

# ── Configuration ─────────────────────────────────────────────────────────────
DISK_IMAGE="/jupyterhub_disk.img"
MOUNT_POINT="/jupyterhub"
DISK_SIZE="50G"


IMAGES=(
  "custom-tiny-base:latest|--build-arg BASE_IMAGE=quay.io/jupyter/minimal-notebook:latest -f Dockerfile.tiny_base ."
)

# ── Guards ────────────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Run this script as root (or with sudo)."
grep -qi 'rocky' /etc/os-release 2>/dev/null || \
  log_warn "This script targets Rocky Linux 9 — proceeding anyway."

# =============================================================================
#  DOCKER — Install Docker CE & Docker Compose plugin
# =============================================================================
step_docker() {
  log_section "Docker · Install Docker CE & Compose"

  log_step "Installing dnf-plugins-core..."
  dnf install -y dnf-plugins-core

  log_step "Adding Docker CE repository..."
  dnf config-manager --add-repo \
    https://download.docker.com/linux/centos/docker-ce.repo

  log_step "Installing Docker CE, CLI, containerd, buildx, and compose plugin..."
  dnf install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  log_step "Enabling and starting Docker..."
  systemctl enable --now docker
  log_ok "Docker service is active."

  REAL_USER="${SUDO_USER:-$USER}"
  if [[ "$REAL_USER" != "root" ]]; then
    log_step "Adding '${REAL_USER}' to the docker group..."
    usermod -aG docker "$REAL_USER"
    log_warn "Log out and back in (or run 'newgrp docker') for the group change to take effect."
  fi

  log_ok "Docker installation complete."
}

# =============================================================================
#  NVIDIA — Install driver from CUDA repo + Container Toolkit
#
#  Two-phase process:
#    Phase 1 (nvidia):      adds CUDA repo, installs nvidia-driver +
#                           nvidia-driver-cuda, then prompts for reboot.
#    Phase 2 (nvidia_post): verifies driver, installs Container Toolkit,
#                           configures Docker runtime.
# =============================================================================
step_nvidia() {
  log_section "NVIDIA · Driver install from CUDA repo"

  log_step "Installing EPEL and enabling CRB..."
  dnf install -y epel-release
  /usr/bin/crb enable

  log_step "Installing required build libraries and tools..."
  dnf install -y \
    gcc \
    gcc-c++ \
    make \
    git \
    perl \
    python3 \
    python3-pip \
    curl \
    wget \
    tar \
    bzip2 \
    which \
    pciutils \
    pkg-config \
    elfutils-libelf-devel \
    libglvnd-devel \
    dkms \
    kernel-devel-$(uname -r) \
    kernel-headers-$(uname -r)

  log_step "Adding CUDA repository..."
  dnf config-manager --add-repo \
    https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo

  log_step "Cleaning DNF cache and refreshing metadata..."
  dnf clean all && dnf makecache

  log_step "Installing nvidia-driver and nvidia-driver-cuda..."
  dnf install -y nvidia-driver nvidia-driver-cuda
  ldconfig

  log_step "Detecting installed NVIDIA driver version for DKMS..."
  NVIDIA_DKMS_VERSION=$(dkms status | grep -oP '^nvidia/\K[^,]+' | head -1)
  if [[ -z "$NVIDIA_DKMS_VERSION" ]]; then
    # Fallback: read version from the installed RPM
    NVIDIA_DKMS_VERSION=$(rpm -q --queryformat '%{VERSION}' nvidia-driver 2>/dev/null | head -1)
  fi
  [[ -n "$NVIDIA_DKMS_VERSION" ]] || die "Could not detect NVIDIA driver version for DKMS."
  log_step "Running: dkms install nvidia/${NVIDIA_DKMS_VERSION}..."
  dkms install "nvidia/${NVIDIA_DKMS_VERSION}"

  log_ok "NVIDIA driver installed and DKMS module built (nvidia/${NVIDIA_DKMS_VERSION})."
  log_warn "A reboot is required to load the NVIDIA kernel modules."
  log_warn "After reboot, run:  sudo $0 nvidia_post"
  echo ""
  read -rp "  Reboot now? [y/N]: " REBOOT_NOW
  if [[ "$REBOOT_NOW" =~ ^[Yy]$ ]]; then
    reboot
  fi
}

step_nvidia_post() {
  log_section "NVIDIA · Container Toolkit (post-reboot)"

  log_step "Verifying NVIDIA driver..."
  if ! nvidia-smi; then
    die "nvidia-smi failed — ensure the driver is installed and the system was rebooted."
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

  log_step "Restarting Docker..."
  systemctl restart docker

  log_ok "NVIDIA Container Toolkit configured."
}

# =============================================================================
#  DISK — Create & mount a quota-limited loopback XFS disk
# =============================================================================
step_disk() {
  log_section "Disk · Loopback XFS Storage (${DISK_SIZE})"

  if mountpoint -q "$MOUNT_POINT"; then
    log_warn "${MOUNT_POINT} is already mounted — skipping."
  else
    if [[ ! -f "$DISK_IMAGE" ]]; then
      log_step "Creating ${DISK_SIZE} sparse image at ${DISK_IMAGE}..."
      truncate -s "$DISK_SIZE" "$DISK_IMAGE"

      log_step "Formatting as XFS..."
      mkfs.xfs "$DISK_IMAGE"
    else
      log_warn "Image ${DISK_IMAGE} already exists — skipping truncate/mkfs."
    fi

    log_step "Creating mount point ${MOUNT_POINT} and mounting..."
    mkdir -p "$MOUNT_POINT"
    mount -o loop "$DISK_IMAGE" "$MOUNT_POINT"
  fi

  log_step "Setting permissions and SELinux context..."
  chmod 775 "$MOUNT_POINT"
  chown root:root "$MOUNT_POINT"
  command -v chcon &>/dev/null && chcon -Rt svirt_sandbox_file_t "$MOUNT_POINT"

  if grep -qF "$DISK_IMAGE" /etc/fstab; then
    log_warn "fstab entry already present — skipping."
  else
    log_step "Adding fstab entry for persistence..."
    echo "${DISK_IMAGE}  ${MOUNT_POINT}  xfs  loop,defaults  0 0" >> /etc/fstab
  fi

  log_ok "Storage ready:"
  df -h "$MOUNT_POINT"
}

# =============================================================================
#  IMAGES — Build single-user Docker images
# =============================================================================
step_images() {
  log_section "Images · Build Single-User Docker Images"

  for entry in "${IMAGES[@]}"; do
    TAG="${entry%%|*}"
    BUILD_ARGS="${entry##*|}"
    DOCKERFILE=$(echo "$BUILD_ARGS" | grep -oP '(?<=-f )\S+')

    if [[ ! -f "$DOCKERFILE" ]]; then
      log_warn "Dockerfile not found: ${DOCKERFILE} — skipping ${TAG}"
      continue
    fi

    log_step "Building ${BOLD}${TAG}${RESET}${CYAN} (${DOCKERFILE})..."
    # shellcheck disable=SC2086
    docker build -t "$TAG" $BUILD_ARGS
    log_ok "Built: ${TAG}"
  done

  log_ok "All available images built."
}

# =============================================================================
#  Entrypoint
# =============================================================================
echo -e "\n${BOLD}${CYAN}  JupyterHub Installer — Rocky Linux 9${RESET}\n"

STEP="${1:-}"

case "$STEP" in
  docker)       step_docker ;;
  nvidia)       step_nvidia ;;
  nvidia_post)  step_nvidia_post ;;
  disk)         step_disk ;;
  images)       step_images ;;
  *)
    echo -e "Usage: sudo $0 [docker|nvidia|nvidia_post|disk|images]\n"
    echo "  docker       — Install Docker CE & Compose plugin"
    echo "  nvidia       — Install NVIDIA driver via DKMS (prompts for reboot)"
    echo "  nvidia_post  — Install NVIDIA Container Toolkit (run after reboot)"
    echo "  disk         — Create & mount loopback XFS storage"
    echo "  images       — Build single-user Docker images"
    exit 1
    ;;
esac

echo -e "\n${BOLD}${GREEN}  Done!${RESET}\n"