#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/portal/comfyui_nag_install.log"
mkdir -p "$(dirname "$LOG")"
echo "=== ComfyUI-NAG installer start: $(date -u) ===" >> "$LOG"

# Configurable vars (can be passed as env)
COMFYUI_DIR="${COMFYUI_DIR:-/opt/workspace-internal/ComfyUI}"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
GIT_CLONE_URL="${GIT_CLONE_URL:-https://github.com/jnprog/ComfyUI-NAG-AutoInstall.git}"
GITHUB_ARCHIVE_URL="${GITHUB_ARCHIVE_URL:-}"
INSTALL_WAIT_TIMEOUT="${INSTALL_WAIT_TIMEOUT:-1800}"  # seconds, default 30m
INSTALL_POLL_INTERVAL="${INSTALL_POLL_INTERVAL:-15}"  # seconds
LUSTIFY_LOG="${LUSTIFY_LOG:-/workspace/install_sdxl_vae.log}"

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Using COMFYUI_DIR=$COMFYUI_DIR" >> "$LOG"
mkdir -p "$CUSTOM_NODES_DIR"

# Create safe symlink so /workspace/ComfyUI points to authoritative COMFYUI_DIR if possible
if [ ! -e /workspace/ComfyUI ]; then
  mkdir -p "$(dirname "$COMFYUI_DIR")"
  mkdir -p "$COMFYUI_DIR"
  ln -sfn "$COMFYUI_DIR" /workspace/ComfyUI
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Created symlink /workspace/ComfyUI -> $COMFYUI_DIR" >> "$LOG"
elif [ -L /workspace/ComfyUI ]; then
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') /workspace/ComfyUI already a symlink" >> "$LOG"
else
  # Exists and not a symlink: only replace if empty
  if [ -z "$(ls -A /workspace/ComfyUI 2>/dev/null || true)" ]; then
    rm -rf /workspace/ComfyUI
    ln -sfn "$COMFYUI_DIR" /workspace/ComfyUI
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Replaced empty /workspace/ComfyUI with symlink -> $COMFYUI_DIR" >> "$LOG"
  else
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') WARN: /workspace/ComfyUI exists and is non-empty; not changing it." >> "$LOG"
  fi
fi

# Wait for Lustify model + VAE to exist or for Lustify completion message
waited=0
LUSTIFY_MODEL_OPT="$COMFYUI_DIR/models/checkpoints/lustifySDXLNSFW_oltINPAINTING.safetensors"
VAE_FILE_OPT="$COMFYUI_DIR/models/vae/sdxl_vae.safetensors"
LUSTIFY_MODEL_WS="/workspace/ComfyUI/models/checkpoints/lustifySDXLNSFW_oltINPAINTING.safetensors"
VAE_FILE_WS="/workspace/ComfyUI/models/vae/sdxl_vae.safetensors"

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Waiting up to ${INSTALL_WAIT_TIMEOUT}s for Lustify model & VAE..." >> "$LOG"
while true; do
  if ( [ -s "$LUSTIFY_MODEL_OPT" ] && [ -s "$VAE_FILE_OPT" ] ) || ( [ -s "$LUSTIFY_MODEL_WS" ] && [ -s "$VAE_FILE_WS" ] ); then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Models found." >> "$LOG"
    break
  fi
  if grep -q "LUSTIFY ComfyUI setup completed" "$LUSTIFY_LOG" 2>/dev/null; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Lustify script reported completion in $LUSTIFY_LOG" >> "$LOG"
    break
  fi
  if [ "$waited" -ge "$INSTALL_WAIT_TIMEOUT" ]; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') TIMEOUT waiting for Lustify after ${waited}s — proceeding anyway" >> "$LOG"
    break
  fi
  sleep "$INSTALL_POLL_INTERVAL"
  waited=$((waited + INSTALL_POLL_INTERVAL))
done

# Determine source and install
TARGET_DIR="$CUSTOM_NODES_DIR/ComfyUI_NAG"
TMP_DIR="${TARGET_DIR}.tmp"

if [ -d "$TARGET_DIR" ]; then
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ComfyUI_NAG already present at $TARGET_DIR" >> "$LOG"
  INSTALLED=true
