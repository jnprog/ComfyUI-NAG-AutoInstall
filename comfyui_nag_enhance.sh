#!/bin/bash
set -e

LOG="/workspace/comfyui_nag_enhance.log"
mkdir -p /workspace
echo "=== COMFYUI-NAG ENHANCEMENT STARTED (v13 - Clean names + progress) ===" | tee -a "$LOG"
date | tee -a "$LOG"

# === FORCE CORRECT PATH (2026 Vast.ai template) ===
COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

# === MODELS ===
if [ -n "$CIVITAI_TOKEN" ]; then
    echo "Downloading Lustify SDXL NSFW Inpainting..." | tee -a "$LOG"
    curl --progress-bar -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
        "https://civitai.com/api/download/models/573152" \
        -o "$COMFY/models/checkpoints/lustify_sdxl_olt_inpainting.safetensors" \
        --write-out "\nDownloaded: %{size_download} bytes\nSpeed: %{speed_download} bytes/s\nTime: %{time_total}s\nHTTP: %{http_code}\n" \
        | tee -a "$LOG"
    echo "✅ Lustify model downloaded successfully" | tee -a "$LOG"
else
    echo "WARNING: CIVITAI_TOKEN not set – skipping Lustify" | tee -a "$LOG"
fi

echo "Downloading SDXL VAE..." | tee -a "$LOG"
curl --progress-bar -L \
    "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
    -o "$COMFY/models/vae/sdxl_vae.safetensors" \
    --write-out "\nDownloaded: %{size_download} bytes\nSpeed: %{speed_download} bytes/s\nTime: %{time_total}s\nHTTP: %{http_code}\n" \
    | tee -a "$LOG"

# === WORKFLOWS – clean names ===
echo "Downloading workflows (clean names)..." | tee -a "$LOG"
cd "$COMFY/user/default/workflows"

# NON-DMD2
curl -L -o "LUSTIFY_SDXL_OLT_INPAINTING_NON_DMD2.json" \
    "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json" \
    --progress-bar --write-out "\nDownloaded NON-DMD2: %{size_download} bytes\n" | tee -a "$LOG"

# DMD2
curl -L -o "LUSTIFY_SDXL_OLT_INPAINTING_DMD2.json" \
    "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json" \
    --progress-bar --write-out "\nDownloaded DMD2: %{size_download} bytes\n" | tee -a "$LOG"

echo "✅ Workflows downloaded with clean filenames" | tee -a "$LOG"

# === CUSTOM NODES ===
echo "Installing nodes..." | tee -a "$LOG"
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
    echo "→ $repo" | tee -a "$LOG"
    git clone https://github.com/$repo.git 2>/dev/null || git -C "${repo##*/}" pull
done

# === NAG PATCHES ===
cd ComfyUI-NAG
echo "Applying NAG patches..." | tee -a "$LOG"
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
    sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
fi
echo "✓ ComfyUI-NAG patched" | tee -a "$LOG"

# === RESTART ===
echo "Restarting ComfyUI..." | tee -a "$LOG"
pkill -9 python 2>/dev/null || true
sleep 3
cd "$COMFY"
/venv/main/bin/python main.py --listen 0.0.0.0 --port 18188 --disable-metadata > /workspace/comfyui.log 2>&1 &

echo "=== ENHANCEMENT COMPLETED (v13) ===" | tee -a "$LOG"
echo "Refresh browser in 30–60 seconds" | tee -a "$LOG"
