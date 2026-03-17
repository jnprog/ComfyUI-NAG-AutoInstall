#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/portal/comfyui_setup.log"
mkdir -p "$(dirname "$LOG")"
echo "=== ComfyUI + NAG Setup start: $(date -u) ===" >> "$LOG"

log() {
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >> "$LOG"
}

log "Starting comprehensive ComfyUI + NAG setup"

# Install system dependencies
apt-get update
apt-get install -y git wget curl

# Install Lustify model and SDXL VAE (from your original script)
log "Installing Lustify model and SDXL VAE"
mkdir -p /workspace/ComfyUI/models/checkpoints
mkdir -p /workspace/ComfyUI/models/vae

cd /workspace/ComfyUI/models/checkpoints
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  log "Downloading Lustify model..."
  wget -O lustifySDXLNSFW_oltINPAINTING.safetensors https://huggingface.co/lokCX/Lustify-SDXL-NSFW-INPAINTING/resolve/main/lustifySDXLNSFW_oltINPAINTING.safetensors
fi

cd /workspace/ComfyUI/models/vae  
if [ ! -f "sdxl_vae.safetensors" ]; then
  log "Downloading SDXL VAE..."
  wget -O sdxl_vae.safetensors https://huggingface.co/madebyollin/sdxl-vae/resolve/main/sdxl_vae.safetensors
fi

# Properly git clone ComfyUI (this is the key fix!)
log "Git cloning ComfyUI (proper repository setup)"
cd /workspace
rm -rf ComfyUI 2>/dev/null || true
git clone https://github.com/comfyanonymous/ComfyUI.git
cd ComfyUI

# Install Python requirements
log "Installing Python requirements"
pip install -r requirements.txt

# Install custom nodes (from your original script)
log "Installing custom nodes"
mkdir -p custom_nodes
cd custom_nodes

# Essential nodes from your original setup
git clone https://github.com/ltdrdata/ComfyUI-Manager.git
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git  
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git
git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
git clone https://github.com/Gourieff/comfyui-reactor-node.git
git clone https://github.com/cubiq/ComfyUI_InstantID.git
git clone https://github.com/FizzleDorf/ComfyUI_FizzNodes.git
git clone https://github.com/cubiq/ComfyUI_Inspire_Pack.git

cd ..

# Install ComfyUI-NAG with correct patches
log "Installing ComfyUI-NAG with compatibility patches"
cd custom_nodes
git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
cd ComfyUI-NAG

# Apply critical compatibility patches
if [ -f "chroma/model.py" ]; then
  log "Patching chroma/model.py"
  # Remove dead Chroma import (doesn't exist in current ComfyUI)
  sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' "chroma/model.py" || true
  sed -i '/import.*Chroma/d' "chroma/model.py" || true
  sed -i '/from.*Chroma/d' "chroma/model.py" || true
  # Fix import paths for current ComfyUI structure
  sed -E -i 's/\bcomfy\.ldm\.chroma\b/comfy.ldm.flux/g' "chroma/model.py" || true
  sed -E -i 's/\bcomfy\.ldm\.chroma\.layers\b/comfy.ldm.flux.layers/g' "chroma/model.py" || true
fi

if [ -f "chroma/layers.py" ]; then
  log "Patching chroma/layers.py"
  sed -E -i 's/\bcomfy\.ldm\.chroma\b/comfy.ldm.flux/g' "chroma/layers.py" || true
  sed -E -i 's/\bcomfy\.ldm\.chroma\.layers\b/comfy.ldm.flux.layers/g' "chroma/layers.py" || true
fi

cd ../..

# Start ComfyUI
log "Starting ComfyUI with all models and nodes"
echo "=== Setup completed successfully ===" >> "$LOG"
cd /workspace/ComfyUI
python main.py --listen 0.0.0.0 --port 8188 --enable-cors-header --disable-metadata
