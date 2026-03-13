#!/usr/bin/env bash
set -euo pipefail

# ComfyUI-NAG installer (idempotent, robust for Vast.ai On-start)
# Usage (On-start): set GIT_CLONE_URL to your repo clone URL and run this script.
#
# Logs: /var/log/portal/comfyui_nag_install.log

LOG=/var/log/portal/comfyui_nag_install.log
mkdir -p "$(dirname "$LOG")"
exec >>"$LOG" 2>&1

echo "=== ComfyUI-NAG installer start: $(date) ==="

# Configurable inputs (can be provided as env vars)
GIT_CLONE_URL="${GIT_CLONE_URL:-}"
GITHUB_ARCHIVE_URL="${GITHUB_ARCHIVE_URL:-}"   # optional tarball URL (github archive)
DEST_PARENT="/workspace/ComfyUI/custom_nodes"
DEST="$DEST_PARENT/ComfyUI_NAG"
LOCAL_SRC="/opt/workspace-internal/ComfyUI/custom_nodes/ComfyUI_NAG"

mkdir -p "$DEST_PARENT"

_cleanup_tmp() {
  [ -n "${TMPDIR:-}" ] && rm -rf "${TMPDIR}" || true
}

# Helper: robust move-of-package
_move_package_to_dest() {
  src="$1"
  echo "Attempting to install from: $src"
  # If src is a folder containing ComfyUI_NAG/ (repo layout)
  if [ -d "$src/ComfyUI_NAG" ]; then
    rm -rf "$DEST"
    mv "$src/ComfyUI_NAG" "$DEST" || true
    echo "Moved $src/ComfyUI_NAG -> $DEST"
    return 0
  fi

  # If src itself is a package folder (contains __init__.py and node.py)
  if [ -f "$src/__init__.py" ] || [ -f "$src/node.py" ]; then
    rm -rf "$DEST"
    mkdir -p "$DEST"
    mv "$src"/* "$DEST"/ || true
    echo "Moved package files from $src -> $DEST"
    return 0
  fi

  # Otherwise try to detect a single top-level directory inside src and use it
  topdir=$(find "$src" -maxdepth 1 -mindepth 1 -type d -print -quit || true)
  if [ -n "$topdir" ]; then
    if [ -d "$topdir/ComfyUI_NAG" ]; then
      rm -rf "$DEST"
      mv "$topdir/ComfyUI_NAG" "$DEST" || true
      echo "Moved $topdir/ComfyUI_NAG -> $DEST"
      return 0
    fi
    # If topdir looks like the package
    if [ -f "$topdir/__init__.py" ] || [ -f "$topdir/node.py" ]; then
      rm -rf "$DEST"
      mkdir -p "$DEST"
      mv "$topdir"/* "$DEST"/ || true
      echo "Moved package files from $topdir -> $DEST"
      return 0
    fi
  fi

  echo "No recognizable ComfyUI_NAG package found in $src"
  return 1
}

# Acquire source code
TMPDIR=""
if [ -n "$GIT_CLONE_URL" ]; then
  echo "GIT_CLONE_URL provided: $GIT_CLONE_URL"
  if command -v git >/dev/null 2>&1; then
    TMPDIR="$(mktemp -d /tmp/comfyui_nag.XXXX)"
    trap _cleanup_tmp EXIT
    echo "Cloning to temporary dir: $TMPDIR"
    if git clone --depth 1 "$GIT_CLONE_URL" "$TMPDIR/repo"; then
      if _move_package_to_dest "$TMPDIR/repo"; then
        echo "Install from git clone succeeded"
      else
        echo "Install from git clone failed to find package layout"
      fi
    else
      echo "git clone failed for $GIT_CLONE_URL"
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
    if _move_package_to_dest "$TMPDIR/ex"; then
      echo "Install from archive succeeded"
    else
      echo "Install from archive failed to find package layout"
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

# If destination exists, ensure permissions
if [ -d "$DEST" ]; then
  chmod -R a+rX "$DEST" || true
  echo "Set permissions on $DEST"
else
  echo "Destination $DEST does not exist after acquisition attempt"
fi

# Apply minimal import patch if required (safe & idempotent)
LAYER="$DEST/chroma/layers.py"
if [ -f "$LAYER" ]; then
  echo "Found file: $LAYER"
  if [ ! -f "$LAYER.bak" ]; then
    cp -a "$LAYER" "$LAYER.bak" || true
    echo "Backup created: $LAYER.bak"
  fi
  if grep -q "from comfy.ldm.chroma.layers import" "$LAYER"; then
    echo "Patching imports in $LAYER"
    sed -i 's|from comfy.ldm.chroma.layers import|from comfy.ldm.flux.layers import|g' "$LAYER" || true
  else
    echo "No comfy.ldm.chroma.layers import found; patch not required"
  fi
else
  echo "Layer file $LAYER not present; skipping patch"
fi

# Determine Python interpreter to use for import test:
# 1) Python used by running main.py (if running)
# 2) /venv/main/bin/python
# 3) python3
# 4) python
PYTHON_CMD=""
COMFY_PID=$(pgrep -f "main.py" | head -n1 || true)
if [ -n "$COMFY_PID" ] && [ -x "/proc/$COMFY_PID/exe" ]; then
  PYTHON_CMD="/proc/$COMFY_PID/exe"
  echo "Will use running ComfyUI interpreter: $PYTHON_CMD (pid $COMFY_PID)"
elif [ -x "/venv/main/bin/python" ]; then
  PYTHON_CMD="/venv/main/bin/python"
  echo "Using /venv/main/bin/python as fallback: $PYTHON_CMD"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD="python3"
  echo "Using python3 from PATH"
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD="python"
  echo "Using python from PATH"
else
  echo "No python interpreter available for import test; skipping import test"
  PYTHON_CMD=""
fi

# Quick non-fatal import test (does not abort script on failure)
if [ -n "$PYTHON_CMD" ]; then
  echo "Running lightweight import test using: $PYTHON_CMD"
  set +e
  "$PYTHON_CMD" - <<'PY'
import sys,traceback,importlib
# Ensure ComfyUI/custom_nodes is on sys.path
sys.path.insert(0, "/workspace/ComfyUI")
sys.path.insert(0, "/workspace/ComfyUI/custom_nodes")
try:
    m = importlib.import_module("ComfyUI_NAG.node")
    print("IMPORT-OK", getattr(m, "__file__", "<​no __file>"))
    print("info():", getattr(m, "info", lambda: "<​no info>")())
except Exception:
    print("IMPORT-FAILED")
    traceback.print_exc()
PY
  RET=$?
  set -e
  echo "Import test exit code: $RET"
else
  echo "Skipping import test (no interpreter available)"
fi

echo "=== ComfyUI-NAG installer end: $(date) ==="
