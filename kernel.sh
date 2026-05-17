#!/usr/bin/env bash
# =============================================================================
#  kernel.sh — Manage Jupyter kernels backed by a local .venv
#
#  Usage:
#    kernel --create <kernel-name> [display-name]
#    kernel --delete <kernel-name>   (alias: --remove)
#
#  Examples:
#    kernel --create myenv
#    kernel --create myenv "My Project (Python 3)"
#    kernel --delete myenv
#    kernel --remove myenv
# =============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
log_step() { echo -e "${CYAN}  ▶  $1${RESET}"; }
log_ok()   { echo -e "${GREEN}  ✔  $1${RESET}"; }
log_info() { echo -e "${YELLOW}  ℹ  $1${RESET}"; }
die()      { echo -e "${RED}  ✖  $1${RESET}" >&2; exit 1; }

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  echo -e ""
  echo -e "${BOLD}  Usage:${RESET}"
  echo -e "    $(basename "$0") --create <kernel-name> [display-name]"
  echo -e "    $(basename "$0") --delete <kernel-name>"
  echo -e "    $(basename "$0") --remove <kernel-name>"
  echo -e ""
  echo -e "${BOLD}  Examples:${RESET}"
  echo -e "    $(basename "$0") --create myenv"
  echo -e "    $(basename "$0") --create myenv \"My Project (Python 3)\""
  echo -e "    $(basename "$0") --delete myenv"
  echo -e ""
  exit 1
}

# ── Subcommand: create ────────────────────────────────────────────────────────
cmd_create() {
  local KERNEL_NAME="${1:-}"
  local DISPLAY_NAME="${2:-$KERNEL_NAME}"
  local VENV_DIR="$(pwd)/.venv"

  [[ -z "$KERNEL_NAME" ]] && die "--create requires a kernel name." && usage

  command -v python3 &>/dev/null || die "'python3' not found."

  echo -e "\n${BOLD}  Creating kernel '${KERNEL_NAME}' → ${VENV_DIR}${RESET}\n"

  # Create venv
  if [[ -d "$VENV_DIR" ]]; then
    log_step ".venv already exists at ${VENV_DIR} — reusing."
  else
    log_step "Creating venv at ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"
    log_ok "venv created."
  fi

  # Activate venv
  log_step "Activating venv..."
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  log_ok "venv activated. (Python: $(python3 --version))"

  # Install ipykernel
  log_step "Installing ipykernel into the venv..."
  pip install --no-cache-dir ipykernel
  log_ok "ipykernel installed."

  # Register kernel
  log_step "Registering kernel '${KERNEL_NAME}' (\"${DISPLAY_NAME}\")..."
  python -m ipykernel install \
    --user \
    --name         "$KERNEL_NAME" \
    --display-name "$DISPLAY_NAME"
  log_ok "Kernel registered."

  # Deactivate venv
  deactivate
  log_ok "venv deactivated."

  # Summary
  echo ""
  echo -e "${BOLD}  Done!${RESET}"
  echo -e "  venv       : ${VENV_DIR}"
  echo -e "  kernel name: ${KERNEL_NAME}"
  echo -e "  display    : ${DISPLAY_NAME}"
  echo ""
  echo -e "${BOLD}  Quick reference:${RESET}"
  echo -e "  ${CYAN}# Install a package into the venv:${RESET}"
  echo -e "    source ${VENV_DIR}/bin/activate && pip install <package> && deactivate"
  echo -e ""
  echo -e "  ${CYAN}# Activate the venv manually:${RESET}"
  echo -e "    source ${VENV_DIR}/bin/activate"
  echo -e ""
  echo -e "  ${CYAN}# Deactivate when done:${RESET}"
  echo -e "    deactivate"
  echo -e ""
  echo -e "  ${CYAN}# Delete this kernel later:${RESET}"
  echo -e "    $(basename "$0") --delete ${KERNEL_NAME}"
  echo -e ""
  echo -e "  ${YELLOW}  ℹ  Reload JupyterLab (F5) if it is already open.${RESET}\n"
}

# ── Subcommand: delete ────────────────────────────────────────────────────────
cmd_delete() {
  local KERNEL_NAME="${1:-}"
  local VENV_DIR="$(pwd)/.venv"

  [[ -z "$KERNEL_NAME" ]] && die "--delete requires a kernel name." && usage

  echo -e "\n${BOLD}  Deleting kernel '${KERNEL_NAME}'${RESET}\n"

  # Unregister kernel from Jupyter
  local KERNEL_DIR
  KERNEL_DIR="$(jupyter --data-dir 2>/dev/null)/kernels/${KERNEL_NAME}"

  if [[ -d "$KERNEL_DIR" ]]; then
    log_step "Unregistering kernel '${KERNEL_NAME}' from Jupyter..."
    jupyter kernelspec remove -f "$KERNEL_NAME"
    log_ok "Kernel '${KERNEL_NAME}' unregistered."
  else
    log_info "Kernel '${KERNEL_NAME}' not found in Jupyter registry — skipping unregister."
  fi

  # Remove .venv if it exists in the current directory
  if [[ -d "$VENV_DIR" ]]; then
    log_step "Removing venv at ${VENV_DIR}..."
    rm -rf "$VENV_DIR"
    log_ok "venv removed."
  else
    log_info "No .venv found at ${VENV_DIR} — skipping venv removal."
  fi

  echo ""
  echo -e "${BOLD}  Done!${RESET} Kernel '${KERNEL_NAME}' has been deleted."
  echo -e "  ${YELLOW}  ℹ  Reload JupyterLab (F5) if it is already open.${RESET}\n"
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && usage

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  --create)           cmd_create "$@" ;;
  --delete|--remove)  cmd_delete "$@" ;;
  *)
    die "Unknown option '${SUBCOMMAND}'."
    usage
    ;;
esac
