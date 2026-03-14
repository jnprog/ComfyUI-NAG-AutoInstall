#!/usr/bin/env bash
set -euo pipefail

LOG="/var/log/portal/comfyui_nag_install.log"
mkdir -p "$(dirname "$LOG")"
echo "=== ComfyUI-NAG installer start: $(date -u) ===" >> "$LOG"
echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') Script invoked: $0" >> "$LOG"

# Configurable vars (can be passed as env)
COMFYUI_DIR="${COMFYUI_DIR:-/opt/workspace-internal/ComfyUI}"
CUSTOM_NODES_DIR="$COMFYUI_DIR/custom_nodes"
# Default upstream (ChenDarYen) - you confirmed this should be default
UPSTREAM_NODE_REPO="${UPSTREAM_NODE_REPO:-https://github.com/ChenDarYen/ComfyUI-NAG.git}"
GIT_BRANCH="${GIT_BRANCH:-main}"
INSTALL_WAIT_TIMEOUT="${INSTALL_WAIT_TIMEOUT:-1800}" # seconds
INSTALL_POLL_INTERVAL="${INSTALL_POLL_INTERVAL:-15}"
LUSTIFY_LOG="${LUSTIFY_LOG:-/workspace/install_sdxl_vae.log}"

# Behavior flags (env)
# If set to "1", allow escalation to SIGKILL when graceful restart times out
FORCE_RESTART="${FORCE_RESTART:-0}"
# If set to "1", SKIP any restart attempts (useful when restarts are centrally managed)
SKIP_RESTART="${SKIP_RESTART:-0}"

log() {
  echo "$(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >> "$LOG"
}

log "Using COMFYUI_DIR=$COMFYUI_DIR"
mkdir -p "$CUSTOM_NODES_DIR"

# Ensure /workspace/ComfyUI points to authoritative COMFYUI_DIR
if [ ! -e /workspace/ComfyUI ]; then
  mkdir -p "$(dirname "$COMFYUI_DIR")"
  mkdir -p "$COMFYUI_DIR"
  ln -sfn "$COMFYUI_DIR" /workspace/ComfyUI
  log "Created symlink /workspace/ComfyUI -> $COMFYUI_DIR"
elif [ -L /workspace/ComfyUI ]; then
  log "/workspace/ComfyUI already a symlink"
else
  if [ -z "$(ls -A /workspace/ComfyUI 2>/dev/null || true)" ]; then
    rm -rf /workspace/ComfyUI
    ln -sfn "$COMFYUI_DIR" /workspace/ComfyUI
    log "Replaced empty /workspace/ComfyUI with symlink -> $COMFYUI_DIR"
  else
    log "WARN: /workspace/ComfyUI exists and is non-empty; not changing it."
  fi
fi

# Wait for Lustify model + VAE or Lustify completion; proceed on timeout
waited=0
LUSTIFY_MODEL_OPT="$COMFYUI_DIR/models/checkpoints/lustifySDXLNSFW_oltINPAINTING.safetensors"
VAE_FILE_OPT="$COMFYUI_DIR/models/vae/sdxl_vae.safetensors"
LUSTIFY_MODEL_WS="/workspace/ComfyUI/models/checkpoints/lustifySDXLNSFW_oltINPAINTING.safetensors"
VAE_FILE_WS="/workspace/ComfyUI/models/vae/sdxl_vae.safetensors"

log "Waiting up to ${INSTALL_WAIT_TIMEOUT}s for Lustify model & VAE..."
while true; do
  if ( [ -s "$LUSTIFY_MODEL_OPT" ] && [ -s "$VAE_FILE_OPT" ] ) || ( [ -s "$LUSTIFY_MODEL_WS" ] && [ -s "$VAE_FILE_WS" ] ); then
    log "Models found."
    break
  fi
  if grep -q "LUSTIFY ComfyUI setup completed" "$LUSTIFY_LOG" 2>/dev/null; then
    log "Lustify script reported completion in $LUSTIFY_LOG"
    break
  fi
  if [ "$waited" -ge "$INSTALL_WAIT_TIMEOUT" ]; then
    log "TIMEOUT waiting for Lustify after ${waited}s — proceeding anyway"
    break
  fi
  sleep "$INSTALL_POLL_INTERVAL"
  waited=$((waited + INSTALL_POLL_INTERVAL))
done

TARGET_DIR="$CUSTOM_NODES_DIR/ComfyUI_NAG"
TMP_DIR="${TARGET_DIR}.tmp.$$"

# Idempotent install: if TARGET_DIR exists and is a git repo do git pull --ff-only; otherwise re-clone shallow
log "Beginning idempotent install for ComfyUI_NAG -> $TARGET_DIR"

