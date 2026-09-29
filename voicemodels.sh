#!/bin/bash

# voicemodels.sh — demo and download Travis voice models.
#
# Usage:
#   ./voicemodels.sh                  play a sample in each installed voice
#   ./voicemodels.sh --download <name>  download a missing voice model
#   ./voicemodels.sh --download all     download all missing voice models

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOICE_DIR="$HOME/.local/share/piper/voices"
HF_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main"

# Format: "name:model_file:hf_path"
VOICE_ENTRIES=(
    "ryan:en_US-ryan-high.onnx:en_US/en_US-ryan-high"
    "amy:en_US-amy-medium.onnx:en_US/en_US-amy-medium"
    "alan:en_GB-alan-medium.onnx:en_GB/en_GB-alan-medium"
)

# ── Helpers ──────────────────────────────────────────────────────────────────

download_voice() {
    local name="$1" model_file="$2" hf_path="$3"
    local onnx="$VOICE_DIR/$model_file"
    local json="$VOICE_DIR/$model_file.json"

    if [ -f "$onnx" ] && [ -f "$json" ]; then
        echo "  [$name]  already installed — skipping"
        return 0
    fi

    echo "  [$name]  downloading from Hugging Face..."
    mkdir -p "$VOICE_DIR"

    local url_base="$HF_BASE/$hf_path/$model_file"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --progress-bar "$url_base"      -o "$onnx" && \
        curl -fSL --progress-bar "$url_base.json" -o "$json"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$url_base"      -O "$onnx" && \
        wget -q --show-progress "$url_base.json" -O "$json"
    else
        echo "  ERROR: neither curl nor wget found"
        return 1
    fi

    if [ -f "$onnx" ] && [ -f "$json" ]; then
        echo "  [$name]  installed to $VOICE_DIR"
    else
        echo "  [$name]  download failed"
        return 1
    fi
}

# ── --download mode ───────────────────────────────────────────────────────────

if [ "$1" = "--download" ]; then
    target="${2:-all}"
    echo ""
    echo "Travis TTS — voice model download"
    echo "════════════════════════════════════"
    echo ""
    for entry in "${VOICE_ENTRIES[@]}"; do
        name="${entry%%:*}"
        rest="${entry#*:}"
        model_file="${rest%%:*}"
        hf_path="${rest##*:}"
        if [ "$target" = "all" ] || [ "$target" = "$name" ]; then
            download_voice "$name" "$model_file" "$hf_path"
            echo ""
        fi
    done
    if [ "$target" != "all" ]; then
        found=0
        for entry in "${VOICE_ENTRIES[@]}"; do
            [ "${entry%%:*}" = "$target" ] && found=1
        done
        if [ "$found" -eq 0 ]; then
            echo "Unknown voice: $target"
            echo "Available: ryan, amy, alan"
            exit 1
        fi
    fi
    exit 0
fi

# ── Demo mode ─────────────────────────────────────────────────────────────────

echo ""
echo "Travis TTS — voice model demo"
echo "════════════════════════════════"
echo ""

any_found=0
for entry in "${VOICE_ENTRIES[@]}"; do
    name="${entry%%:*}"
    rest="${entry#*:}"
    model_file="${rest%%:*}"
    hf_path="${rest##*:}"
    onnx="$VOICE_DIR/$model_file"

    if [ ! -f "$onnx" ]; then
        echo "  [$name]  — not installed"
        echo "            run: $(basename "$0") --download $name"
        echo ""
        continue
    fi
    any_found=1
    echo "  [$name]  — $model_file"
    "$SCRIPT_DIR/announce.sh" "Hello, I am $name. I can be your Travis voice." "$name"
    echo ""
done

if [ "$any_found" -eq 0 ]; then
    echo "No voice models found in $VOICE_DIR"
    echo "Run: $(basename "$0") --download all"
fi

echo "Set voice globally:    TRAVIS_VOICE=<name> in ~/.config/travis/travis.env"
echo "Set voice per-project: TRAVIS_VOICE=<name> in .claude/travis.env"
echo ""
