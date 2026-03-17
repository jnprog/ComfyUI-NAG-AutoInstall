#!/usr/bin/env bash
set -euo pipefail

# Vast.ai ComfyUI-NAG Enhancement Script with Real-Time Progress
LOG_DIR="/var/log/portal"
LOG_FILE="$LOG_DIR/comfyui_nag_enhance.log"
mkdir -p "$LOG_DIR"

log() {
  local timestamp
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}
# Add this function for authenticated downloads
download_with_hf_token() {
  local url="$1"
  local output="$2"
  local description="$3"
  local hf_token="$4"
  
  log "Starting authenticated download: $description"
  log "URL: $url"
  
  wget --progress=dot:mega \
    --header="Authorization: Bearer $hf_token" \
    -O "$output" "$url" 2>&1 | while read line; do
    if [[ "$line" == *[0-9]*"."[0-9]*"%"* ]]; then
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] DOWNLOAD PROGRESS: $line" | tee -a "$LOG_FILE"
    elif [[ "$line" == *"saved"* ]]; then
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] DOWNLOAD COMPLETE: $line" | tee -a "$LOG_FILE"
    else
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WGET: $line" >> "$LOG_FILE"
    fi
  done
}

# In your main script, replace the Lustify download with:
HF_TOKEN="YOUR_HUGGINGFACE_TOKEN_HERE"  # You'll need to set this

if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  download_with_hf_token \
    "https://huggingface.co/lokCX/Lustify-SDXL-NSFW-INPAINTING/resolve/main/lustifySDXLNSFW_oltINPAINTING.safetensors" \
    "lustifySDXLNSFW_oltINPAINTING.safetensors" \
    "Lustify SDXL NSFW Inpainting Model" \
    "$HF_TOKEN"
fi
# Function to download with progress
download_with_progress() {
  local url="$1"
  local output="$2"
  local description="$3"
  
  log "Starting download: $description"
  log "URL: $url"
  log "Output: $output"
  
  # Use wget with progress bar and log to file
  wget --progress=dot:mega -O "$output" "$url" 2>&1 | while read line; do
    if [[ "$line" == *[0-9]*"."[0-9]*"%"* ]]; then
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] DOWNLOAD PROGRESS: $line" | tee -a "$LOG_FILE"
    elif [[ "$line" == *"saved"* ]]; then
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] DOWNLOAD COMPLETE: $line" | tee -a "$LOG_FILE"
    else
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] WGET: $line" >> "$LOG_FILE"
    fi
  done
  
  log "Download completed: $description"
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED ==="

# Find ComfyUI directory - Vast.ai templates vary
COMFYUI_DIR=""
if [ -d "/ComfyUI" ] && [ -f "/ComfyUI/main.py" ]; then
  COMFYUI_DIR="/ComfyUI"
  log "Found ComfyUI at: /ComfyUI"
elif [ -d "/workspace/ComfyUI" ] && [ -f "/workspace/ComfyUI/main.py" ]; then
  COMFYUI_DIR="/workspace/ComfyUI"
  log "Found ComfyUI at: /workspace/ComfyUI"
else
  # Search for it
  COMFYUI_DIR=$(find / -name "main.py" -path "*/ComfyUI/*" -exec dirname {} \; 2>/dev/null | head -1)
  if [ -z "$COMFYUI_DIR" ]; then
    log "ERROR: Could not find ComfyUI directory"
    exit 1
  else
    log "Found ComfyUI at: $COMFYUI_DIR"
  fi
fi

# Install system dependencies if needed
log "Installing system dependencies"
apt-get update > /dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y git wget curl > /dev/null 2>&1 || true

# Create workspace directory structure
log "Creating workspace directory structure"
mkdir -p /workspace/models/checkpoints
mkdir -p /workspace/models/vae
mkdir -p /workspace/models

# Install Lustify model with progress
cd /workspace/models/checkpoints
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  download_with_progress \
    "https://huggingface.co/lokCX/Lustify-SDXL-NSFW-INPAINTING/resolve/main/lustifySDXLNSFW_oltINPAINTING.safetensors" \
    "lustifySDXLNSFW_oltINPAINTING.safetensors" \
    "Lustify SDXL NSFW Inpainting Model"
else
  log "Lustify model already exists - skipping download"
fi

# Install SDXL VAE with progress
cd /workspace/models/vae  
if [ ! -f "sdxl_vae.safetensors" ]; then
  download_with_progress \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
    "sdxl_vae.safetensors" \
    "SDXL VAE Model"
else
  log "SDXL VAE already exists - skipping download"
fi

# Create symlink for models if ComfyUI doesn't have models directory
if [ ! -d "$COMFYUI_DIR/models" ]; then
  log "Creating models symlink from $COMFYUI_DIR/models to /workspace/models"
  ln -sfn /workspace/models "$COMFYUI_DIR/models"
else
  log "ComfyUI models directory already exists - skipping symlink"
fi

# Install custom nodes
log "Installing custom nodes"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"

cd "$CUSTOM_NODES_DIR"

# Install essential custom nodes
if [ ! -d "ComfyUI-Manager" ]; then
  log "Cloning ComfyUI-Manager..."
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git
else
  log "ComfyUI-Manager already exists - skipping"
fi

if [ ! -d "ComfyUI-Impact-Pack" ]; then
  log "Cloning ComfyUI-Impact-Pack..."
  git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
else
  log "ComfyUI-Impact-Pack already exists - skipping"
fi

if [ ! -d "ComfyUI_IPAdapter_plus" ]; then
  log "Cloning ComfyUI_IPAdapter_plus..."
  git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
else
  log "ComfyUI_IPAdapter_plus already exists - skipping"
fi

# Install and patch ComfyUI-NAG
log "Installing ComfyUI-NAG"
if [ ! -d "ComfyUI_NAG" ]; then
  log "Cloning ComfyUI-NAG..."
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  
  # Apply patches
  cd ComfyUI_NAG
  
  log "Applying patches to ComfyUI-NAG..."
  
  # Patch layers.py
  if sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py; then
    log "✓ Patched chroma/layers.py"
  else
    log "⚠ Warning: Failed to patch chroma/layers.py"
  fi
  
  # Patch model.py - remove Chroma imports and fix inheritance
  sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
  sed -i '/import.*Chroma/d' chroma/model.py || true
  sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py
  
  # Ensure Flux import
  if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
    log "✓ Added Flux import to chroma/model.py"
  fi
  
  cd "$CUSTOM_NODES_DIR"
  log "✓ ComfyUI-NAG installed and patched"
else
  log "ComfyUI-NAG already exists - skipping installation"
fi

# Create __init__.py for custom_nodes directory
if [ ! -f "$CUSTOM_NODES_DIR/__init__.py" ]; then
  touch "$CUSTOM_NODES_DIR/__init__.py"
  log "Created __init__.py for custom_nodes"
fi

log "=== ENHANCEMENT COMPLETED SUCCESSFULLY ==="
log "Models installed: Lustify, SDXL VAE"
log "Custom nodes installed: ComfyUI-Manager, Impact-Pack, IPAdapter, ComfyUI-NAG"
log "ComfyUI-NAG patched for Flux compatibility"
log "Ready to use ComfyUI with NAG support!"