else
  INSTALLED=false
  # Use GIT_CLONE_URL if provided
  if [ -n "${GIT_CLONE_URL:-}" ]; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Installing from GIT_CLONE_URL=$GIT_CLONE_URL" >> "$LOG"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    # Setup netrc if credentials present
    if [ -n "${GITHUB_USER:-}" ] && [ -n "${GITHUB_TOKEN:-}" ]; then
      printf 'machine github.com\nlogin %s\npassword %s\n' "$GITHUB_USER" "$GITHUB_TOKEN" > "$HOME/.netrc"
      chmod 600 "$HOME/.netrc"
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Wrote temporary .netrc for git auth" >> "$LOG"
    fi
    # Try shallow clone
    if command -v git >/dev/null 2>&1; then
      git -c http.lowSpeedLimit=0 clone --depth 1 "$GIT_CLONE_URL" "$TMP_DIR" >> "$LOG" 2>&1 || {
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Git clone failed; cleaning up" >> "$LOG"
        rm -rf "$TMP_DIR"
      }
    else
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') git not available on system; cannot clone via GIT_CLONE_URL" >> "$LOG"
    fi
    rm -f "$HOME/.netrc" 2>/dev/null || true
    # If tmp has content, move/rename into target
    if [ -d "$TMP_DIR" ] && [ -n "$(ls -A "$TMP_DIR" 2>/dev/null)" ]; then
      rm -rf "$TARGET_DIR"
      mv "$TMP_DIR" "$TARGET_DIR"
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Installed ComfyUI_NAG to $TARGET_DIR" >> "$LOG"
      INSTALLED=true
    fi
  fi

  # If not installed & archive url present -> try download/extract
  if ! $INSTALLED && [ -n "${GITHUB_ARCHIVE_URL:-}" ]; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Attempting download from GITHUB_ARCHIVE_URL=$GITHUB_ARCHIVE_URL" >> "$LOG"
    mkdir -p "$TMP_DIR"
    curl -L "$GITHUB_ARCHIVE_URL" -o "$TMP_DIR/archive.tar.gz" >> "$LOG" 2>&1 || true
    tar -xzf "$TMP_DIR/archive.tar.gz" -C "$TMP_DIR" --strip-components=1 >> "$LOG" 2>&1 || true
    if [ -n "$(ls -A "$TMP_DIR" 2>/dev/null)" ]; then
      rm -rf "$TARGET_DIR"
      mv "$TMP_DIR" "$TARGET_DIR"
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Installed ComfyUI_NAG (archive) to $TARGET_DIR" >> "$LOG"
      INSTALLED=true
    fi
  fi

  # Fallback: if custom_nodes contains a folder named ComfyUI-NAG, create symlink to ComfyUI_NAG
  if ! $INSTALLED && [ -d "$CUSTOM_NODES_DIR" ]; then
    for d in "$CUSTOM_NODES_DIR"/*; do
      base=$(basename "$d")
      if [ "$base" = "ComfyUI-NAG" ]; then
        ln -sfn "$d" "$TARGET_DIR"
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Found existing ComfyUI-NAG, created symlink $TARGET_DIR -> $d" >> "$LOG"
        INSTALLED=true
        break
      fi
    done
  fi
fi

# Final checks and import test
echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Running import test..." >> "$LOG"
python3 - <<'PY' >> "$LOG" 2>&1 || true
import sys,importlib,traceback,os
COMFYUI_DIR = os.environ.get('COMFYUI_DIR','/opt/workspace-internal/ComfyUI')
sys.path.insert(0, os.path.join(COMFYUI_DIR))
sys.path.insert(0, os.path.join(COMFYUI_DIR, 'custom_nodes'))
try:
    m = importlib.import_module("ComfyUI_NAG.node")
    print("IMPORT-OK", getattr(m, "__file__", "<​no file>"))
except Exception:
    traceback.print_exc()
    print("IMPORT-FAILED")
PY

echo "=== ComfyUI-NAG installer end: $(date -u) ===" >> "$LOG"

# leave exit code 0 to not block boot; check logs for errors
exit 0
