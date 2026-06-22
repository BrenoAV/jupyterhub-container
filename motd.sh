#!/bin/bash

# Detect background: if COLORFGBG is set, use it; otherwise default to dark
_dark=1
if [ -n "$COLORFGBG" ]; then
    _bg="${COLORFGBG##*;}"
    [ "$_bg" -lt 8 ] 2>/dev/null && _dark=1 || _dark=0
fi

if [ "$_dark" = "1" ]; then
    _c="\033[0m"
    _b="\033[1m"
    _head="\033[1;96m"    # bright cyan
    _key="\033[1;92m"     # bright green
    _val="\033[0;37m"     # light gray
else
    _c="\033[0m"
    _b="\033[1m"
    _head="\033[1;34m"    # bold blue
    _key="\033[1;32m"     # bold green (dark)
    _val="\033[0;30m"     # black
fi

echo -e "${_b}${_head}Environment: ${IMAGE_FLAVOR:-Base}${_c}\n"

echo -e "${_key}🐍 python${_c}  ${_val}$(python --version 2>/dev/null)${_c}"

# Only show Torch/CUDA info if torch is actually installed
if python -c "import torch" &> /dev/null; then
    echo -e "${_key}🔥 torch${_c}   ${_val}$(python -c 'import torch; print(torch.__version__)')${_c}"
    echo -e "${_key}🖥️  cuda${_c}    ${_val}$(python -c 'import torch; print(torch.version.cuda if torch.cuda.is_available() else "CPU only")')${_c}"
fi

echo -e "${_key}⚡ uv${_c}      ${_val}$(uv --version 2>/dev/null || echo 'not found')${_c}"
echo -e "${_key}📦 conda${_c}   ${_val}$(conda --version 2>/dev/null || echo 'not found') (inactive)${_c}"
echo -e "${_key}🔒 venv${_c}    ${_val}$(python -c 'import venv; print("available")' 2>/dev/null || echo 'not found')${_c}"
echo -e ""

unset _c _b _head _key _val _dark _bg
