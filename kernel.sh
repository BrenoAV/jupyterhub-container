##!/usr/bin/env bash
# =============================================================================
#  kernel.sh — Manage Jupyter kernels backed by a local .venv
#
#  To keep the environment activated in your terminal, SOURCE the script:
#    source kernel.sh --create <kernel-name> [display-name]
#    source kernel.sh --use <kernel-name>
#
#  To run normally:
#    ./kernel.sh --remove <kernel-name>
#    ./kernel.sh --list
# =============================================================================

# Detect if the script is being sourced
(return 0 2>/dev/null) && _SOURCED=true || _SOURCED=false

# Only apply strict modes if executed as a subshell to avoid closing the parent shell
if [[ "$_SOURCED" == false ]]; then
  set -euo pipefail
fi

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
log_step() { echo -e "${CYAN}  ▶  $1${RESET}"; }
log_ok()   { echo -e "${GREEN}  ✔  $1${RESET}"; }
log_info() { echo -e "${YELLOW}  ℹ  $1${RESET}"; }

# Safe exit function: Returns if sourced, exits if executed
quit() {
  [[ "$_SOURCED" == true ]] && return "$1" || exit "$1"
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  local SCRIPT_NAME
  SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
  echo -e ""
  echo -e "${BOLD}  Usage:${RESET}"
  echo -e "    source ${SCRIPT_NAME} --create <kernel-name> [display-name]"
  echo -e "    source ${SCRIPT_NAME} --use <kernel-name>"
  echo -e "    ${SCRIPT_NAME} --remove <kernel-name>"
  echo -e "    ${SCRIPT_NAME} --list"
  echo -e ""
  echo -e "${BOLD}  Examples:${RESET}"
  echo -e "    source ${SCRIPT_NAME} --create myenv"
  echo -e "    source ${SCRIPT_NAME} --use myenv"
  echo -e "    ${SCRIPT_NAME} --remove myenv"
  echo -e ""
  quit 1
}

# ── Subcommand: create ────────────────────────────────────────────────────────
cmd_create() {
  local KERNEL_NAME="${1:-}"
  local DISPLAY_NAME="${2:-$KERNEL_NAME}"

  if [[ -z "$KERNEL_NAME" ]]; then
    echo -e "${RED}  ✖  --create requires a kernel name.${RESET}" >&2
    usage
  fi

  # Dynamically generate the folder name based on the kernel name
  local VENV_DIR="$(pwd)/.${KERNEL_NAME}_venv"

  command -v python3 &>/dev/null || { echo -e "${RED}  ✖  'python3' not found.${RESET}" >&2; quit 1; }

  echo -e "\n${BOLD}  Creating kernel '${KERNEL_NAME}' → ${VENV_DIR}${RESET}\n"

  # Create venv
  if [[ -d "$VENV_DIR" ]]; then
    log_step "Environment folder already exists at ${VENV_DIR} — reusing."
  else
    log_step "Creating virtual environment at ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"
    log_ok "Environment created."
  fi

  # Activate venv
  log_step "Activating environment..."
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  log_ok "Environment activated. (Python: $(python3 --version))"

  # Install ipykernel
  log_step "Installing ipykernel into the environment..."
  pip install --no-cache-dir ipykernel
  log_ok "ipykernel installed."

  # Register kernel
  log_step "Registering kernel '${KERNEL_NAME}' (\"${DISPLAY_NAME}\")..."
  python -m ipykernel install \
    --user \
    --name         "$KERNEL_NAME" \
    --display-name "$DISPLAY_NAME"
  log_ok "Kernel registered."

  # Summary
  echo ""
  echo -e "${BOLD}  Done!${RESET}"
  echo -e "  venv dir   : ${VENV_DIR}"
  echo -e "  kernel name: ${KERNEL_NAME}"
  echo -e "  display    : ${DISPLAY_NAME}"
  echo ""
  
  if [[ "$_SOURCED" == true ]]; then
    echo -e "  ${GREEN}✔ The virtual environment is now actively running in your terminal.${RESET}"
    echo -e "  ${CYAN}# Deactivate when done:${RESET}"
    echo -e "    deactivate"
  else
    echo -e "  ${YELLOW}ℹ Because you executed this script normally, the venv is NOT active in your shell.${RESET}"
    echo -e "  ${CYAN}# To activate the environment manually, run:${RESET}"
    echo -e "    source ${VENV_DIR}/bin/activate"
  fi
  
  echo -e ""
  echo -e "  ${CYAN}# Remove this kernel later:${RESET}"
  echo -e "    ./$(basename "${BASH_SOURCE[0]:-$0}") --remove ${KERNEL_NAME}"
  echo -e ""
  echo -e "  ${YELLOW}   ℹ  Reload JupyterLab (F5) if it is already open.${RESET}\n"
}

