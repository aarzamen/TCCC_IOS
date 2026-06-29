#!/bin/bash
# Pre-stage Kokoro CoreML models on a connected iOS device's app cache so
# DevTools → Sender → LOAD VOICE ENGINE skips the ~640 MB HuggingFace pull.
#
# Usage: scripts/prestage-kokoro-models.sh <device-udid>
# Example: scripts/prestage-kokoro-models.sh DF20767D-0672-56DB-9928-AD2191C2CCA5
#
# The app must already be installed on the device (the data container is
# created at first install). After running, launch the app, navigate to
# DevTools → Sender, tap LOAD VOICE ENGINE — engine should report READY
# in seconds rather than minutes.
set -euo pipefail

DEVICE="${1:-}"
if [[ -z "$DEVICE" ]]; then
    echo "Usage: $0 <device-udid>"
    echo "Tip: 'xcrun devicectl list devices' shows paired phones"
    exit 1
fi

BUNDLE_ID="com.aarzamen.TCCCai"
STAGE_DIR="$(mktemp -d)/kokoro-stage"
MODELS_DIR="$STAGE_DIR/Library/Caches/fluidaudio/Models/kokoro"
HF_BASE="https://huggingface.co/FluidInference/kokoro-82m-coreml/resolve/main"

mkdir -p "$MODELS_DIR/kokoro_21_5s.mlmodelc"/{analytics,weights}
mkdir -p "$MODELS_DIR/kokoro_21_15s.mlmodelc"/{analytics,weights}

echo "→ downloading Kokoro models from HuggingFace (~640 MB)"
files=(
    "kokoro_21_5s.mlmodelc/analytics/coremldata.bin"
    "kokoro_21_5s.mlmodelc/coremldata.bin"
    "kokoro_21_5s.mlmodelc/metadata.json"
    "kokoro_21_5s.mlmodelc/model.mil"
    "kokoro_21_5s.mlmodelc/weights/weight.bin"
    "kokoro_21_15s.mlmodelc/analytics/coremldata.bin"
    "kokoro_21_15s.mlmodelc/coremldata.bin"
    "kokoro_21_15s.mlmodelc/metadata.json"
    "kokoro_21_15s.mlmodelc/model.mil"
    "kokoro_21_15s.mlmodelc/weights/weight.bin"
)
for f in "${files[@]}"; do
    echo "  $f"
    curl -fsSL -o "$MODELS_DIR/$f" "$HF_BASE/$f"
done

echo "→ pushing to device $DEVICE"
xcrun devicectl device copy to \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE_ID" \
    --source "$STAGE_DIR/Library" \
    --destination Library

echo "✓ done. Launch app → DevTools → Sender → LOAD VOICE ENGINE"
echo "  Cache landed at: <container>/Library/Caches/fluidaudio/Models/kokoro/"