if [ -d "$TARGET_DIR" ]; then
  if command -v git >/dev/null 2>&1 && git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "Detected git repo at $TARGET_DIR; attempting git -C $TARGET_DIR pull --ff-only origin $GIT_BRANCH"
    set +e
    git -C "$TARGET_DIR" pull --ff-only origin "$GIT_BRANCH" >> "$LOG" 2>&1
    PULL_RC=$?
    set -e
    if [ $PULL_RC -eq 0 ]; then
      log "git pull --ff-only succeeded"
    else
      log "git pull --ff-only failed (rc=$PULL_RC); removing $TARGET_DIR and will re-clone"
      rm -rf "$TARGET_DIR"
    fi
  else
    log "Existing $TARGET_DIR is not a git repo; removing to re-clone"
    rm -rf "$TARGET_DIR"
  fi
fi

# If target doesn't exist now, shallow clone upstream repo into tmp and move into place
if [ ! -d "$TARGET_DIR" ]; then
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  if command -v git >/dev/null 2>&1; then
    log "Cloning upstream node repo $UPSTREAM_NODE_REPO (branch $GIT_BRANCH) into tmp dir $TMP_DIR"
    set +e
    git -c http.lowSpeedLimit=0 clone --depth 1 --branch "$GIT_BRANCH" "$UPSTREAM_NODE_REPO" "$TMP_DIR" >> "$LOG" 2>&1
    GIT_EXIT=$?
    set -e
    if [ $GIT_EXIT -ne 0 ]; then
      log "ERROR: git clone returned $GIT_EXIT. Cleaning tmp and aborting."
      rm -rf "$TMP_DIR"
      echo "=== ComfyUI-NAG installer end (clone failed): $(date -u) ===" >> "$LOG"
      exit 3
    fi
  else
    log "ERROR: git not found; cannot clone upstream node repository"
    echo "=== ComfyUI-NAG installer end (git missing): $(date -u) ===" >> "$LOG"
    exit 4
  fi

  log "Searching for node.py in cloned tree"
  PKG_PARENT=$(find "$TMP_DIR" -maxdepth 3 -type f -name "node.py" -printf '%h\n' | head -n1 || true)
  if [ -n "$PKG_PARENT" ]; then
    log "Found node.py in: $PKG_PARENT"
    base=$(basename "$PKG_PARENT")
    mkdir -p "$(dirname "$TARGET_DIR")"
    if [ "$base" = "ComfyUI_NAG" ] || [ "$base" = "ComfyUI-NAG" ]; then
      log "Moving package directory $PKG_PARENT -> $TARGET_DIR"
      rm -rf "$TARGET_DIR"
      mv "$PKG_PARENT" "$TARGET_DIR" >> "$LOG" 2>&1 || true
    else
      log "Creating $TARGET_DIR and moving package contents"
      rm -rf "$TARGET_DIR"
      mkdir -p "$TARGET_DIR"
      mv "$PKG_PARENT"/* "$TARGET_DIR"/ 2>>"$LOG" || true
      if [ ! -f "$TARGET_DIR/node.py" ] && [ -d "$TARGET_DIR/ComfyUI_NAG" ]; then
        mv "$TARGET_DIR/ComfyUI_NAG"/* "$TARGET_DIR"/ 2>>"$LOG" || true
        rmdir "$TARGET_DIR/ComfyUI_NAG" 2>/dev/null || true
      fi
    fi

    # Move any other helpful top-level files into target
    shopt -s dotglob
    for f in "$TMP_DIR"/*; do
      bn=$(basename "$f")
      if [ -e "$f" ] && [ "$bn" != "$(basename "$PKG_PARENT")" ]; then
        mv -f "$f" "$TARGET_DIR"/ 2>/dev/null || true
      fi
    done
    shopt -u dotglob

    # Move .git if present
    if [ -d "$TMP_DIR/.git" ]; then
      mv -f "$TMP_DIR/.git" "$TARGET_DIR"/ 2>/dev/null || true
    else
      nested_git=$(find "$TMP_DIR" -maxdepth 2 -type d -name ".git" -print -quit || true)
      if [ -n "$nested_git" ]; then
        mv -f "$nested_git" "$TARGET_DIR"/ 2>/dev/null || true
      fi
    fi

    log "Installed ComfyUI_NAG to $TARGET_DIR"
  else
    log "ERROR: Could not find node.py in cloned tree; leaving tmp for inspection at $TMP_DIR"
    echo "=== ComfyUI-NAG installer end (node.py not found) : $(date -u) ===" >> "$LOG"
    exit 5
  fi

  rm -rf "$TMP_DIR" 2>/dev/null || true
fi

# Apply compatibility patch: replace imports in chroma/layers.py and chroma/model.py
log "Applying compatibility patch(s) (comfy.ldm.chroma.layers -> comfy.ldm.flux.layers) if needed"
PATCHED_FILES=()
for rel in "chroma/layers.py" "chroma/model.py"; do
  f="$TARGET_DIR/$rel"
  if [ -f "$f" ]; then
    log "Processing $f"
    cp -a "$f" "${f}.orig" >> "$LOG" 2>&1 || true
    sed -E -i 's/\bcomfy\.ldm\.chroma\.layers\b/comfy.ldm.flux.layers/g' "$f" || true
    sed -E -i 's/\bfrom comfy\.ldm\.chroma\.layers\b/from comfy.ldm.flux.layers/g' "$f" || true
    sed -E -i 's/\bcomfy\.ldm\.chroma\b/comfy.ldm.flux/g' "$f" || true
    if ! cmp -s "${f}.orig" "$f"; then
      log "File $f modified; appending diff to log"
      echo "----- DIFF for $rel -----" >> "$LOG"
      diff -u "${f}.orig" "$f" >> "$LOG" 2>&1 || true
      echo "----- END DIFF -----" >> "$LOG"
      PATCHED_FILES+=("$rel")
    else
      log "No changes required for $f"
      rm -f "${f}.orig" 2>/dev/null || true
    fi
  else
    log "File not present (skipping): $f"
  fi
done

# Ownership & permissions: match an existing node if available
log "Setting ownership/permissions to match an existing custom node (if any)"
EXISTING_NODE_REF=$(find "$CUSTOM_NODES_DIR" -maxdepth 1 -mindepth 1 -type d ! -name "$(basename "$TARGET_DIR")" | head -n1 || true)
if [ -n "$EXISTING_NODE_REF" ]; then
  log "Using reference node: $EXISTING_NODE_REF"
  if command -v chown >/dev/null 2>&1; then
    chown --reference="$EXISTING_NODE_REF" -R "$TARGET_DIR" >> "$LOG" 2>&1 || true
  fi
  if command -v chmod >/dev/null 2>&1; then
    chmod --reference="$EXISTING_NODE_REF" -R "$TARGET_DIR" >> "$LOG" 2>&1 || true
  fi
  log "Ownership/permissions adjusted to match $EXISTING_NODE_REF"
else
  log "No existing custom node found to reference for ownership/permissions; leaving defaults"
fi

# Programmatic import test using the exact snippet you requested.
log "Running required programmatic import test (captures output)"
IMPORT_TEST_OUT=$(python3 - <<'PY' 2>&1 || true
import importlib, traceback
try:
    m = importlib.import_module('ComfyUI_NAG.node')
    print(type(getattr(m, 'NAGDoubleStreamBlock', None)), getattr(m, 'NAGDoubleStreamBlock', None))
except Exception:
    traceback.print_exc()
    raise
PY
)
PY_RC=$? || true

# Append import test output to log
echo "----- Programmatic import test output -----" >> "$LOG"
echo "$IMPORT_TEST_OUT" >> "$LOG"
echo "----- End import test output -----" >> "$LOG"
# Also echo to console for immediate visibility
echo "$IMPORT_TEST_OUT"

# If python raised an exception, the shell capture will set non-zero; treat that as failure
if [ $PY_RC -ne 0 ]; then
  log "Import test FAILED (python exited with $PY_RC). Appending tracebacks/diffs and exiting non-zero."

  # Append modified files or diffs for inspection
  for rel in "chroma/layers.py" "chroma/model.py"; do
    f="$TARGET_DIR/$rel"
    if [ -f "${f}.orig" ] && [ -f "$f" ]; then
      echo "===== DIFF for $rel (orig -> current) =====" >> "$LOG"
      diff -u "${f}.orig" "$f" >> "$LOG" 2>&1 || true
      echo "===== END DIFF =====" >> "$LOG"
    elif [ -f "$f" ]; then
      echo "===== Current contents of $rel =====" >> "$LOG"
      sed -n '1,400p' "$f" >> "$LOG" 2>&1 || true
      echo "===== END contents =====" >> "$LOG"
    else
      echo "===== $rel not present =====" >> "$LOG"
    fi
  done

  echo "Import traceback and output (last shown above)." >> "$LOG"
  echo "=== ComfyUI-NAG installer end (import failed): $(date -u) ===" >> "$LOG"
  echo "ERROR: ComfyUI_NAG import test failed. See $LOG for traceback and diffs." >&2
  exit 6
fi

log "Import test succeeded (python exit code 0)."

# restart_comfyui: graceful restart logic (systemd preferred; otherwise SIGTERM -> wait for new PID)
restart_comfyui() {
  log "restart_comfyui invoked (SKIP_RESTART=$SKIP_RESTART, FORCE_RESTART=$FORCE_RESTART)"
  if [ "${SKIP_RESTART:-0}" = "1" ]; then
    log "SKIP_RESTART=1 set; skipping restart attempt."
    return 0
  fi

  # Attempt systemd restart first if service exists
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-units --type=service --all | grep -qi '^comfyui\.service'; then
      log "Detected systemd comfyui.service; attempting systemctl restart comfyui.service"
      if systemctl restart comfyui.service >> "$LOG" 2>&1; then
        log "systemctl restart comfyui.service succeeded"
        return 0
      else
        log "systemctl restart comfyui.service returned non-zero"
        # fallthrough to process-level attempt
      fi
    else
      log "No comfyui systemd service detected"
    fi
  else
    log "systemctl not available"
  fi

  # Identify ComfyUI process PIDs (try several patterns: main.py, comfyui, ComfyUI main)
  PIDS="$(pgrep -f 'comfyui|ComfyUI|main.py' || true)"
  if [ -z "$PIDS" ]; then
    log "No comfyui process found via pgrep; nothing to terminate; returning success"
    return 0
  fi
  log "Found comfyui-related PIDs: $PIDS"

  # Save old PIDs, send SIGTERM
  OLD_PIDS="$PIDS"
  log "Sending SIGTERM to PIDs: $OLD_PIDS"
  if kill -TERM $OLD_PIDS >> "$LOG" 2>&1; then
    log "SIGTERM sent"
  else
    log "Failed to send SIGTERM (non-fatal here)"
  fi

  # Wait up to 30s for new PID(s) to appear (supervisor or process may respawn)
  for i in $(seq 1 30); do
    sleep 1
    NEW_PIDS="$(pgrep -f 'comfyui|ComfyUI|main.py' || true)"
    if [ -n "$NEW_PIDS" ] && [ "$NEW_PIDS" != "$OLD_PIDS" ]; then
      log "Detected new comfyui PID(s): $NEW_PIDS (old: $OLD_PIDS)"
      return 0
    fi
  done

  log "No restart detected after timeout"

  if [ "${FORCE_RESTART:-0}" = "1" ]; then
    log "FORCE_RESTART=1 set — escalating: sending SIGKILL to old PIDs"
    if kill -KILL $OLD_PIDS >> "$LOG" 2>&1; then
      log "SIGKILL sent to old PIDs; waiting briefly for supervisor to restart"
      sleep 5
      NEW_PIDS="$(pgrep -f 'comfyui|ComfyUI|main.py' || true)"
      if [ -n "$NEW_PIDS" ]; then
        log "Detected new comfyui PIDs after forced kill: $NEW_PIDS"
        return 0
      else
        log "No comfyui process found after forced kill"
        return 2
      fi
    else
      log "Failed to send SIGKILL"
      return 2
    fi
  fi

  log "Not forcing restart (FORCE_RESTART not set). Please restart comfyui manually or set FORCE_RESTART=1 to allow forced restart."
  return 2
}

# Attempt restart if import succeeded
if [ "${SKIP_RESTART:-0}" != "1" ]; then
  restart_comfyui
  RESTART_RC=$? || true
  if [ "$RESTART_RC" -eq 0 ]; then
    log "Restart attempt succeeded or not needed (rc=$RESTART_RC). Will verify comfyui.log for import times block."
    # Wait a few seconds for logs to appear
    sleep 5
    if [ -f /var/log/portal/comfyui.log ]; then
      log "Attempting to capture 'Import times for custom nodes' block from /var/log/portal/comfyui.log"
      grep -nA50 "Import times for custom nodes" /var/log/portal/comfyui.log >> "$LOG" 2>&1 || log "grep returned non-zero (maybe block not present yet)"
    else
      log "/var/log/portal/comfyui.log not present to check import times block"
    fi
  else
    log "Restart attempt returned non-zero (rc=$RESTART_RC). See above logs; operator action may be needed."
  fi
else
  log "SKIP_RESTART=1 set; skipping restart verification step. Please restart ComfyUI to load the node if necessary."
fi

log "ComfyUI-NAG install completed successfully."
echo "=== ComfyUI-NAG installer end (success): $(date -u) ===" >> "$LOG"
exit 0
