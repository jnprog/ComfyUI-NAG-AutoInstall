#!/bin/bash
set -e

LOG="/workspace/comfyui_nag_enhance.log"
mkdir -p /workspace
echo "=== COMFYUI-NAG ENHANCEMENT STARTED (v12 - Final) ===" | tee -a "$LOG"
date | tee -a "$LOG"

# === FORCE CORRECT PATH (2026 Vast.ai template) ===
COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

# === MODELS ===
if [ -n "$CIVITAI_TOKEN" ]; then
  echo "Downloading Lustify SDXL NSFW Inpainting..." | tee -a "$LOG"
  curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
    "https://civitai.com/api/download/models/573152" \
    -o "$COMFY/models/checkpoints/lustify_sdxl_olt_inpainting.safetensors" | tee -a "$LOG"
  echo "✅ Lustify model downloaded successfully" | tee -a "$LOG"
else
  echo "WARNING: CIVITAI_TOKEN not set – skipping Lustify" | tee -a "$LOG"
fi

echo "Downloading SDXL VAE..." | tee -a "$LOG"
curl -L "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
  -o "$COMFY/models/vae/sdxl_vae.safetensors" | tee -a "$LOG"

# === WORKFLOWS (URL-encoded) ===
echo "Downloading workflows..." | tee -a "$LOG"
cd "$COMFY/user/default/workflows"
curl -L -O "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"
curl -L -O "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"
echo "✅ Workflows downloaded" | tee -a "$LOG"

# === CUSTOM NODES ===
echo "Installing nodes..." | tee -a "$LOG"
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
  git clone https://github.com/$repo.git 2>/dev/null || git -C "${repo##*/}" pull
done

# === NAG PATCHES (exact working ones from your logs) ===
cd ComfyUI-NAG
echo "Applying NAG patches..." | tee -a "$LOG"
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
  sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
fi
echo "✓ ComfyUI-NAG installed and patched" | tee -a "$LOG"

# === RESTART COMFYUI ===
echo "Restarting ComfyUI..." | tee -a "$LOG"
pkill -9 python 2>/dev/null || true
sleep 3
cd "$COMFY"
/venv/main/bin/python main.py --listen 0.0.0.0 --port 18188 --disable-metadata > /workspace/comfyui.log 2>&1 &

echo "=== ENHANCEMENT COMPLETED ===" | tee -a "$LOG"
echo "Please wait 30-60 seconds and refresh http://localhost:18188 (or Open button)" | tee -a "$LOG"
