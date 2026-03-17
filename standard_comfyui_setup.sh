#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/portal"
LOG_FILE="$LOG_DIR/comfyui_setup.log"
mkdir -p "$LOG_DIR"

log() {
  local timestamp
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log "=== COMFYUI-NAG SETUP STARTED ==="

# Install system dependencies
log "Installing system dependencies"
apt-get update > /dev/null 2>&1
apt-get install -y git wget curl > /dev/null 2>&1

# Install models
log "Installing models"
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
  wget -O sdxl_vae.safetensors https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors
fi

# Install ComfyUI
log "Installing ComfyUI"
cd /workspace
rm -rf ComfyUI 2>/dev/null || true
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI

# Install Python requirements (includes PyTorch)
log "Installing Python requirements..."
pip install -r requirements.txt

# Install custom nodes
log "Installing custom nodes"
mkdir -p custom_nodes
cd custom_nodes
git clone https://github.com/ltdrdata/ComfyUI-Manager.git
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git

# Install and patch NAG
log "Installing ComfyUI-NAG"
git clone https://github.com/ChenDarYen/ComfyUI-NAG.git

# Rename directory for Python import compatibility
mv ComfyUI-NAG ComfyUI_NAG
cd ComfyUI_NAG

# Apply patches
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py

# Ensure Flux import
grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py || \
sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py

cd ../..

# Setup models
log "Setting up models"
rm -rf models 2>/dev/null || true
ln -s /workspace/models /workspace/ComfyUI/models

# Create custom_nodes __init__.py
touch /workspace/ComfyUI/custom_nodes/__init__.py

log "=== SETUP COMPLETED ==="
log "Starting ComfyUI for Vast.ai web interface..."

# Start ComfyUI (Vast.ai will handle the web interface)
cd /workspace/ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --disable-metadata
