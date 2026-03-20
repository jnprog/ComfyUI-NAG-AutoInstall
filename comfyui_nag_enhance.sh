#!/bin/bash
set -e

LOG="/workspace/comfyui_nag_enhance.log"
mkdir -p /workspace
echo "=== COMFYUI-NAG ENHANCEMENT STARTED (v18 - REAL-TIME PROGRESS + your DMD2 LoRA) ===" | tee -a "$LOG"
date | tee -a "$LOG"

# FORCE CORRECT PATH
COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae,upscale_models,loras},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

# ===================== LUSTIFY MODEL =====================
MODEL_PATH="$COMFY/models/checkpoints/lustify_sdxl_olt_inpainting.safetensors"
MIN_SIZE=6500000000

echo "=== Downloading Lustify OLT Inpainting (expected ~6.5 GB) ===" | tee -a "$LOG"
DOWNLOADED=false

if [ -n "$CIVITAI_TOKEN" ]; then
  for method in bearer token; do
    echo "→ Trying Civitai ($method method)..." | tee -a "$LOG"
    rm -f "$MODEL_PATH.tmp"
    if [ "$method" = "bearer" ]; then
      curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
        "https://civitai.com/api/download/models/573152" \
        -o "$MODEL_PATH.tmp" --progress-bar 2>&1 | tee -a "$LOG"
    else
      curl -L "https://civitai.com/api/download/models/573152?token=$CIVITAI_TOKEN" \
        -o "$MODEL_PATH.tmp" --progress-bar 2>&1 | tee -a "$LOG"
    fi
    SIZE=$(stat -c %s "$MODEL_PATH.tmp" 2>/dev/null || echo 0)
    if [ $SIZE -gt $MIN_SIZE ]; then
      mv "$MODEL_PATH.tmp" "$MODEL_PATH"
      echo "✅ SUCCESS: Civitai Lustify download ($((SIZE/1024/1024)) MB)" | tee -a "$LOG"
      DOWNLOADED=true
      break
    else
      echo "⚠️ Civitai blocked — trying next method..." | tee -a "$LOG"
      rm -f "$MODEL_PATH.tmp"
    fi
  done
fi

if [ "$DOWNLOADED" = false ] || [ ! -f "$MODEL_PATH" ] || [ $(stat -c %s "$MODEL_PATH" 2>/dev/null || echo 0) -lt $MIN_SIZE ]; then
  echo "→ Falling back to Google Drive mirror with gdown..." | tee -a "$LOG"
  rm -f "$MODEL_PATH" "$MODEL_PATH.tmp"
  echo "→ Installing gdown..." | tee -a "$LOG"
  /venv/main/bin/python -m pip install gdown --break-system-packages 2>/dev/null || python3 -m pip install gdown --break-system-packages || true
  echo "→ Downloading full Lustify model (this will show live % + speed + ETA)..." | tee -a "$LOG"
  /venv/main/bin/python -m gdown 1_PkycSGBNdsSQus-YLBXYqsCO2J8THK_ -O "$MODEL_PATH" 2>&1 | tee -a "$LOG"
  SIZE=$(stat -c %s "$MODEL_PATH" 2>/dev/null || echo 0)
  if [ $SIZE -gt $MIN_SIZE ]; then
    echo "✅ SUCCESS: gdown Lustify mirror ($((SIZE/1024/1024)) MB)" | tee -a "$LOG"
  else
    echo "❌ Download too small — run gdown manually" | tee -a "$LOG"
  fi
fi

# AUTO-RENAME FOR DMD2 WORKFLOW
if [ -f "$MODEL_PATH" ] && [ $(stat -c %s "$MODEL_PATH") -gt $MIN_SIZE ]; then
  mv "$MODEL_PATH" "$COMFY/models/checkpoints/lustify_7.safetensors"
  echo "✅ Auto-renamed to lustify_7.safetensors (DMD2 workflow ready)" | tee -a "$LOG"
fi

# ===================== DMD2 LORA (your mirror) =====================
LORA_PATH="$COMFY/models/loras/speed\\dmd2_sdxl_4step_lora.safetensors"
echo "=== Downloading DMD2 Speed LoRA (expected ~400-800 MB) ===" | tee -a "$LOG"
mkdir -p "$COMFY/models/loras"

if [ -n "$CIVITAI_TOKEN" ]; then
  echo "→ Trying Civitai for DMD2 LoRA..." | tee -a "$LOG"
  curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
    "https://civitai.com/api/download/models/1820705" \
    -o "$LORA_PATH.tmp" --progress-bar 2>&1 | tee -a "$LOG"
  SIZE=$(stat -c %s "$LORA_PATH.tmp" 2>/dev/null || echo 0)
  if [ $SIZE -gt 1000000 ]; then
    mv "$LORA_PATH.tmp" "$LORA_PATH"
    echo "✅ SUCCESS: Civitai DMD2 LoRA ($((SIZE/1024/1024)) MB)" | tee -a "$LOG"
  else
    rm -f "$LORA_PATH.tmp"
  fi
fi

if [ ! -f "$LORA_PATH" ]; then
  echo "→ Falling back to your Google Drive mirror..." | tee -a "$LOG"
  /venv/main/bin/python -m pip install gdown --break-system-packages 2>/dev/null || python3 -m pip install gdown --break-system-packages || true
  echo "→ Downloading DMD2 LoRA (live progress below)..." | tee -a "$LOG"
  /venv/main/bin/python -m gdown 1d8skP0VUx38-ZMoAkdaw8U9nH8v5BtjG -O "$LORA_PATH" 2>&1 | tee -a "$LOG"
  echo "✅ SUCCESS: DMD2 LoRA installed from your mirror" | tee -a "$LOG"
fi

# ===================== SDXL VAE =====================
echo "=== Downloading SDXL VAE ===" | tee -a "$LOG"
curl --progress-bar -L \
  "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
  -o "$COMFY/models/vae/sdxl_vae.safetensors" 2>&1 | tee -a "$LOG"
echo "✅ SDXL VAE downloaded" | tee -a "$LOG"

# ===================== WORKFLOWS =====================
echo "=== Downloading workflows ===" | tee -a "$LOG"
cd "$COMFY/user/default/workflows"
curl -L -o "LUSTIFY_SDXL_OLT_INPAINTING_NON_DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json" 2>&1 | tee -a "$LOG"
curl -L -o "LUSTIFY_SDXL_OLT_INPAINTING_DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json" 2>&1 | tee -a "$LOG"
echo "✅ Workflows downloaded" | tee -a "$LOG"

# ===================== CUSTOM NODES + PATCHES =====================
echo "=== Installing custom nodes ===" | tee -a "$LOG"
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
  echo "→ Cloning/updating $repo" | tee -a "$LOG"
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

# ===================== RESTART =====================
echo "=== Restarting ComfyUI on port 18188 ===" | tee -a "$LOG"
pkill -9 python 2>/dev/null || true
sleep 3
cd "$COMFY"
/venv/main/bin/python main.py --listen 0.0.0.0 --port 18188 --disable-metadata > /workspace/comfyui.log 2>&1 &

echo "=== ENHANCEMENT COMPLETED (v18) ===" | tee -a "$LOG"
echo "Now run: tail -f /workspace/comfyui_nag_enhance.log" | tee -a "$LOG"
echo "Refresh ComfyUI at http://localhost:18188 and load the DMD2 workflow" | tee -a "$LOG"
