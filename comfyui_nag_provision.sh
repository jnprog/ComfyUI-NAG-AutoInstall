#!/bin/bash
set -e

echo "=== ComfyUI-NAG Provisioning (v9 - Fixed for Vast.ai 2026) ==="

# === PATH FIX (real location in 2026 template) ===
INTERNAL_COMFY="/opt/workspace-internal/ComfyUI"
WORKSPACE_COMFY="/workspace/ComfyUI"
mkdir -p "$INTERNAL_COMFY"/{custom_nodes,models/{checkpoints,vae},user/default/workflows}
ln -sfn "$INTERNAL_COMFY" "$WORKSPACE_COMFY" 2>/dev/null || true
COMFY_PATH="$INTERNAL_COMFY"

# Activate venv
source /venv/main/bin/activate

# === MODELS ===
echo "Downloading Lustify SDXL NSFW Inpainting (with token)..."
if [ -n "$CIVITAI_TOKEN" ]; then
  curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
    "https://civitai.com/api/download/models/573152" \  # replace with exact version ID if needed (your v8 one)
    -o "$COMFY_PATH/models/checkpoints/lustify_sdxl_olt_inpainting.safetensors"
fi

echo "Downloading SDXL VAE..."
curl -L "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
  -o "$COMFY_PATH/models/vae/sdxl_vae.safetensors"

# === WORKFLOWS (URL-encoded) ===
echo "Downloading workflows..."
cd "$COMFY_PATH/user/default/workflows"
curl -L -O "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"
curl -L -O "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"

# === CUSTOM NODES ===
echo "Installing nodes..."
cd "$COMFY_PATH/custom_nodes"
for repo in \
  "ltdrdata/ComfyUI-Manager" \
  "ltdrdata/ComfyUI-Impact-Pack" \
  "cubiq/ComfyUI_IPAdapter_plus" \
  "ChenDarYen/ComfyUI-NAG"; do
  git clone "https://github.com/$repo.git" 2>/dev/null || git -C "$(basename $repo)" pull
done

# === NAG PATCH (your proven fix from conversation.pdf) ===
cd ComfyUI-NAG
echo "Applying NAG patches..."
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
  sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
fi

# Optional: overwrite with your exact patched files from documents (even safer)
# cat > chroma/layers.py << 'EOF' ... (paste the full layers.py you provided)
# cat > chroma/model.py << 'EOF' ... (paste the full model.py)

echo "=== PROVISIONING COMPLETE ==="
echo "ComfyUI will auto-start via supervisor. Refresh the Open button in 30-60s."
