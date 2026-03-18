#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/portal"
LOG_FILE="$LOG_DIR/comfyui_nag_enhance.log"
mkdir -p "$LOG_DIR"

log() {
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED (Updated v3) ==="

COMFYUI_DIR="/workspace/ComfyUI"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
WORKFLOW_DIR="/workspace/user/default/workflows/Lustify SDXL"
MODEL_DIR="/workspace/models"

mkdir -p "$CUSTOM_NODES_DIR"
mkdir -p "$WORKFLOW_DIR"
mkdir -p "$MODEL_DIR/checkpoints/sdxl"
mkdir -p "$MODEL_DIR/vae/sdxl"

log "Downloading Lustify SDXL model..."
cd "$MODEL_DIR/checkpoints/sdxl"
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
    curl -L --progress-bar -H "Authorization: Bearer $CIVITAI_TOKEN" \
      -o "lustifySDXLNSFW_oltINPAINTING.safetensors" \
      "https://civitai.com/api/download/models/1588039" || log "Warning: Failed to download Lustify model"
else
    log "Lustify model already exists"
fi

log "Downloading SDXL VAE..."
cd "$MODEL_DIR/vae/sdxl"
if [ ! -f "sdxl_vae.safetensors" ]; then
    wget --progress=bar:force:noscroll -O "sdxl_vae.safetensors" \
      "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" || log "Warning: Failed to download VAE"
else
    log "SDXL VAE already exists"
fi

log "Creating symlink for models..."
ln -sfn "$MODEL_DIR" "$COMFYUI_DIR/models" 2>/dev/null || true

log "Downloading workflows from GitHub..."
cd "$WORKFLOW_DIR"
curl -L --connect-timeout 20 --max-time 60 -f -o "LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"

curl -L --connect-timeout 20 --max-time 60 -f -o "LUSTIFY! SDXL - OLT INPAINTING - DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"

log "✅ Workflows downloaded"

# Install custom nodes
log "Installing custom nodes..."
cd "$CUSTOM_NODES_DIR"

for repo in "https://github.com/ltdrdata/ComfyUI-Manager.git" \
            "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
            "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"; do
  dir=$(basename "$repo" .git)
  if [ ! -d "$dir" ]; then 
    git clone --depth 1 "$repo" && log "Cloned $dir" || log "Failed to clone $dir"
  fi
done

# Install and patch ComfyUI-NAG with strong fix
if [ ! -d "ComfyUI_NAG" ]; then
  log "Cloning ComfyUI-NAG..."
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  cd ComfyUI_NAG

  log "Applying strong patches for layers.py and model.py..."
  
  # Strong patch for layers.py
  sed -i 's|from .* import DoubleStreamBlock, SingleStreamBlock|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
  sed -i 's|^from .*layers.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
  
  # Strong patch for model.py
  sed -i '/Chroma/d' chroma/model.py || true
  sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
  
  if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1i from comfy.ldm.flux.model import Flux' chroma/model.py
  fi

  cd ..
  log "✅ ComfyUI-NAG installed and patched successfully"
else
  log "ComfyUI-NAG already exists"
fi

touch "$CUSTOM_NODES_DIR/__init__.py" 2>/dev/null || true

log "=== ENHANCEMENT COMPLETED SUCCESSFULLY ==="
log "Lustify model, SDXL VAE, workflows, and patched NAG node are ready"
