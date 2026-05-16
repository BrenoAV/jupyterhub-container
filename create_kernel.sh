#!/usr/bin/env bash
# =============================================================================
#  create_kernel.sh — Create a .venv in the current directory and register
#                     it as a Jupyter kernel.
#
#  Usage: create_kernel.sh <kernel-name> [display-name]
#
#  Examples:
#    create_kernel.sh myenv
#    create_kernel.sh myenv "My Project (Python 3)"
#
#  The kernel will appear in JupyterLab's launcher under the given display
#  name (defaults to the kernel name if not provided).
# =============================================================================
set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; BOLD='\033[1m'; RESET='\033[0m'
log_step() { echo -e "${CYAN}  ▶  $1${RESET}"; }
log_ok()   { echo -e "${GREEN}  ✔  $1${RESET}"; }
die()      { echo -e "${RED}  ✖  $1${RESET}" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && die "Usage: $(basename "$0") <kernel-name> [display-name]"

KERNEL_NAME="$1"
DISPLAY_NAME="${2:-$KERNEL_NAME}"
VENV_DIR="$(pwd)/.venv"

# ── Sanity checks ─────────────────────────────────────────────────────────────
command -v python3 &>/dev/null || die "'python3' not found."

echo -e "\n${BOLD}  Creating kernel '${KERNEL_NAME}' → ${VENV_DIR}${RESET}\n"

# ── Create venv ───────────────────────────────────────────────────────────────
if [[ -d "$VENV_DIR" ]]; then
  log_step ".venv already exists at ${VENV_DIR} — reusing."
else
  log_step "Creating venv at ${VENV_DIR}..."
  python3 -m venv "$VENV_DIR"
  log_ok "venv created."
fi

# ── Install ipykernel ─────────────────────────────────────────────────────────
log_step "Installing ipykernel into the venv..."
"$VENV_DIR/bin/pip" install --no-cache-dir ipykernel
log_ok "ipykernel installed."

# ── Register kernel ───────────────────────────────────────────────────────────
log_step "Registering kernel '${KERNEL_NAME}' (\"${DISPLAY_NAME}\")..."
"$VENV_DIR/bin/python" -m ipykernel install \
  --user \
  --name        "$KERNEL_NAME" \
  --display-name "$DISPLAY_NAME"
log_ok "Kernel registered."

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}  Done!${RESET}"
echo -e "  venv       : ${VENV_DIR}"
echo -e "  kernel name: ${KERNEL_NAME}"
echo -e "  display    : ${DISPLAY_NAME}"
echo -e "  Reload JupyterLab (F5) if it is already open.\n"
