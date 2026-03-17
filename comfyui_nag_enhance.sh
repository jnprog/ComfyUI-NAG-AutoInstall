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

# Function to download with progress (for public URLs, using wget)
download_with_progress() {
  local url="$1"
  local output="$2"
  local description="$3"
  
  log "Starting download: $description"
  log "URL: $url"
  log "Output: $output"
  
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

# CivitAI download function (using curl for better redirect handling)
download_civitai_model() {
  local version_id="$1"  
  local output="$2"
  local description="$3"
  local api_key="$4"
  
  log "Starting CivitAI download: $description"
  log "Version ID: $version_id"
  
  local download_url="https://civitai.com/api/download/models/$version_id"
  
  curl -L --progress-bar \
    --header "Authorization: Bearer $api_key" \
    --header "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
    -o "$output" "$download_url" 2>&1 | while read line; do
    if [[ "$line" == *%* ]]; then
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] DOWNLOAD PROGRESS: $line" | tee -a "$LOG_FILE"
    elif [[ "$line" == *"saved"* || "$line" == *"complete"* ]]; then
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] DOWNLOAD COMPLETE: $line" | tee -a "$LOG_FILE"
    else
      echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] CURL: $line" >> "$LOG_FILE"
    fi
  done
  
  log "CivitAI download completed: $description"
}

# Helper: download from google drive (handles confirm token for large files)
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
    rm -f "$COOKIE" "$PAGE"
    return 0
  fi

  if command -v wget >/dev/null 2>&1; then
    wget --quiet --save-cookies "$COOKIE" --keep-session-cookies --no-check-certificate "https://docs.google.com/uc?export=download&id=${FILEID}" -O "$PAGE"
    CONFIRM=$(sed -rn 's/.*confirm=([0-9A-Za-z_]+).*/\1/p' "$PAGE" | head -n1 || true)
    if [ -n "$CONFIRM" ]; then
      wget --progress=bar:force:noscroll --load-cookies "$COOKIE" "https://docs.google.com/uc?export=download&confirm=${CONFIRM}&id=${FILEID}" -O "$OUT" 2>&1 | tee -a "$LOG_FILE"
    else
      wget --progress=bar:force:noscroll --load-cookies "$COOKIE" "https://docs.google.com/uc?export=download&id=${FILEID}" -O "$OUT" 2>&1 | tee -a "$LOG_FILE"
    fi
    rm -f "$COOKIE" "$PAGE"
    return 0
  fi

  log "No curl or wget available for Google Drive download"
  rm -f "$COOKIE" "$PAGE"
  return 1
}

log "=== COMFYUI-NAG ENHANCEMENT STARTED ==="

# Find ComfyUI directory
COMFYUI_DIR=""
if [ -d "/ComfyUI" ] && [ -f "/ComfyUI/main.py" ]; then
  COMFYUI_DIR="/ComfyUI"
  log "Found ComfyUI at: /ComfyUI"
elif [ -d "/workspace/ComfyUI" ] && [ -f "/workspace/ComfyUI/main.py" ]; then
  COMFYUI_DIR="/workspace/ComfyUI"
  log "Found ComfyUI at: /workspace/ComfyUI"
else
  COMFYUI_DIR=$(find / -name "main.py" -path "*/ComfyUI/*" -exec dirname {} \; 2>/dev/null | head -1)
  if [ -z "$COMFYUI_DIR" ]; then
    log "ERROR: Could not find ComfyUI directory"
    exit 1
  else
    log "Found ComfyUI at: $COMFYUI_DIR"
  fi
fi

# Install system dependencies
log "Installing system dependencies"
apt-get update > /dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y git wget curl > /dev/null 2>&1 || true

# Create workspace directory structure (matching gist layout)
log "Creating workspace directory structure"
mkdir -p /workspace/models/checkpoints/sdxl
mkdir -p /workspace/models/vae/sdxl
mkdir -p /workspace/models

# Download Lustify model from CivitAI
CIVITAI_TOKEN="${CIVITAI_TOKEN:-}"
if [ -z "$CIVITAI_TOKEN" ]; then
  log "ERROR: CivitAI API key required for Lustify model download"
  exit 1
fi

cd /workspace/models/checkpoints/sdxl
if [ ! -f "lustifySDXLNSFW_oltINPAINTING.safetensors" ]; then
  download_civitai_model \
    "1588039" \
    "lustifySDXLNSFW_oltINPAINTING.safetensors" \
    "Lustify SDXL NSFW Inpainting Model" \
    "$CIVITAI_TOKEN"
else
  log "Lustify model already exists - skipping download"
fi

# Download SDXL VAE
cd /workspace/models/vae/sdxl
if [ ! -f "sdxl_vae.safetensors" ]; then
  download_with_progress \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
    "sdxl_vae.safetensors" \
    "SDXL VAE Model"
else
  log "SDXL VAE already exists - skipping download"
fi

# === WORKFLOWS (Google Drive + rclone fallback from your gist) ===
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
WORKFLOW_DRIVE_PATH="${WORKFLOW_DRIVE_PATH:-}"
DRIVE_FILE_PATH="${DRIVE_FILE_PATH:-}"

WORKFLOW_DIR="/workspace/user/default/workflows/Lustify SDXL"
WF1_NAME='LUSTIFY! SDXL - OLT INPAINTING - NON-DMD2.json'
WF2_NAME='LUSTIFY! SDXL - OLT INPAINTING - DMD2.json'
WF1_DEST="${WORKFLOW_DIR}/${WF1_NAME}"
WF2_DEST="${WORKFLOW_DIR}/${WF2_NAME}"
mkdir -p "$WORKFLOW_DIR"

