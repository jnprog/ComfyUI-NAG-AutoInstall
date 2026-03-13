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
INSTALL_WAIT_TIMEOUT="${INSTALL_WAIT_TIMEOUT:-1800}" # seconds, default 30m
INSTALL_POLL_INTERVAL="${INSTALL_POLL_INTERVAL:-15}" # seconds
LUSTIFY_LOG="${LUSTIFY_LOG:-/workspace/install_sdxl_vae.log}"

echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Using COMFYUI_DIR=$COMFYUI_DIR" >> "$LOG"
mkdir -p "$CUSTOM_NODES_DIR"

# Ensure /workspace/ComfyUI points to authoritative COMFYUI_DIR
if [ ! -e /workspace/ComfyUI ]; then
  mkdir -p "$(dirname "$COMFYUI_DIR")"
  mkdir -p "$COMFYUI_DIR"
  ln -sfn "$COMFYUI_DIR" /workspace/ComfyUI
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Created symlink /workspace/ComfyUI -> $COMFYUI_DIR" >> "$LOG"
elif [ -L /workspace/ComfyUI ]; then
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') /workspace/ComfyUI already a symlink" >> "$LOG"
else
  if [ -z "$(ls -A /workspace/ComfyUI 2>/dev/null || true)" ]; then
    rm -rf /workspace/ComfyUI
    ln -sfn "$COMFYUI_DIR" /workspace/ComfyUI
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Replaced empty /workspace/ComfyUI with symlink -> $COMFYUI_DIR" >> "$LOG"
  else
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') WARN: /workspace/ComfyUI exists and is non-empty; not changing it." >> "$LOG"
  fi
fi

# Wait for Lustify model + VAE or Lustify completion; proceed on timeout
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

# Install target
TARGET_DIR="$CUSTOM_NODES_DIR/ComfyUI_NAG"
TMP_DIR="${TARGET_DIR}.tmp.$$"

# If already installed and looks valid, skip
if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/node.py" -o -f "$TARGET_DIR/ComfyUI_NAG/node.py" ]; then
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') ComfyUI_NAG already present at $TARGET_DIR" >> "$LOG"
  INSTALLED=true
else
  INSTALLED=false
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  # Try to install from GIT_CLONE_URL
  if [ -n "${GIT_CLONE_URL:-}" ] && command -v git >/dev/null 2>&1; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Attempting git clone $GIT_CLONE_URL -> $TMP_DIR" >> "$LOG"
    git -c http.lowSpeedLimit=0 clone --depth 1 "$GIT_CLONE_URL" "$TMP_DIR" >> "$LOG" 2>&1 || {
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Git clone failed (continuing to other methods)" >> "$LOG"
      rm -rf "$TMP_DIR"
      mkdir -p "$TMP_DIR"
    }
  fi

  # If clone didn't fetch the files from git, try archive download (if provided)
  if [ -z "$(ls -A "$TMP_DIR" 2>/dev/null)" ] && [ -n "${GITHUB_ARCHIVE_URL:-}" ]; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Attempting archive download $GITHUB_ARCHIVE_URL" >> "$LOG"
    curl -sL "$GITHUB_ARCHIVE_URL" -o "$TMP_DIR/archive.tar.gz" >> "$LOG" 2>&1 || true
    tar -xzf "$TMP_DIR/archive.tar.gz" -C "$TMP_DIR" --strip-components=1 >> "$LOG" 2>&1 || true
  fi

  # If still empty, try to find an existing ComfyUI-NAG folder in custom_nodes and symlink it
  if [ -z "$(ls -A "$TMP_DIR" 2>/dev/null)" ]; then
    for d in "$CUSTOM_NODES_DIR"/*; do
      base=$(basename "$d")
      if [ "$base" = "ComfyUI-NAG" ] || [ "$base" = "ComfyUI_NAG" ]; then
        echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Found pre-existing $d, creating symlink $TARGET_DIR -> $d" >> "$LOG"
        ln -sfn "$d" "$TARGET_DIR"
        INSTALLED=true
        break
      fi
    done
  fi

  # If we have files in TMP_DIR, find the directory that actually contains node.py and normalize layout
  if [ -n "$(ls -A "$TMP_DIR" 2>/dev/null)" ]; then
    echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Searching $TMP_DIR for package directory containing node.py" >> "$LOG"
    PKG_PARENT=$(find "$TMP_DIR" -maxdepth 3 -type f -name "node.py" -printf '%h\n' | head -n1 || true)

    if [ -n "$PKG_PARENT" ]; then
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Found node.py in: $PKG_PARENT" >> "$LOG"

      # If PKG_PARENT is exactly a directory named ComfyUI_NAG or ComfyUI-NAG, move that dir to TARGET_DIR
      base=$(basename "$PKG_PARENT")
      mkdir -p "$(dirname "$TARGET_DIR")"

      if [ "$base" = "ComfyUI_NAG" ] || [ "$base" = "ComfyUI-NAG" ]; then
        # move the package directory to target (preserve git if present)
        rm -rf "$TARGET_DIR"
        mv "$PKG_PARENT" "$TARGET_DIR" >> "$LOG" 2>&1 || true
      else
        # node.py is nested under some folder; create target and move package contents into ComfyUI_NAG
        rm -rf "$TARGET_DIR"
        mkdir -p "$TARGET_DIR"
        mv "$PKG_PARENT"/* "$TARGET_DIR"/ 2>>"$LOG" || true
        # If node.py is not in top-level but the package dir name isn't ComfyUI_NAG,
        # ensure package is importable as ComfyUI_NAG by creating a package dir if necessary.
        if [ ! -f "$TARGET_DIR/node.py" ] && [ -d "$TARGET_DIR/ComfyUI_NAG" ]; then
          # move inner ComfyUI_NAG up
          mv "$TARGET_DIR/ComfyUI_NAG"/* "$TARGET_DIR"/ 2>>"$LOG" || true
          rmdir "$TARGET_DIR/ComfyUI_NAG" 2>/dev/null || true
        fi
      fi

      # Move any other helpful top-level files (README/scripts) into TARGET_DIR if they exist at TMP root
      shopt -s dotglob
      for f in "$TMP_DIR"/*; do
        bn=$(basename "$f")
        if [ -e "$f" ] && [ "$bn" != "$(basename "$PKG_PARENT")" ]; then
          mv -f "$f" "$TARGET_DIR"/ 2>/dev/null || true
        fi
      done
      shopt -u dotglob

      # Move .git if present anywhere under tmp into target (so history remains)
      if [ -d "$TMP_DIR/.git" ]; then
        mv -f "$TMP_DIR/.git" "$TARGET_DIR"/ 2>/dev/null || true
      else
        # try locate any nested .git
        nested_git=$(find "$TMP_DIR" -maxdepth 2 -type d -name ".git" -print -quit || true)
        if [ -n "$nested_git" ]; then
          mv -f "$nested_git" "$TARGET_DIR"/ 2>/dev/null || true
        fi
      fi

      INSTALLED=true
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Installed ComfyUI_NAG to $TARGET_DIR" >> "$LOG"
    else
      echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') WARNING: Could not find node.py in cloned tree; leaving $TMP_DIR for inspection" >> "$LOG"
      # keep tmp for inspection
    fi
  fi

  # Clean up tmp if installed
  if $INSTALLED; then
    rm -rf "$TMP_DIR" 2>/dev/null || true
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
exit 0
