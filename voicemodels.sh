#!/bin/bash

# voicemodels.sh — plays a sample sentence in each installed voice.
# Run this to hear what each voice sounds like before picking one.
#
# Usage: ./voicemodels.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOICE_DIR="$HOME/.local/share/piper/voices"

echo ""
echo "Travis TTS — voice model demo"
echo "══════════════════════════════"
echo ""

# Format: "voice_name:model_filename"
VOICE_ENTRIES=(
    "ryan:en_US-ryan-high.onnx"
    "amy:en_US-amy-medium.onnx"
    "alan:en_GB-alan-medium.onnx"
)

any_found=0
for entry in "${VOICE_ENTRIES[@]}"; do
    name="${entry%%:*}"
    model_file="$VOICE_DIR/${entry##*:}"
    if [ ! -f "$model_file" ]; then
        echo "  [$name]  — not installed (${entry##*:})"
        echo ""
        continue
    fi
    any_found=1
    echo "  [$name]  — ${entry##*:}"
    "$SCRIPT_DIR/announce.sh" "Hello, I am $name. I can be your Travis voice." "$name"
    echo ""
done

if [ "$any_found" -eq 0 ]; then
    echo "No voice models found in $VOICE_DIR"
    echo "Run install.sh to download the default voice."
fi

echo "To set a voice globally:    edit ~/.config/travis/travis.env  →  TRAVIS_VOICE=<name>"
echo "To set a voice per-project: edit .claude/travis.env           →  TRAVIS_VOICE=<name>"
echo ""