download_workflow_by_id_or_rclone() {
  local FILEID="$1"
  local REMOTE_PATH="$2"
  local OUT="$3"

  if [ -f "$OUT" ]; then
    log "Workflow already exists: $OUT"
    return 0
  fi

  if [ -n "$FILEID" ]; then
    log "Attempting direct GDrive download of workflow (file id: $FILEID) -> $OUT"
    if gdrive_download "$FILEID" "$OUT"; then
      chmod 644 "$OUT" || true
      log "Downloaded workflow to $OUT"
      return 0
    else
      log "Direct workflow download failed for file id $FILEID"
    fi
  fi

  # rclone fallback
  if command -v rclone >/dev/null 2>&1 && [ -f /workspace/service-account.json ] && [ -n "$REMOTE_PATH" ]; then
    log "Attempting rclone copy of ${RCLONE_REMOTE}:${REMOTE_PATH} -> ${OUT}"
    mkdir -p "$(dirname "$OUT")"
    if rclone copyto --drive-chunk-size 64M --transfers 1 --progress "${RCLONE_REMOTE}:${REMOTE_PATH}" "${OUT}" 2>&1 | tee -a "$LOG_FILE"; then
      chmod 644 "$OUT" || true
      log "rclone copied workflow to $OUT"
      return 0
    else
      log "rclone copyto failed for ${RCLONE_REMOTE}:${REMOTE_PATH}"
    fi
  fi

  log "Failed to obtain workflow -> $OUT"
  return 1
}

# Download service-account.json if needed
if [ ! -f /workspace/service-account.json ] && [ -n "${SA_JSON_FILE_ID:-}" ]; then
  log "Downloading service-account.json from Drive (file id: $SA_JSON_FILE_ID)"
  if gdrive_download "$SA_JSON_FILE_ID" /workspace/service-account.json; then
    chmod 600 /workspace/service-account.json || true
    log "Downloaded /workspace/service-account.json"
  else
    log "Failed to download service-account.json"
  fi
fi

# Create rclone.conf if service account exists
if [ -f /workspace/service-account.json ]; then
  RCLONE_CONF_DIR="/root/.config/rclone"
  mkdir -p "$RCLONE_CONF_DIR"
  RCLONE_CONF_PATH="$RCLONE_CONF_DIR/rclone.conf"
  printf '[%s]\ntype = drive\nscope = drive\nservice_account_file = /workspace/service-account.json\n' "$RCLONE_REMOTE" > "$RCLONE_CONF_PATH"
  chmod 600 "$RCLONE_CONF_PATH"
  log "Created minimal rclone.conf for remote [$RCLONE_REMOTE]"
fi

# Install rclone if needed for fallback
REMOTE_FOLDER="${WORKFLOW_DRIVE_PATH:-$DRIVE_FILE_PATH}"
if [ -f /workspace/service-account.json ] && [ -n "$REMOTE_FOLDER" ] && ! command -v rclone >/dev/null 2>&1; then
  log "rclone not found — installing"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://rclone.org/install.sh | bash 2>&1 | tee -a "$LOG_FILE" || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://rclone.org/install.sh | bash 2>&1 | tee -a "$LOG_FILE" || true
  fi
fi

log "Downloading workflows..."
download_workflow_by_id_or_rclone "${WORKFLOW1_FILE_ID:-}" "${REMOTE_FOLDER:+${REMOTE_FOLDER}/${WF1_NAME}}" "$WF1_DEST" || true
download_workflow_by_id_or_rclone "${WORKFLOW2_FILE_ID:-}" "${REMOTE_FOLDER:+${REMOTE_FOLDER}/${WF2_NAME}}" "$WF2_DEST" || true

# Create symlink for models
if [ ! -d "$COMFYUI_DIR/models" ]; then
  log "Creating models symlink from $COMFYUI_DIR/models to /workspace/models"
  ln -sfn /workspace/models "$COMFYUI_DIR/models"
else
  log "ComfyUI models directory already exists - skipping symlink"
fi

# Install custom nodes (unchanged from your version)
log "Installing custom nodes"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
mkdir -p "$CUSTOM_NODES_DIR"
cd "$CUSTOM_NODES_DIR"

for repo in \
  "https://github.com/ltdrdata/ComfyUI-Manager.git" \
  "https://github.com/ltdrdata/ComfyUI-Impact-Pack.git" \
  "https://github.com/cubiq/ComfyUI_IPAdapter_plus.git"; do
  dir=$(basename "$repo" .git)
  if [ ! -d "$dir" ]; then
    log "Cloning $dir..."
    git clone "$repo"
  else
    log "$dir already exists - skipping"
  fi
done

# Install and patch ComfyUI-NAG
log "Installing ComfyUI-NAG"
if [ ! -d "ComfyUI_NAG" ]; then
  log "Cloning ComfyUI-NAG..."
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
  log "ComfyUI-NAG already exists - skipping installation"
fi

if [ ! -f "$CUSTOM_NODES_DIR/__init__.py" ]; then
  touch "$CUSTOM_NODES_DIR/__init__.py"
  log "Created __init__.py for custom_nodes"
fi

log "=== ENHANCEMENT COMPLETED SUCCESSFULLY ==="
log "Models installed: Lustify (in sdxl/), SDXL VAE (in sdxl/), workflows in Lustify SDXL folder"
log "Custom nodes: Manager, Impact-Pack, IPAdapter, ComfyUI-NAG (patched)"
log "Ready to use ComfyUI with NAG support!"
