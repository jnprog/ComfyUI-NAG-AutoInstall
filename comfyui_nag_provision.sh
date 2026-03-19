#!/bin/bash
set -e

LOG="/workspace/boot.log"
echo "=== ComfyUI-NAG v11 Quick Start ===" | tee -a "$LOG"
date | tee -a "$LOG"

COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

echo "Waiting for ComfyUI folder..." | tee -a "$LOG"
for i in {1..12}; do
  if [ -d "$COMFY" ] && [ -f "$COMFY/main.py" ]; then
    echo "ComfyUI folder ready" | tee -a "$LOG"
    break
  fi
  sleep 5
done

# Nodes + NAG patch
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
  echo "Installing $repo" | tee -a "$LOG"
  git clone https://github.com/$repo.git 2>/dev/null || git -C "${repo##*/}" pull
done

cd ComfyUI-NAG
echo "Applying NAG patches..." | tee -a "$LOG"
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
  sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
fi

cd "$COMFY"
echo "Starting ComfyUI on port 18188..." | tee -a "$LOG"
pkill -9 python 2>/dev/null || true
sleep 3
/venv/main/bin/python main.py --listen 0.0.0.0 --port 18188 --disable-metadata > /workspace/comfyui.log 2>&1 &

echo "=== BOOT COMPLETE ===" | tee -a "$LOG"
echo "Check progress with: tail -f $LOG" | tee -a "$LOG"
