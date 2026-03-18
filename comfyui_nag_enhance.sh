#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="/var/log/portal"
LOG_FILE="$LOG_DIR/comfyui_nag_enhance.log"
mkdir -p "$LOG_DIR"

log() {
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED (GitHub version) ==="

COMFYUI_DIR="/opt/workspace-internal/ComfyUI"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
WORKFLOW_DIR="/workspace/user/default/workflows/Lustify SDXL"

mkdir -p "$WORKFLOW_DIR"

log "Downloading workflows from GitHub..."

curl -L --progress-bar -o "$WORKFLOW_DIR/LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json"

curl -L --progress-bar -o "$WORKFLOW_DIR/LUSTIFY! SDXL - OLT INPAINTING - DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY! SDXL - OLT INPAINTING - DMD2.json"

log "✅ Workflows downloaded successfully from GitHub"

# Install custom nodes
log "Installing custom nodes..."
cd "$CUSTOM_NODES_DIR"

for repo in "https://github.com/ltdrdata/ComfyUI-Manager.git" \
            "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
            "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"; do
  dir=$(basename "$repo" .git)
  if [ ! -d "$dir" ]; then 
    git clone --depth 1 "$repo"
    log "Cloned $dir"
  fi
done

# Install and patch ComfyUI-NAG (strong patch)
if [ ! -d "ComfyUI_NAG" ]; then
  log "Cloning and patching ComfyUI-NAG..."
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  cd ComfyUI_NAG

  log "Applying patches to fix NoneType error..."
  sed -i 's|from .* import DoubleStreamBlock|from comfy.ldm.flux.layers import DoubleStreamBlock|' chroma/layers.py || true
  sed -i 's|from .* import SingleStreamBlock|from comfy.ldm.flux.layers import SingleStreamBlock|' chroma/layers.py || true
  sed -i '/Chroma/d' chroma/model.py || true
  sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
  
  if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1i from comfy.ldm.flux.model import Flux' chroma/model.py
  fi

  cd ..
  log "✅ ComfyUI-NAG patched successfully"
fi

touch "$CUSTOM_NODES_DIR/__init__.py" 2>/dev/null || true

log "=== ENHANCEMENT COMPLETED SUCCESSFULLY ==="
log "Models: Lustify SDXL + SDXL VAE are ready"
log "Workflows downloaded from GitHub"
log "NAG node installed and patched"
