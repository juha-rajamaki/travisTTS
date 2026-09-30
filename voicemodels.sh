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
    "ryan:en_US-ryan-high.onnx:en/en_US/ryan/high"
    "amy:en_US-amy-medium.onnx:en/en_US/amy/medium"
    "alan:en_GB-alan-medium.onnx:en/en_GB/alan/medium"
    "jenny:en_GB-jenny_dioco-medium.onnx:en/en_GB/jenny_dioco/medium"
    "kristin:en_US-kristin-medium.onnx:en/en_US/kristin/medium"
)

# Per-voice introductions for the demo mode.
declare -A VOICE_INTRO
VOICE_INTRO[ryan]="Hi, I'm Ryan — your default voice. I announce when Claude finishes a task and say on it when work begins."
VOICE_INTRO[amy]="Hi, I'm Amy. I speak up when the Plan agent has finished laying out an implementation plan for you."
VOICE_INTRO[alan]="Hello, I'm Alan. I report the findings whenever the security auditor has reviewed your code."
VOICE_INTRO[jenny]="Hi, I'm Jenny. I can be your Travis voice."
VOICE_INTRO[kristin]="Hi, I'm Kristin. I can be your Travis voice."

# ── Helpers ──────────────────────────────────────────────────────────────────

# A real model is tens of MB; anything under 1 MB is an error page or a cut-off download.
model_ok() {
    local f="$1"
    [ -f "$f" ] && \
        [ "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)" -gt 1000000 ]
}

download_voice() {
    local name="$1" model_file="$2" hf_path="$3"
    local onnx="$VOICE_DIR/$model_file"
    local json="$VOICE_DIR/$model_file.json"

    if model_ok "$onnx" && [ -s "$json" ]; then
        echo "  [$name]  already installed — skipping"
        return 0
    fi

    echo "  [$name]  downloading from Hugging Face..."
    mkdir -p "$VOICE_DIR"

    # Download into .part files and move them into place only when both succeeded, so an
    # interrupted download never leaves a truncated model that looks installed.
    local url_base="$HF_BASE/$hf_path/$model_file"
    local ok=1
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --progress-bar "$url_base"      -o "$onnx.part" && \
        curl -fSL --progress-bar "$url_base.json" -o "$json.part" || ok=0
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$url_base"      -O "$onnx.part" && \
        wget -q --show-progress "$url_base.json" -O "$json.part" || ok=0
    else
        echo "  ERROR: neither curl nor wget found"
        return 1
    fi

    if [ "$ok" -eq 1 ] && model_ok "$onnx.part" && [ -s "$json.part" ]; then
        mv -f "$onnx.part" "$onnx" && mv -f "$json.part" "$json"
    else
        rm -f "$onnx.part" "$json.part"
        ok=0
    fi

    if [ "$ok" -eq 1 ]; then
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
            echo "Available: ryan, amy, alan, jenny, kristin"
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
    "$SCRIPT_DIR/announce.sh" "${VOICE_INTRO[$name]:-Hello, I am $name. I can be your Travis voice.}" "$name"
    echo ""
done

if [ "$any_found" -eq 0 ]; then
    echo "No voice models found in $VOICE_DIR"
    echo "Run: $(basename "$0") --download all"
fi

echo "Set voice globally:    TRAVIS_VOICE=<name> in ~/.config/travis/travis.env"
echo "Set voice per-project: TRAVIS_VOICE=<name> in .claude/travis.env"
echo ""
