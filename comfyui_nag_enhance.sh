#!/usr/bin/env bash
set -euo pipefail

# Vast.ai ComfyUI-NAG Enhancement Script
# This script ADDS to Vast.ai's existing ComfyUI installation
# Run this as an on-start script with Vast.ai's ComfyUI template

LOG_DIR="/var/log/portal"
LOG_FILE="$LOG_DIR/comfyui_nag_enhance.log"
mkdir -p "$LOG_DIR"

log() {
  local timestamp
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED ==="

# Find ComfyUI directory (Vast.ai templates usually have it in /workspace)
COMFYUI_DIR=""
if [ -f "/workspace/ComfyUI/main.py" ]; then
  COMFYUI_DIR="/workspace/ComfyUI"
elif [ -f "/ComfyUI/main.py" ]; then
  COMFYUI_DIR="/ComfyUI"
else
  # Search for it
  COMFYUI_DIR=$(find / -name "main.py" -path "*/ComfyUI/*" -exec dirname {} \; 2>/dev/null | head -1)
fi

if [ -z "$COMFYUI_DIR" ]; then
  log "ERROR: Could not find ComfyUI directory"
  exit 1
fi

log "Found ComfyUI at: $COMFYUI_DIR"

# Install system dependencies if needed
log "Installing system dependencies"
apt-get update > /dev/null 2>&1 || true
apt-get install -y git wget curl > /dev/null 2>&1 || true

# Create models directories
log "Creating models directories"
mkdir -p /workspace/models/checkpoints
mkdir -p /workspace/models/vae

# Install Lustify model
cd /workspace/models/checkpoints
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  log "Downloading Lustify model..."
  wget -O lustifySDXLNSFW_oltINPAINTING.safetensors https://huggingface.co/lokCX/Lustify-SDXL-NSFW-INPAINTING/resolve/main/lustifySDXLNSFW_oltINPAINTING.safetensors
fi

# Install SDXL VAE
cd /workspace/models/vae  
if [ ! -f "sdxl_vae.safetensors" ]; then
  log "Downloading SDXL VAE..."
  wget -O sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors
fi

# Create symlink for models if needed
if [ ! -d "$COMFYUI_DIR/models" ]; then
  ln -s /workspace/models "$COMFYUI_DIR/models"
  log "Created models symlink"
fi

# Install custom nodes
log "Installing custom nodes"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"

cd "$CUSTOM_NODES_DIR"

# Install essential custom nodes
if [ ! -d "ComfyUI-Manager" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git
fi

if [ ! -d "ComfyUI-Impact-Pack" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
fi

if [ ! -d "ComfyUI_IPAdapter_plus" ]; then
  git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
fi

# Install and patch ComfyUI-NAG
log "Installing ComfyUI-NAG"
if [ ! -d "ComfyUI_NAG" ]; then
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  
  # Apply patches
  cd ComfyUI_NAG
  
  # Patch layers.py
  sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py
  
  # Patch model.py - remove Chroma imports and fix inheritance
  sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
  sed -i '/import.*Chroma/d' chroma/model.py || true
  sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py
  
  # Ensure Flux import
  if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
  fi
  
  cd "$CUSTOM_NODES_DIR"
fi

# Create __init__.py for custom_nodes directory
if [ ! -f "$CUSTOM_NODES_DIR/__init__.py" ]; then
  touch "$CUSTOM_NODES_DIR/__init__.py"
fi

log "=== ENHANCEMENT COMPLETED ==="
log "Models installed: Lustify, SDXL VAE"
log "Custom nodes installed: ComfyUI-Manager, Impact-Pack, IPAdapter, ComfyUI-NAG"
log "ComfyUI-NAG patched for Flux compatibility"

# Note: Vast.ai will handle starting ComfyUI automatically
# This script only enhances the existing installation
