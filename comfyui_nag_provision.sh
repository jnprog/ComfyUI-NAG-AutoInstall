#!/bin/bash
set -e

echo "=== ComfyUI-NAG Boot Script (v10 - Fast Start) ==="

COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

# Nodes (fast)
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
  git clone https://github.com/$repo.git 2>/dev/null || git -C "${repo##*/}" pull
done

# NAG patch
cd ComfyUI-NAG
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
  sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
fi

# Start ComfyUI
cd "$COMFY"
echo "Starting ComfyUI on port 18188..."
/venv/main/bin/python main.py \
  --listen 0.0.0.0 \
  --port 18188 \
  --disable-metadata > /workspace/comfyui.log 2>&1 &

echo "=== BOOT COMPLETE ==="
echo "ComfyUI should be ready in 30-60 seconds."
