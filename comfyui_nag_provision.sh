#!/bin/bash
set -e

echo "=== ComfyUI-NAG Provisioning v9 (PROVISIONING_SCRIPT) ==="

COMFY="/opt/workspace-internal/ComfyUI"
mkdir -p "$COMFY"/{custom_nodes,models/{checkpoints,vae},user/default/workflows}
ln -sfn "$COMFY" /workspace/ComfyUI 2>/dev/null || true

# Models
if [ -n "$CIVITAI_TOKEN" ]; then
  echo "Downloading Lustify SDXL NSFW Inpainting..."
  curl -L -H "Authorization: Bearer $CIVITAI_TOKEN" \
    "https://civitai.com/api/download/models/573152" \
    -o "$COMFY/models/checkpoints/lustify_sdxl_olt_inpainting.safetensors"
fi

echo "Downloading SDXL VAE..."
curl -L "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
  -o "$COMFY/models/vae/sdxl_vae.safetensors"

# Workflows (URL-encoded)
cd "$COMFY/user/default/workflows"
curl -L -O "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20NON-DMD2.json"
curl -L -O "https://raw.githubusercontent.com/jnprog/ComfyUI-NAG-AutoInstall/main/workflows/LUSTIFY!%20SDXL%20-%20OLT%20INPAINTING%20-%20DMD2.json"

# Nodes
cd "$COMFY/custom_nodes"
for repo in ltdrdata/ComfyUI-Manager ltdrdata/ComfyUI-Impact-Pack cubiq/ComfyUI_IPAdapter_plus ChenDarYen/ComfyUI-NAG; do
  git clone https://github.com/$repo.git 2>/dev/null || git -C "${repo##*/}" pull
done

# NAG patches (exact working ones from your PDF + logs)
cd ComfyUI-NAG
sed -i '5s|.*|from comfy.ldm.flux.layers import DoubleStreamBlock, SingleStreamBlock|' chroma/layers.py || true
sed -i '/from comfy\.ldm\.flux\.model import Chroma/d' chroma/model.py || true
sed -i '/import.*Chroma/d' chroma/model.py || true
sed -i 's/class NAGChroma(Chroma):/class NAGChroma(Flux):/' chroma/model.py || true
if ! grep -q "from comfy.ldm.flux.model import Flux" chroma/model.py; then
  sed -i '1s|^|from comfy.ldm.flux.model import Flux\n|' chroma/model.py
fi

echo "=== PROVISIONING COMPLETE ==="
echo "Supervisor will restart ComfyUI automatically."
