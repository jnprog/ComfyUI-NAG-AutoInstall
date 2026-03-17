#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/portal/comfyui_setup.log"
mkdir -p "$(dirname "$LOG")"
echo "=== Standard ComfyUI Setup start: $(date -u) ===" >> "$LOG"

log() {
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >> "$LOG"
}

log "Starting standard ComfyUI setup with proper Python structure"

# Install system dependencies
apt-get update
apt-get install -y git wget curl

# Install Lustify model and SDXL VAE (keep your existing models)
log "Installing Lustify model and SDXL VAE"
mkdir -p /workspace/models/checkpoints
mkdir -p /workspace/models/vae

cd /workspace/models/checkpoints
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  log "Downloading Lustify model..."
  wget -O lustifySDXLNSFW_oltINPAINTING.safetensors https://huggingface.co/lokCX/Lustify-SDXL-NSFW-INPAINTING/resolve/main/lustifySDXLNSFW_oltINPAINTING.safetensors
fi

cd /workspace/models/vae  
if [ ! -f "sdxl_vae.safetensors" ]; then
  log "Downloading SDXL VAE..."
  wget -O sdxl_vae.safetensors https://huggingface.co/madebyollin/sdxl-vae/resolve/main/sdxl_vae.safetensors
fi

# CRITICAL: Proper standard ComfyUI installation
log "Installing standard ComfyUI with full Python package structure"
cd /workspace
rm -rf ComfyUI 2>/dev/null || true

# Clone the official ComfyUI repository
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI

# Verify we have the proper structure
log "Verifying ComfyUI structure..."
if [ ! -d "comfy" ]; then
  log "ERROR: comfy directory not found! This is not a standard ComfyUI installation."
  exit 1
fi

if [ ! -f "comfy/__init__.py" ] || [ ! -f "main.py" ]; then
  log "ERROR: Missing critical ComfyUI files!"
  exit 1
fi

log "ComfyUI structure verified - proceeding with setup"

# Install Python requirements
log "Installing Python requirements"
pip install -r requirements.txt

# Install essential custom nodes
log "Installing essential custom nodes"
mkdir -p custom_nodes
cd custom_nodes

# Core nodes you need
git clone https://github.com/ltdrdata/ComfyUI-Manager.git
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git

cd ..

# Install ComfyUI-NAG with proper patches
log "Installing ComfyUI-NAG"
cd custom_nodes
git clone https://github.com/ChenDarYen/ComfyUI-NAG.git

# Apply compatibility patches
cd ComfyUI-NAG

# Patch layers.py - this is the key fix from the GitHub issue
if [ -f "chroma/layers.py" ]; then
  log "Patching chroma/layers.py for Flux compatibility"
  # Replace the import line with the correct one
  sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' "chroma/layers.py"
fi

# Patch model.py - remove dead Chroma import and fix paths
if [ -f "chroma/model.py" ]; then
  log "Patching chroma/model.py"
  # Remove dead Chroma import
  sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' "chroma/model.py" || true
  sed -i '/import.*Chroma/d' "chroma/model.py" || true
  # Fix import paths
  sed -E -i 's/\bcomfy\.ldm\.chroma\b/comfy.ldm.flux/g' "chroma/model.py" || true
  sed -E -i 's/\bcomfy\.ldm\.chroma\.layers\b/comfy.ldm.flux.layers/g' "chroma/model.py" || true
fi

cd ../..

# Create symlink for models (standard ComfyUI expects models in ComfyUI/models)
log "Setting up model directories"
rm -rf models 2>/dev/null || true
ln -s /workspace/models /workspace/ComfyUI/models

# Test the installation
log "Testing ComfyUI structure..."
python3 -c "
import sys
sys.path.insert(0, '.')
import comfy
print('SUCCESS: comfy module imported!')
print(f'ComfyUI path: {comfy.__file__}')
"

# Test NAG import
log "Testing NAG node import..."
python3 -c "
import sys
sys.path.insert(0, '.')
from custom_nodes.ComfyUI_NAG import node
print('SUCCESS: NAG node imported!')
"

log "=== Standard ComfyUI setup completed successfully ==="
echo "=== Setup completed: $(date -u) ===" >> "$LOG"

# Start ComfyUI
cd /workspace/ComfyUI
log "Starting ComfyUI..."
exec python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --disable-metadata
