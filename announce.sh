#!/bin/bash

# TTS Announcement Script using Piper
# Usage: ./announce.sh "Your message here" [voice]
# Example: ./announce.sh "Task completed" "lessac"

MESSAGE="${1:-Task completed}"
VOICE="${2:-ryan}"  # Default to ryan-high voice (US male, high quality)

# Available piper voice options:
# lessac     - US English female (natural, clear)
# ljspeech   - US English female (medium quality)
# libritts   - US English (high quality, slower)
# amy        - US English female (medium quality)
# alan       - UK English male (medium quality)
# ryan       - US English male (high quality) - DEFAULT
# samuel     - US English male (Ryan model, natural) - end-of-coding announcements

# Map voice names and numbers to model files
VOICE_DIR="${HOME}/.local/share/piper/voices"

# Playback tuning, overridden per-voice below. Models render at 22050 Hz.
PLAY_RATE="22050"
LENGTH_SCALE=""

# Support numbered voices (1-6)
case "$VOICE" in
    "1"|"lessac"|"en-us")
        MODEL_FILE="$VOICE_DIR/en_US-lessac-medium.onnx"
        VOICE_NAME="lessac"
        ;;
    "2"|"ljspeech")
        MODEL_FILE="$VOICE_DIR/en_US-ljspeech-medium.onnx"
        VOICE_NAME="ljspeech"
        ;;
    "3"|"libritts")
        MODEL_FILE="$VOICE_DIR/en_US-libritts-high.onnx"
        VOICE_NAME="libritts"
        ;;
    "4"|"amy")
        MODEL_FILE="$VOICE_DIR/en_US-amy-medium.onnx"
        VOICE_NAME="amy"
        ;;
    "5"|"alan"|"en-uk")
        MODEL_FILE="$VOICE_DIR/en_GB-alan-medium.onnx"
        VOICE_NAME="alan"
        ;;
    "6"|"samuel"|"sam")
        # samuel.onnx IS the en_US-ryan-medium model, saved under that name. It is the file that
        # exists on this machine; en_US-ryan-high has never been downloaded, and pointing here at
        # a missing model is what drops Travis to the espeak robot.
        MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="samuel"
        ;;
    "7"|"ryan")
        MODEL_FILE="$VOICE_DIR/en_US-ryan-high.onnx"
        VOICE_NAME="ryan"
        ;;
    "daniel")
        MODEL_FILE="$VOICE_DIR/en_GB-alan-medium.onnx"  # piper fallback; macOS uses Daniel neural
        VOICE_NAME="daniel"
        ;;
    "rocko")
        MODEL_FILE="$VOICE_DIR/en_GB-alan-medium.onnx"  # piper fallback; macOS uses Rocko neural
        VOICE_NAME="rocko"
        ;;
    *)
        MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="samuel"
        ;;
esac

# ── One voice at a time ──────────────────────────────────────────────────────
# Every announcement can overlap (nag fires on its own timer). Two at once
# COLLIDE — Travis cuts himself off mid-sentence. Held for the whole speaking
# section, so a second announcement waits rather than talking over the first.
# The lock lives on a file descriptor, so it is released automatically if the
# process is killed — which is exactly what waiting-nag.sh's stop does.
LOCK_FILE="${TMPDIR:-/tmp}/travis-announce.lock"
LOCK_WAIT="${ANNOUNCE_LOCK_WAIT:-120}"
if command -v flock >/dev/null 2>&1 && exec 9>"$LOCK_FILE" 2>/dev/null; then
    if ! flock -w "$LOCK_WAIT" 9; then
        echo "Skipped (waited ${LOCK_WAIT}s for the speaker): $MESSAGE"
        exit 0
    fi
fi

# Resolve piper binary
if [[ "$OSTYPE" == "darwin"* ]]; then
    PIPER_BIN="/Users/borre/Library/Python/3.9/bin/piper"
else
    PIPER_BIN="$(command -v piper 2>/dev/null || echo '')"
fi

# Last resort if the mapped model is missing.
# Samuel is tried first because he is the voice everything here asks for.
# The size and .json checks matter: truncated downloads are a few bytes long,
# and piper accepts one and then renders silence.
if [ ! -s "$MODEL_FILE" ]; then
    for candidate in "$VOICE_DIR/samuel.onnx" "$VOICE_DIR"/*.onnx; do
        [ -f "$candidate" ] && [ -f "$candidate.json" ] || continue
        [ "$(stat -c%s "$candidate" 2>/dev/null || echo 0)" -gt 1000000 ] || continue
        MODEL_FILE="$candidate"
        VOICE_NAME="$(basename "$candidate" .onnx)"
        break
    done
fi

if [ -x "$PIPER_BIN" ] && [ -f "$MODEL_FILE" ]; then
    echo "Announcing ($VOICE_NAME): $MESSAGE"
    WAV="$(mktemp "${TMPDIR:-/tmp}/announce_speech.XXXXXX.wav")" || WAV="/tmp/announce_speech.wav"
    trap 'rm -f "$WAV"' EXIT
    PIPER_ARGS=(--model "$MODEL_FILE" --output_file "$WAV")
    [ -n "$LENGTH_SCALE" ] && PIPER_ARGS+=(--length_scale "$LENGTH_SCALE")
    echo "$MESSAGE" | "$PIPER_BIN" "${PIPER_ARGS[@]}" 2>/dev/null
    if [[ "$OSTYPE" == "darwin"* ]]; then
        afplay "$WAV" 2>/dev/null
    else
        aplay -r "$PLAY_RATE" -f S16_LE -t wav "$WAV" 2>/dev/null
    fi
    rm -f "$WAV"
elif command -v espeak &> /dev/null; then
    echo "Announcing (espeak fallback): $MESSAGE"
    timeout 60 espeak "$MESSAGE" -s 140 -v en-us
elif command -v say &> /dev/null; then
    echo "Announcing (say fallback): $MESSAGE"
    timeout 60 say "$MESSAGE"
else
    echo "TTS: $MESSAGE"
fi
