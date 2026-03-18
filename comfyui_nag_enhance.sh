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

log "=== COMFYUI-NAG ENHANCEMENT STARTED (Updated v4) ==="

cd "$CUSTOM_NODES_DIR"

# 1. Download models
log "Downloading Lustify SDXL model..."
curl -L --fail -o "$MODELS_DIR/checkpoints/lustify_sdxl_olt_inpainting.safetensors" \
  "https://civitai.com/api/download/models/1588039?type=Model&format=SafeTensor&size=pruned&fp=fp16" || log "⚠️ Lustify download failed (check link)"

log "Downloading SDXL VAE..."
curl -L --fail -o "$MODELS_DIR/vae/sdxl_vae.safetensors" \
  "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" || log "⚠️ VAE download failed"

log "Creating symlink for easier loading..."
ln -sf "$MODELS_DIR/checkpoints/lustify_sdxl_olt_inpainting.safetensors" \
  "$MODELS_DIR/checkpoints/LUSTIFY! SDXL - OLT INPAINTING.safetensors" || true

# 2. Download workflows (URL-encoded)
log "Downloading workflows from GitHub..."
curl -L --fail -o "$WORKFLOWS_DIR/LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY%21%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"

curl -L --fail -o "$WORKFLOWS_DIR/LUSTIFY! SDXL - OLT INPAINTING - DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY%21%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"

log "✅ Workflows downloaded"

# 3. Install supporting nodes
log "Installing custom nodes..."
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus; do
  node_name=$(basename "$repo")
  if [ ! -d "$node_name" ]; then
    git clone "https://github.com/$repo.git" || true
    log "Cloned $node_name"
  fi
done

# 4. Install + patch ComfyUI-NAG (using your proven patch)
log "Installing ComfyUI-NAG..."
if [ ! -d "ComfyUI_NAG" ]; then
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  cd ComfyUI_NAG

  log "Applying patches to ComfyUI-NAG..."
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
  log "ComfyUI-NAG already exists - skipping"
fi

log "=== ENHANCEMENT COMPLETED SUCCESSFULLY ==="
log "Lustify model, SDXL VAE, workflows, and patched NAG node are ready."

# Optional: Restart ComfyUI so new nodes load cleanly
log "Restarting ComfyUI to load new custom nodes..."
pkill -f "python.*main.py" || true
sleep 5
/entrypoint.sh >> "$LOG" 2>&1 &
log "ComfyUI restarted in background."
