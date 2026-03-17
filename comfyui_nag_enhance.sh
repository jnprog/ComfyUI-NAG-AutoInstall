#!/usr/bin/env bash
set -euo pipefail

# Vast.ai ComfyUI-NAG Enhancement Script
LOG_DIR="/var/log/portal"
LOG_FILE="$LOG_DIR/comfyui_nag_enhance.log"
mkdir -p "$LOG_DIR"

log() {
  local timestamp
  timestamp=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
  echo "[$timestamp] $*" | tee -a "$LOG_FILE"
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED ==="

# Find ComfyUI directory
COMFYUI_DIR=""
for possible in "/opt/workspace-internal/ComfyUI" "/workspace/ComfyUI" "/ComfyUI"; do
  if [ -d "$possible" ] && [ -f "$possible/main.py" ]; then
    COMFYUI_DIR="$possible"
    log "Found ComfyUI at: $COMFYUI_DIR"
    break
  fi
done

if [ -z "$COMFYUI_DIR" ]; then
  log "ERROR: Could not find ComfyUI directory"
  exit 1
fi

# Install system dependencies
log "Installing system dependencies"
apt-get update -qq > /dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y git wget curl rclone -qq > /dev/null 2>&1 || true

# Create directory structure
log "Creating workspace directory structure"
mkdir -p /workspace/models/checkpoints/sdxl
mkdir -p /workspace/models/vae/sdxl
mkdir -p /workspace/user/default/workflows/Lustify\ SDXL

# === MODELS ===
CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
if [ -z "$CIVITAI_TOKEN" ]; then
  log "ERROR: CIVITAI_TOKEN environment variable is required"
  exit 1
fi

cd /workspace/models/checkpoints/sdxl
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  log "Starting CivitAI download: Lustify SDXL NSFW Inpainting Model"
  curl -L --progress-bar \
    -H "Authorization: Bearer $CIVITAI_TOKEN" \
    -o "lustifySDXLNSFW_oltINPAINTING.safetensors" \
    "https://civitai.com/api/download/models/1588039" 2>&1 | tee -a "$LOG_FILE"
  log "CivitAI download completed: Lustify SDXL NSFW Inpainting Model"
else
  log "Lustify model already exists - skipping"
fi

cd /workspace/models/vae/sdxl
if [ ! -f "sdxl_vae.safetensors" ]; then
  log "Starting download: SDXL VAE Model"
  wget --progress=bar:force:noscroll -O "sdxl_vae.safetensors" \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" 2>&1 | tee -a "$LOG_FILE"
  log "Download completed: SDXL VAE Model"
else
  log "SDXL VAE already exists - skipping"
fi

# === WORKFLOWS ===
log "Downloading workflows using Google Drive logic"

RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
WORKFLOW_DIR="/workspace/user/default/workflows/Lustify SDXL"
WF1_NAME='LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json'
WF2_NAME='LUSTIFY! SDXL - OLT INPAINTING - DMD2.json'
WF1_DEST="${WORKFLOW_DIR}/${WF1_NAME}"
WF2_DEST="${WORKFLOW_DIR}/${WF2_NAME}"

gdrive_download() {
  local FILEID="$1"
  local OUT="$2"
  log "gdrive_download: fileid=$FILEID out=$OUT"
  mkdir -p "$(dirname "$OUT")"
  local COOKIE PAGE CONFIRM
  COOKIE=$(mktemp)
  PAGE=$(mktemp)
  if command -v curl >/dev/null 2>&1; then
    curl -s -c "$COOKIE" -L "https://docs.google.com/uc?export=download&id=${FILEID}" -o "$PAGE"
    CONFIRM=$(sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1/p' "$PAGE" | head -n1 || true)
    if [ -n "$CONFIRM" ]; then
      curl -L --progress-bar -b "$COOKIE" "https://docs.google.com/uc?export=download&confirm=${CONFIRM}&id=${FILEID}" -o "$OUT" 2>&1 | tee -a "$LOG_FILE"
    else
      curl -L --progress-bar -b "$COOKIE" "https://docs.google.com/uc?export=download&id=${FILEID}" -o "$OUT" 2>&1 | tee -a "$LOG_FILE"
    fi
  fi
  rm -f "$COOKIE" "$PAGE"
}

download_workflow_by_id_or_rclone() {
  local FILEID="$1"
  local OUT="$2"
  if [ -f "$OUT" ]; then log "Workflow already exists: $OUT"; return 0; fi
  if [ -n "$FILEID" ]; then
    log "Attempting direct GDrive download for $OUT"
    if gdrive_download "$FILEID" "$OUT"; then
      chmod 644 "$OUT" || true
      log "Downloaded workflow to $OUT"
      return 0
    fi
  fi
  log "Failed to download workflow $OUT"
  return 1
}

# Download workflows
REMOTE_FOLDER="${WORKFLOW_DRIVE_PATH:-$DRIVE_FILE_PATH}"
download_workflow_by_id_or_rclone "${WORKFLOW1_FILE_ID:-}" "$WF1_DEST"
download_workflow_by_id_or_rclone "${WORKFLOW2_FILE_ID:-}" "$WF2_DEST"

# Symlink models
ln -sfn /workspace/models "$COMFYUI_DIR/models" 2>/dev/null || true
log "Models symlinked"

# Install custom nodes + NAG with stronger patch
log "Installing custom nodes and ComfyUI-NAG..."
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR"

for repo in "https://github.com/ltdrdata/ComfyUI-Manager.git" "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"; do
  dir=$(basename "$repo" .git)
  if [ ! -d "$dir" ]; then 
    git clone --depth 1 "$repo"
    log "Cloned $dir"
  fi
done

if [ ! -d "ComfyUI_NAG" ]; then
  log "Cloning ComfyUI-NAG..."
  git clone https://github.com/ChenDarYen/ComfyUI-NAG.git
  mv ComfyUI-NAG ComfyUI_NAG
  
  cd ComfyUI_NAG
  log "Applying stronger patches to fix NoneType error..."

  # Stronger patch for layers.py
  sed -i 's|from .* import DoubleStreamBlock, SingleStreamBlock|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
  sed -i 's|from .*layers import|from comfy.ldm.flux.layers import|' chroma/layers.py || true

  # Stronger patch for model.py
  sed -i '/Chroma/d' chroma/model.py || true
  sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
  
  if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1i from comfy.ldm.flux.model import Flux' chroma/model.py
  fi

  cd ..
  log "✓ ComfyUI-NAG installed and patched"
else
  log "ComfyUI-NAG already exists - skipping installation"
fi

touch "$CUSTOM_NODES_DIR/__init__.py" 2>/dev/null || true

log "=== ENHANCEMENT COMPLETED SUCCESSFULLY ==="
log "Models in /workspace/models/.../sdxl/"
log "Workflows in $WORKFLOW_DIR"
log "NAG node patched and ready"