# ── Subcommand: remove ────────────────────────────────────────────────────────
cmd_remove() {
  local KERNEL_NAME="${1:-}"

  if [[ -z "$KERNEL_NAME" ]]; then
    echo -e "${RED}  ✖  --remove requires a kernel name.${RESET}" >&2
    usage
  fi

  # Match the dynamically generated folder name
  local VENV_DIR="$(pwd)/.${KERNEL_NAME}_venv"

  echo -e "\n${BOLD}  Removing kernel '${KERNEL_NAME}'${RESET}\n"

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

  # Remove dynamic .venv if it exists
  if [[ -d "$VENV_DIR" ]]; then
    log_step "Removing environment folder at ${VENV_DIR}..."
    rm -rf "$VENV_DIR"
    log_ok "Environment folder removed."
  else
    log_info "No environment found at ${VENV_DIR} — skipping folder removal."
  fi

  echo ""
  echo -e "${BOLD}  Done!${RESET} Kernel '${KERNEL_NAME}' has been removed."
  echo -e "  ${YELLOW}   ℹ  Reload JupyterLab (F5) if it is already open.${RESET}\n"
}

# ── Subcommand: list ──────────────────────────────────────────────────────────
cmd_list() {
  echo -e "\n${BOLD}  Active Jupyter Kernels (System-wide):${RESET}"
  if command -v jupyter &>/dev/null; then
    jupyter kernelspec list
  else
    echo -e "  ${RED}✖ 'jupyter' command execution failed. Is it installed?${RESET}"
  fi

  echo -e "\n${BOLD}  Local Managed Venvs (Current Directory):${RESET}"
  local found=false
  # Using nullglob or simple loop check to see if any ./*_venv directories exist
  for dir in .[^.]*_venv; do
    if [[ -d "$dir" ]]; then
      local name="${dir#.*/.}"
      name="${name%_venv}"
      echo -e "    ${CYAN}•${RESET} ${BOLD}${name}${RESET} (${dir})"
      found=true
    fi
  done

  if [[ "$found" == false ]]; then
    echo -e "    No script-managed virtual environments discovered here."
  fi
  echo ""
}

# ── Subcommand: use ────────────────────────────────────────────────────────────
cmd_use() {
  local KERNEL_NAME="${1:-}"

  if [[ -z "$KERNEL_NAME" ]]; then
    echo -e "${RED}  ✖  --use requires a kernel name.${RESET}" >&2
    usage
  fi

  local VENV_DIR="$(pwd)/.${KERNEL_NAME}_venv"

  if [[ ! -d "$VENV_DIR" ]]; then
    echo -e "${RED}  ✖  No virtual environment found at ${VENV_DIR}${RESET}" >&2
    quit 1
  fi

  if [[ "$_SOURCED" == false ]]; then
    echo -e "\n${RED}  ✖  Shell environment context missing!${RESET}" >&2
    echo -e "     To activate this environment in your current terminal, you ${BOLD}MUST source${RESET} the script:" >&2
    echo -e "     ${GREEN}source $(basename "${BASH_SOURCE[0]:-$0}") --use ${KERNEL_NAME}${RESET}\n" >&2
    quit 1
  fi

  log_step "Activating environment for '${KERNEL_NAME}'..."
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  log_ok "Environment successfully activated! (Python: $(python3 --version))"
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then usage; fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  --create)           cmd_create "$@" ;;
  --remove)           cmd_remove "$@" ;;
  --list)             cmd_list "$@" ;;
  --use)              cmd_use "$@" ;;
  *)
    echo -e "${RED}  ✖  Unknown option '${SUBCOMMAND}'.${RESET}" >&2
    usage
    ;;
esac!/usr/bin/env bash
# =============================================================================
#  kernel.sh — Manage Jupyter kernels backed by a local .venv
#
#  To keep the environment activated in your terminal, SOURCE the script:
#    source kernel.sh --create <kernel-name> [display-name]
#
#  To run normally (will NOT activate in current shell):
#    ./kernel.sh --create <kernel-name> [display-name]
#    ./kernel.sh --delete <kernel-name>
# =============================================================================

# Detect if the script is being sourced
(return 0 2>/dev/null) && _SOURCED=true || _SOURCED=false

# Only apply strict modes if executed as a subshell to avoid closing the parent shell
if [[ "$_SOURCED" == false ]]; then
  set -euo pipefail
fi

# ── Colors ────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; CYAN='\033[0;36m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; RESET='\033[0m'
log_step() { echo -e "${CYAN}  ▶  $1${RESET}"; }
log_ok()   { echo -e "${GREEN}  ✔  $1${RESET}"; }
log_info() { echo -e "${YELLOW}  ℹ  $1${RESET}"; }

