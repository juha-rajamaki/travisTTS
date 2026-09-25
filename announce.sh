#!/bin/bash

# TTS Announcement Script using Piper
# Usage: ./announce.sh "Your message here" [voice]
# Example: ./announce.sh "Task completed" lessac

MESSAGE="${1:-Task completed}"
VOICE="${2:-samuel}"

# Available voices:
# samuel  - en_US-ryan-medium (default; the installed Ryan model)
# amy     - en_US-amy-medium
# lessac  - en_US-lessac-medium
# alan    - en_GB-alan-medium

VOICE_DIR="${HOME}/.local/share/piper/voices"
PLAY_RATE="22050"

case "$VOICE" in
    "1"|"samuel"|"sam")
        # samuel.onnx IS the en_US-ryan-medium model saved under this name.
        # en_US-ryan-high has never been downloaded here; pointing at a missing
        # model silently falls back to espeak (the robot voice).
        MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="samuel"
        ;;
    "2"|"amy")
        MODEL_FILE="$VOICE_DIR/en_US-amy-medium.onnx"
        VOICE_NAME="amy"
        ;;
    "3"|"lessac")
        MODEL_FILE="$VOICE_DIR/en_US-lessac-medium.onnx"
        VOICE_NAME="lessac"
        ;;
    "4"|"alan")
        MODEL_FILE="$VOICE_DIR/en_GB-alan-medium.onnx"
        VOICE_NAME="alan"
        ;;
    *)
        MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="samuel"
        ;;
esac

# ── One voice at a time ──────────────────────────────────────────────────────
# Announcements can overlap (nag fires on its own timer). Two at once COLLIDE —
# Travis cuts himself off mid-sentence. The lock is released automatically if
# the process is killed, so waiting-nag.sh stop can always cut in-flight audio.
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

# Last resort: if the mapped model is missing, take the first model actually
# present. Samuel tried first since everything defaults to him.
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
    echo "$MESSAGE" | "$PIPER_BIN" --model "$MODEL_FILE" --output_file "$WAV" 2>/dev/null
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
