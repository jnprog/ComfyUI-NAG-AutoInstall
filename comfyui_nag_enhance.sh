#!/bin/bash
set -e

LOG="/workspace/comfyui_nag_enhance.log"
mkdir -p /workspace
echo "=== COMFYUI-NAG ENHANCEMENT STARTED (v17 - Civitai + gdown + auto-rename + DMD2 LoRA) ===" | tee -a "$LOG"
date | tee -a "$LOG"

# FORCE CORRECT PATH (2026 Vast.ai template)
COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae,upscale_models,loras},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

# ===================== LUSTIFY MODEL (CIVITAI + GDOWN GOOGLE DRIVE) =====================
MODEL_PATH="$COMFY/models/checkpoints/lustify_sdxl_olt_inpainting.safetensors"
MIN_SIZE=6500000000  # ~6.5 GB

echo "Downloading Lustify OLT Inpainting..." | tee -a "$LOG"

DOWNLOADED=false

# Try Civitai first (two methods)
if [ -n "$CIVITAI_TOKEN" ]; then
  for method in bearer token; do
    echo "→ Trying Civitai ($method method)..." | tee -a "$LOG"
    rm -f "$MODEL_PATH.tmp"
    
    if [ "$method" = "bearer" ]; then
      curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
        "https://civitai.com/api/download/models/573152" \
        -o "$MODEL_PATH.tmp" --progress-bar
    else
      curl -L "https://civitai.com/api/download/models/573152?token=$CIVITAI_TOKEN" \
        -o "$MODEL_PATH.tmp" --progress-bar
    fi
    
    SIZE=$(stat -c %s "$MODEL_PATH.tmp" 2>/dev/null || echo 0)
    if [ $SIZE -gt $MIN_SIZE ]; then
      mv "$MODEL_PATH.tmp" "$MODEL_PATH"
      echo "✅ SUCCESS: Civitai download ($((SIZE/1024/1024)) MB)" | tee -a "$LOG"
      DOWNLOADED=true
      break
    else
      echo "⚠️ Civitai blocked (only $((SIZE/1024)) KB) — trying next method..." | tee -a "$LOG"
      rm -f "$MODEL_PATH.tmp"
    fi
  done
fi

# Google Drive fallback with gdown
if [ "$DOWNLOADED" = false ] || [ ! -f "$MODEL_PATH" ] || [ $(stat -c %s "$MODEL_PATH" 2>/dev/null || echo 0) -lt $MIN_SIZE ]; then
  echo "→ Civitai blocked — falling back to Google Drive mirror with gdown..." | tee -a "$LOG"
  rm -f "$MODEL_PATH" "$MODEL_PATH.tmp"
  
  echo "→ Installing gdown..." | tee -a "$LOG"
  /venv/main/bin/python -m pip install gdown --break-system-packages 2>/dev/null || python3 -m pip install gdown --break-system-packages || true
  
  echo "→ Downloading full 6.5 GB Lustify model via gdown..." | tee -a "$LOG"
  /venv/main/bin/python -m gdown 1_PkycSGBNdsSQus-YLBXYqsCO2J8THK_ -O "$MODEL_PATH" || \
  python3 -m gdown 1_PkycSGBNdsSQus-YLBXYqsCO2J8THK_ -O "$MODEL_PATH"
  
  SIZE=$(stat -c %s "$MODEL_PATH" 2>/dev/null || echo 0)
  if [ $SIZE -gt $MIN_SIZE ]; then
    echo "✅ SUCCESS: gdown Google Drive mirror ($((SIZE/1024/1024)) MB)" | tee -a "$LOG"
    DOWNLOADED=true
  else
    echo "❌ Download still too small — please run gdown manually" | tee -a "$LOG"
  fi
fi

# ===================== AUTO-RENAME FOR DMD2 WORKFLOW =====================
if [ -f "$MODEL_PATH" ] && [ $(stat -c %s "$MODEL_PATH") -gt $MIN_SIZE ]; then
  mv "$MODEL_PATH" "$COMFY/models/checkpoints/lustify_7.safetensors"
  echo "✅ Auto-renamed Lustify to lustify_7.safetensors (required by DMD2 workflow)" | tee -a "$LOG"
fi

# ===================== DMD2 LORA (your Google Drive mirror) =====================
LORA_PATH="$COMFY/models/loras/speed\\dmd2_sdxl_4step_lora.safetensors"
echo "Downloading DMD2 Speed LoRA..." | tee -a "$LOG"
mkdir -p "$COMFY/models/loras"

DOWNLOADED_LORA=false

# Try Civitai first
if [ -n "$CIVITAI_TOKEN" ]; then
  echo "→ Trying Civitai for DMD2 LoRA..." | tee -a "$LOG"
  rm -f "$LORA_PATH.tmp"
  curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
    "https://civitai.com/api/download/models/1820705" \
    -o "$LORA_PATH.tmp" --progress-bar
  SIZE=$(stat -c %s "$LORA_PATH.tmp" 2>/dev/null || echo 0)
  if [ $SIZE -gt 1000000 ]; then
    mv "$LORA_PATH.tmp" "$LORA_PATH"
    echo "✅ SUCCESS: Civitai DMD2 LoRA ($((SIZE/1024/1024)) MB)" | tee -a "$LOG"
    DOWNLOADED_LORA=true
  else
    rm -f "$LORA_PATH.tmp"
  fi
fi

# Google Drive fallback (your mirror)
if [ "$DOWNLOADED_LORA" = false ] || [ ! -f "$LORA_PATH" ]; then
  echo "→ Civitai blocked — falling back to your Google Drive mirror..." | tee -a "$LOG"
  /venv/main/bin/python -m pip install gdown --break-system-packages 2>/dev/null || python3 -m pip install gdown --break-system-packages || true
  /venv/main/bin/python -m gdown 1d8skP0VUx38-ZMoAkdaw8U9nH8v5BtjG -O "$LORA_PATH" || \
  python3 -m gdown 1d8skP0VUx38-ZMoAkdaw8U9nH8v5BtjG -O "$LORA_PATH"
  echo "✅ SUCCESS: DMD2 LoRA via your Google Drive mirror" | tee -a "$LOG"
fi

# ===================== SDXL VAE =====================
echo "Downloading SDXL VAE..." | tee -a "$LOG"
curl --progress-bar -L \
  "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
  -o "$COMFY/models/vae/sdxl_vae.safetensors"

# ===================== WORKFLOWS =====================
echo "Downloading workflows..." | tee -a "$LOG"
cd "$COMFY/user/default/workflows"
curl -L -o "LUSTIFY_SDXL_OLT_INPAINTING_NON_DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"
curl -L -o "LUSTIFY_SDXL_OLT_INPAINTING_DMD2.json" \
  "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"

# ===================== CUSTOM NODES + NAG PATCHES =====================
echo "Installing custom nodes..." | tee -a "$LOG"
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
  echo "→ $repo" | tee -a "$LOG"
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

# ===================== RESTART COMFYUI =====================
echo "Restarting ComfyUI on port 18188..." | tee -a "$LOG"
pkill -9 python 2>/dev/null || true
sleep 3
cd "$COMFY"
/venv/main/bin/python main.py --listen 0.0.0.0 --port 18188 --disable-metadata > /workspace/comfyui.log 2>&1 &

echo "=== ENHANCEMENT COMPLETED (v17) ===" | tee -a "$LOG"
echo "Refresh browser at http://localhost:18188 and load LUSTIFY_SDXL_OLT_INPAINTING_DMD2.json" | tee -a "$LOG"