# Safe exit function: Returns if sourced, exits if executed
quit() {
  [[ "$_SOURCED" == true ]] && return "$1" || exit "$1"
}

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  local SCRIPT_NAME
  SCRIPT_NAME="$(basename "${BASH_SOURCE[0]:-$0}")"
  echo -e ""
  echo -e "${BOLD}  Usage:${RESET}"
  echo -e "    source ${SCRIPT_NAME} --create <kernel-name> [display-name]"
  echo -e "    ./${SCRIPT_NAME} --delete <kernel-name>"
  echo -e "    ./${SCRIPT_NAME} --remove <kernel-name>"
  echo -e ""
  echo -e "${BOLD}  Examples:${RESET}"
  echo -e "    source ${SCRIPT_NAME} --create myenv"
  echo -e "    source ${SCRIPT_NAME} --create myenv \"My Project (Python 3)\""
  echo -e "    ./${SCRIPT_NAME} --delete myenv"
  echo -e ""
  quit 1
}

# ── Subcommand: create ────────────────────────────────────────────────────────
cmd_create() {
  local KERNEL_NAME="${1:-}"
  local DISPLAY_NAME="${2:-$KERNEL_NAME}"

  if [[ -z "$KERNEL_NAME" ]]; then
    echo -e "${RED}  ✖  --create requires a kernel name.${RESET}" >&2
    usage
  fi

  # Dynamically generate the folder name based on the kernel name
  local VENV_DIR="$(pwd)/.${KERNEL_NAME}_venv"

  command -v python3 &>/dev/null || { echo -e "${RED}  ✖  'python3' not found.${RESET}" >&2; quit 1; }

  echo -e "\n${BOLD}  Creating kernel '${KERNEL_NAME}' → ${VENV_DIR}${RESET}\n"

  # Create venv
  if [[ -d "$VENV_DIR" ]]; then
    log_step "Environment folder already exists at ${VENV_DIR} — reusing."
  else
    log_step "Creating virtual environment at ${VENV_DIR}..."
    python3 -m venv "$VENV_DIR"
    log_ok "Environment created."
  fi

  # Activate venv
  log_step "Activating environment..."
  # shellcheck disable=SC1091
  source "$VENV_DIR/bin/activate"
  log_ok "Environment activated. (Python: $(python3 --version))"

  # Install ipykernel
  log_step "Installing ipykernel into the environment..."
  pip install --no-cache-dir ipykernel
  log_ok "ipykernel installed."

  # Register kernel
  log_step "Registering kernel '${KERNEL_NAME}' (\"${DISPLAY_NAME}\")..."
  python -m ipykernel install \
    --user \
    --name         "$KERNEL_NAME" \
    --display-name "$DISPLAY_NAME"
  log_ok "Kernel registered."

  # Summary
  echo ""
  echo -e "${BOLD}  Done!${RESET}"
  echo -e "  venv dir   : ${VENV_DIR}"
  echo -e "  kernel name: ${KERNEL_NAME}"
  echo -e "  display    : ${DISPLAY_NAME}"
  echo ""
  
  if [[ "$_SOURCED" == true ]]; then
    echo -e "  ${GREEN}✔ The virtual environment is now actively running in your terminal.${RESET}"
    echo -e "  ${CYAN}# Deactivate when done:${RESET}"
    echo -e "    deactivate"
  else
    echo -e "  ${YELLOW}ℹ Because you executed this script normally, the venv is NOT active in your shell.${RESET}"
    echo -e "  ${CYAN}# To activate the environment manually, run:${RESET}"
    echo -e "    source ${VENV_DIR}/bin/activate"
  fi
  
  echo -e ""
  echo -e "  ${CYAN}# Delete this kernel later:${RESET}"
  echo -e "    ./$(basename "${BASH_SOURCE[0]:-$0}") --delete ${KERNEL_NAME}"
  echo -e ""
  echo -e "  ${YELLOW}  ℹ  Reload JupyterLab (F5) if it is already open.${RESET}\n"
}

# ── Subcommand: delete ────────────────────────────────────────────────────────
cmd_delete() {
  local KERNEL_NAME="${1:-}"

  if [[ -z "$KERNEL_NAME" ]]; then
    echo -e "${RED}  ✖  --delete requires a kernel name.${RESET}" >&2
    usage
  fi

  # Match the dynamically generated folder name
  local VENV_DIR="$(pwd)/.${KERNEL_NAME}_venv"

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

  # Remove dynamic .venv if it exists
  if [[ -d "$VENV_DIR" ]]; then
    log_step "Removing environment folder at ${VENV_DIR}..."
    rm -rf "$VENV_DIR"
    log_ok "Environment folder removed."
  else
    log_info "No environment found at ${VENV_DIR} — skipping folder removal."
  fi

  echo ""
  echo -e "${BOLD}  Done!${RESET} Kernel '${KERNEL_NAME}' has been deleted."
  echo -e "  ${YELLOW}  ℹ  Reload JupyterLab (F5) if it is already open.${RESET}\n"
}

# ── Entrypoint ────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then usage; fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  --create)           cmd_create "$@" ;;
  --delete|--remove)  cmd_delete "$@" ;;
  *)
    echo -e "${RED}  ✖  Unknown option '${SUBCOMMAND}'.${RESET}" >&2
    usage
    ;;
esac
