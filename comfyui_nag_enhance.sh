#!/bin/bash
set -e

LOG="/workspace/comfyui_nag_enhance.log"
CUSTOM_NODES_DIR="/workspace/ComfyUI/custom_nodes"
MODELS_DIR="/workspace/ComfyUI/models"
WORKFLOWS_DIR="/workspace/ComfyUI/user/default/workflows"

mkdir -p "$CUSTOM_NODES_DIR" "$MODELS_DIR/checkpoints" "$MODELS_DIR/vae" "$WORKFLOWS_DIR"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" | tee -a "$LOG"
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED (v7 - Fixed Restart) ==="

cd "$CUSTOM_NODES_DIR"

# 1. Models
log "Downloading Lustify SDXL model using CIVITAI_TOKEN..."
curl -L --fail -H "Authorization: Bearer $CIVITAI_TOKEN" \
  -o "$MODELS_DIR/checkpoints/lustify_sdxl_olt_inpainting.safetensors" \
  "https://civitai.com/api/download/models/1588039"

if [ -f "$MODELS_DIR/checkpoints/lustify_sdxl_olt_inpainting.safetensors" ]; then
  log "✅ Lustify model downloaded successfully"
else
  log "❌ Lustify model download failed"
fi

log "Downloading SDXL VAE..."
curl -L --fail -o "$MODELS_DIR/vae/sdxl_vae.safetensors" \
  "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"

log "Creating symlink..."
ln -sf "$MODELS_DIR/checkpoints/lustify_sdxl_olt_inpainting.safetensors" \
  "$MODELS_DIR/checkpoints/LUSTIFY! SDXL - OLT INPAINTING.safetensors" || true

# 2. Workflows
log "Downloading workflows..."
curl -L --fail -o "$WORKFLOWS_DIR/LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY%21%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"

curl -L --fail -o "$WORKFLOWS_DIR/LUSTIFY! SDXL - OLT INPAINTING - DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY%21%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"

log "✅ Workflows downloaded"

# 3. ComfyUI-Manager
log "Installing ComfyUI-Manager..."
if [ ! -d "ComfyUI-Manager" ]; then
  git clone https://github.com/ltdrdata/ComfyUI-Manager.git
fi

# 4. ComfyUI-NAG + proven patch
log "Installing ComfyUI-NAG..."
if [ ! -d "ComfyUI_NAG" ]; then
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  cd ComfyUI_NAG

  log "Applying patches..."
  sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
  sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
  sed -i '/import.*Chroma/d' chroma/model.py || true
  sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true

  if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
  fi

  cd "$CUSTOM_NODES_DIR"
  log "✓ ComfyUI-NAG installed and patched"
else
  log "ComfyUI-NAG already exists"
fi

log "=== ENHANCEMENT COMPLETED ==="

# 5. Restart using the correct Vast.ai method
log "Restarting ComfyUI using Vast.ai default method..."
pkill -f "python.*main.py" || true
sleep 10
log "Starting ComfyUI via default boot script..."
/opt/instance-tools/bin/boot_default.sh >> "$LOG" 2>&1 &
log "ComfyUI should now be starting. Check port 18188 in 20-30 seconds."
