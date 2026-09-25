#!/bin/bash

# TTS Announcement Script using Piper
# Usage: ./announce.sh "Your message here" [voice]
# Example: ./announce.sh "Task completed" ryan

MESSAGE="${1:-Task completed}"
VOICE="${2:-ryan}"

# Available voices (model files live in ~/.local/share/piper/voices/):
#   ryan    - en_US-ryan-medium.onnx  (default — install.sh downloads this)
#   samuel  - samuel.onnx             (alias for ryan-medium, kept for back-compat)
#   amy     - en_US-amy-medium.onnx
#   lessac  - en_US-lessac-medium.onnx
#   alan    - en_GB-alan-medium.onnx

VOICE_DIR="${HOME}/.local/share/piper/voices"
PLAY_RATE="22050"

case "$VOICE" in
    "1"|"ryan"|"samuel"|"sam")
        # samuel.onnx is the ryan-medium model saved by install.sh
        MODEL_FILE="$VOICE_DIR/en_US-ryan-medium.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="en_US-ryan-medium"
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
        MODEL_FILE="$VOICE_DIR/en_US-ryan-medium.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="en_US-ryan-medium"
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

# ── Resolve piper binary ─────────────────────────────────────────────────────
PIPER_BIN=""

if command -v piper >/dev/null 2>&1; then
    PIPER_BIN="$(command -v piper)"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    # Scan common pip --user script dirs on macOS
    for d in \
        "$HOME/Library/Python/3.13/bin" \
        "$HOME/Library/Python/3.12/bin" \
        "$HOME/Library/Python/3.11/bin" \
        "$HOME/Library/Python/3.10/bin" \
        "$HOME/Library/Python/3.9/bin" \
        "$HOME/.local/bin"; do
        [ -x "$d/piper" ] && PIPER_BIN="$d/piper" && break
    done
else
    # Linux / WSL / Windows (Git Bash)
    PIPER_BIN="$HOME/.local/bin/piper"
    [ -x "$PIPER_BIN" ] || PIPER_BIN=""
fi

# ── Fallback: first usable model present ────────────────────────────────────
if [ ! -s "$MODEL_FILE" ]; then
    for candidate in "$VOICE_DIR/en_US-ryan-medium.onnx" "$VOICE_DIR/samuel.onnx" "$VOICE_DIR"/*.onnx; do
        [ -f "$candidate" ] && [ -f "$candidate.json" ] || continue
        [ "$(stat -f%z "$candidate" 2>/dev/null || stat -c%s "$candidate" 2>/dev/null || echo 0)" -gt 1000000 ] || continue
        MODEL_FILE="$candidate"
        VOICE_NAME="$(basename "$candidate" .onnx)"
        break
    done
fi

# ── Speak ────────────────────────────────────────────────────────────────────
if [ -x "$PIPER_BIN" ] && [ -f "$MODEL_FILE" ]; then
    echo "Announcing ($VOICE_NAME): $MESSAGE"
    WAV="$(mktemp "${TMPDIR:-/tmp}/announce_speech.XXXXXX.wav")" || WAV="/tmp/announce_speech.wav"
    trap 'rm -f "$WAV"' EXIT
    echo "$MESSAGE" | "$PIPER_BIN" --model "$MODEL_FILE" --output_file "$WAV" 2>/dev/null
    if [[ "$OSTYPE" == "darwin"* ]]; then
        afplay "$WAV" 2>/dev/null
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        # WSL: use PowerShell to play audio through Windows
        powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '$WAV').PlaySync()" 2>/dev/null || \
            aplay -r "$PLAY_RATE" -f S16_LE -t wav "$WAV" 2>/dev/null
    elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
        # Git Bash / Cygwin on Windows
        powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '$(cygpath -w "$WAV" 2>/dev/null || echo "$WAV")').PlaySync()" 2>/dev/null
    else
        aplay -r "$PLAY_RATE" -f S16_LE -t wav "$WAV" 2>/dev/null
    fi
    rm -f "$WAV"
elif command -v espeak >/dev/null 2>&1; then
    echo "Announcing (espeak fallback): $MESSAGE"
    espeak "$MESSAGE" -s 140 -v en-us
elif command -v say >/dev/null 2>&1; then
    echo "Announcing (say fallback): $MESSAGE"
    say "$MESSAGE"
else
    echo "TTS: $MESSAGE"
fi
