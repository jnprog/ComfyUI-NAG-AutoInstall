#!/usr/bin/env bash
set -euo pipefail

# ComfyUI-NAG installer (idempotent)
# Usage:
#  - Provide GIT_CLONE_URL env var to clone from a git repo (recommended)
#  - Otherwise the script will copy from /opt/workspace-internal/ComfyUI/custom_nodes/ComfyUI_NAG if present
#  - Logs: /var/log/portal/comfyui_nag_install.log
#
# Example one-line run (from On-start script):
#  GIT_CLONE_URL="https://gist.github.com/<user>/<gist_id>.git" bash /tmp/ComfyUI-NAG_Script.sh

LOG=/var/log/portal/comfyui_nag_install.log
exec >> "$LOG" 2>&1

echo "=== ComfyUI-NAG installer start: $(date) ==="

# Configurable inputs (can be provided as env vars)
GIT_CLONE_URL="${GIT_CLONE_URL:-}"
GITHUB_ARCHIVE_URL="${GITHUB_ARCHIVE_URL:-}"   # optional tarball URL (github archive)
DEST="/workspace/ComfyUI/custom_nodes/ComfyUI_NAG"
LOCAL_SRC="/opt/workspace-internal/ComfyUI/custom_nodes/ComfyUI_NAG"

# Ensure runtime custom_nodes exists
mkdir -p /workspace/ComfyUI/custom_nodes

# Helper: remove temporary state if partially present
_cleanup_tmp() {
  [ -n "${TMPDIR:-}" ] && rm -rf "${TMPDIR}" || true
}

# Acquire source code
if [ -n "$GIT_CLONE_URL" ]; then
  echo "GIT_CLONE_URL provided: $GIT_CLONE_URL"
  if command -v git >/dev/null 2>&1; then
    if [ -d "$DEST/.git" ]; then
      echo "Updating existing Git repo at $DEST"
      git -C "$DEST" fetch --all --depth=1 || true
      git -C "$DEST" reset --hard origin/HEAD || true
    else
      echo "Cloning into $DEST"
      rm -rf "$DEST"
      git clone --depth 1 "$GIT_CLONE_URL" "$DEST" || {
        echo "git clone failed for $GIT_CLONE_URL"
      }
    fi
  else
    echo "git not available in PATH; skipping git clone"
  fi

elif [ -n "$GITHUB_ARCHIVE_URL" ]; then
  echo "GITHUB_ARCHIVE_URL provided: $GITHUB_ARCHIVE_URL"
  TMPDIR="$(mktemp -d /tmp/comfyui_nag.XXXX)"
  trap _cleanup_tmp EXIT
  echo "Downloading archive..."
  if curl -fsSL "$GITHUB_ARCHIVE_URL" -o "$TMPDIR/archive.tar.gz"; then
    mkdir -p "$TMPDIR/ex" && tar -xzf "$TMPDIR/archive.tar.gz" -C "$TMPDIR/ex" || true
    # Move top-level contents into DEST
    rm -rf "$DEST"
    mkdir -p "$DEST"
    topdir=$(find "$TMPDIR/ex" -mindepth 1 -maxdepth 1 -type d -print -quit || true)
    if [ -n "$topdir" ]; then
      echo "Moving archive contents from $topdir -> $DEST"
      mv "$topdir"/* "$DEST"/ || true
    else
      echo "No directory found in archive; copying all files"
      mv "$TMPDIR/ex"/* "$DEST"/ || true
    fi
  else
    echo "Failed to download archive from $GITHUB_ARCHIVE_URL"
  fi

elif [ -d "$LOCAL_SRC" ]; then
  echo "Copying local source from $LOCAL_SRC to $DEST"
  rm -rf "$DEST"
  cp -a "$LOCAL_SRC" "$DEST"
else
  echo "No source found (GIT_CLONE_URL unset, GITHUB_ARCHIVE_URL unset, and $LOCAL_SRC missing). Skipping install."
fi

# Apply minimal import patch if required (safe & idempotent)
LAYER="$DEST/chroma/layers.py"
if [ -f "$LAYER" ]; then
  echo "Found file: $LAYER"
  # Backup if not already backed up
  if [ ! -f "$LAYER.bak" ]; then
    cp -a "$LAYER" "$LAYER.bak" || true
    echo "Backup created: $LAYER.bak"
  fi

  # Replace imports that reference comfy.ldm.chroma.layers -> comfy.ldm.flux.layers
  if grep -q "from comfy.ldm.chroma.layers import" "$LAYER"; then
    echo "Patching imports in $LAYER"
    sed -i 's|from comfy.ldm.chroma.layers import|from comfy.ldm.flux.layers import|g' "$LAYER" || true
  else
    echo "No comfy.ldm.chroma.layers import found; patch not required"
  fi
else
  echo "Layer file $LAYER not present; skipping patch"
fi

# Ensure permissive read/execute bits so ComfyUI can import
if [ -d "$DEST" ]; then
  chmod -R a+rX "$DEST" || true
  echo "Set permissions on $DEST"
fi

# Quick non-fatal import test (does not abort script on failure)
echo "Running lightweight import test..."
/venv/main/bin/python - <<'PY' || true
import sys,traceback,importlib
sys.path.insert(0, "/workspace/ComfyUI")
sys.path.insert(0, "/workspace/ComfyUI/custom_nodes")
try:
    m = importlib.import_module("ComfyUI_NAG.node")
    print("IMPORT-OK", getattr(m, "__file__", "<​no __file>"))
except Exception:
    print("IMPORT-FAILED")
    traceback.print_exc()
PY

echo "=== ComfyUI-NAG installer end: $(date) ==="