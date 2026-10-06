#!/bin/bash

# TTS Announcement Script using Piper
# Usage: ./announce.sh "Your message here" [voice]
# Example: ./announce.sh "Task completed" ryan

MESSAGE="${1:-Task completed}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=travis-config.sh
source "$SCRIPT_DIR/travis-config.sh"

# Voice priority: explicit $2 argument > TRAVIS_VOICE (env or travis.env) > built-in default.
# Hook scripts never pass $2, so they always follow the config; an explicit choice such as
# `travis 3 "..."` or the voicemodels.sh demo is honoured.
VOICE="${2:-${TRAVIS_VOICE:-ryan}}"

if travis_is_quiet; then
    echo "DND (${TRAVIS_QUIET_FROM}–${TRAVIS_QUIET_TO}): $MESSAGE"
    exit 0
fi

if [ -n "${TRAVIS_ACTIVE_FROM:-}${TRAVIS_ACTIVE_TO:-}" ] && ! travis_active_hours_set; then
    echo "Warning: active hours ignored, need valid HH:MM for both TRAVIS_ACTIVE_FROM and TRAVIS_ACTIVE_TO" >&2
fi
if ! travis_is_active; then
    echo "Outside active hours (${TRAVIS_ACTIVE_FROM}–${TRAVIS_ACTIVE_TO}): $MESSAGE"
    exit 0
fi

# Available voices (model files live in ~/.local/share/piper/voices/):
#   ryan    - en_US-ryan-high.onnx    (default)
#   amy     - en_US-amy-medium.onnx
#   alan    - en_GB-alan-medium.onnx
#   jenny   - en_GB-jenny_dioco-medium.onnx
#   kristin - en_US-kristin-medium.onnx
#   samuel  - alias for ryan (back-compat)

VOICE_DIR="${HOME}/.local/share/piper/voices"
PLAY_RATE="22050"

case "$VOICE" in
    "1"|"ryan"|"samuel"|"sam")
        MODEL_FILE="$VOICE_DIR/en_US-ryan-high.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/en_US-ryan-medium.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="ryan"
        ;;
    "2"|"amy")
        MODEL_FILE="$VOICE_DIR/en_US-amy-medium.onnx"
        VOICE_NAME="amy"
        ;;
    "3"|"alan")
        MODEL_FILE="$VOICE_DIR/en_GB-alan-medium.onnx"
        VOICE_NAME="alan"
        ;;
    "4"|"jenny")
        MODEL_FILE="$VOICE_DIR/en_GB-jenny_dioco-medium.onnx"
        VOICE_NAME="jenny"
        ;;
    "5"|"kristin")
        MODEL_FILE="$VOICE_DIR/en_US-kristin-medium.onnx"
        VOICE_NAME="kristin"
        ;;
    *)
        MODEL_FILE="$VOICE_DIR/en_US-ryan-high.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/en_US-ryan-medium.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="ryan"
        ;;
esac

# ── One voice at a time ──────────────────────────────────────────────────────
# Announcements can overlap (nag fires on its own timer). Two at once COLLIDE —
# Travis cuts himself off mid-sentence.
# Strategy: kill any in-flight afplay/aplay before starting a new one, then
# hold a mkdir lock so concurrent callers queue up rather than pile on.
# mkdir is atomic on macOS and Linux; the lock dir is removed on EXIT so a
# killed process never leaves it behind.
LOCK_DIR="${TMPDIR:-/tmp}/travis-announce.lock"
LOCK_WAIT="${ANNOUNCE_LOCK_WAIT:-120}"
AFPLAY_PID_FILE="${TMPDIR:-/tmp}/travis-afplay.pid"

# Kill any currently-playing afplay/aplay so the new announcement isn't garbled.
if [ -f "$AFPLAY_PID_FILE" ]; then
    _old_pid="$(cat "$AFPLAY_PID_FILE" 2>/dev/null)"
    [ -n "$_old_pid" ] && kill "$_old_pid" 2>/dev/null
    rm -f "$AFPLAY_PID_FILE"
fi

# Older versions used a flock file at the same path; a leftover plain file would make
# mkdir fail forever, so remove it (only if it's ours and not a directory or symlink).
if [ -e "$LOCK_DIR" ] && [ ! -d "$LOCK_DIR" ] && [ ! -L "$LOCK_DIR" ] && [ -O "$LOCK_DIR" ]; then
    rm -f "$LOCK_DIR"
fi

# Acquire mkdir lock (works on macOS + Linux, no flock needed).
_lock_acquired=0
_lock_deadline=$(( $(date +%s) + LOCK_WAIT ))
while true; do
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        _lock_acquired=1
        trap 'rm -rf "$LOCK_DIR"' EXIT
        break
    fi
    # Check if the owning process is still alive via its pid file inside the lock dir.
    _owner="$(cat "$LOCK_DIR/pid" 2>/dev/null)"
    if [ -n "$_owner" ] && ! kill -0 "$_owner" 2>/dev/null; then
        rm -rf "$LOCK_DIR" 2>/dev/null   # stale lock — remove and retry immediately
        continue
    fi
    [ "$(date +%s)" -ge "$_lock_deadline" ] && { echo "Skipped (waited ${LOCK_WAIT}s for the speaker): $MESSAGE"; exit 0; }
    sleep 0.2
done
echo $$ > "$LOCK_DIR/pid" 2>/dev/null

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
    WAV="$(mktemp "${TMPDIR:-/tmp}/announce_speech.XXXXXX")" || WAV="/tmp/announce_speech_$$.tmp"
    WIN_WAV=""
    # One cleanup for every exit path; INT/TERM (e.g. a hook timeout) exit through the EXIT trap.
    trap 'rm -f "$WAV" "$WAV.pad" "$WIN_WAV" "$AFPLAY_PID_FILE"; rm -rf "$LOCK_DIR"' EXIT
    trap 'exit 130' INT TERM
    printf '%s\n' "$MESSAGE" | "$PIPER_BIN" --model "$MODEL_FILE" --output_file "$WAV" 2>/dev/null
    if [[ "$OSTYPE" == "darwin"* ]]; then
        afplay "$WAV" 2>/dev/null &
        _afplay_pid=$!
        echo "$_afplay_pid" > "$AFPLAY_PID_FILE"
        wait "$_afplay_pid" 2>/dev/null
        rm -f "$AFPLAY_PID_FILE"
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        # WSL: play through Windows. SoundPlayer can't open a Linux path like /tmp/x.wav, and a
        # \\wsl.localhost UNC path returns after a fraction of a second - so copy the file onto
        # the Windows drive first. Prepend 400 ms of silence: Windows audio devices (Bluetooth
        # especially) wake up late and swallow the start of the first word.
        # Padded into a side file and moved over only on success, so a failure never leaves a
        # truncated WAV behind to play.
        python3 - "$WAV" "$WAV.pad" <<'PY' 2>/dev/null && mv -f "$WAV.pad" "$WAV"
import sys, wave
src, dst = sys.argv[1], sys.argv[2]
with wave.open(src, 'rb') as r:
    params, frames = r.getparams(), r.readframes(r.getnframes())
pad = b'\0' * int(params.framerate * 0.4) * params.sampwidth * params.nchannels
with wave.open(dst, 'wb') as w:
    w.setparams(params)
    w.writeframes(pad + frames)
PY
        WIN_TEMP="$(cmd.exe /c 'echo %TEMP%' 2>/dev/null | tr -d '\r')"
        WIN_WAV_DIR="$(wslpath -u "$WIN_TEMP" 2>/dev/null)"
        if [ -n "$WIN_TEMP" ] && [ -d "$WIN_WAV_DIR" ] && cp "$WAV" "$WIN_WAV_DIR/$(basename "$WAV")" 2>/dev/null; then
            WIN_WAV="$WIN_WAV_DIR/$(basename "$WAV")"
            # Inside a single-quoted PowerShell string a ' must be doubled (e.g. C:\Users\O'Brien).
            PS_PATH="$WIN_TEMP\\$(basename "$WAV")"
            powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '${PS_PATH//\'/\'\'}').PlaySync()" >/dev/null 2>&1
            rm -f "$WIN_WAV"
        else
            paplay "$WAV" 2>/dev/null || aplay -r "$PLAY_RATE" -f S16_LE -t wav "$WAV" 2>/dev/null
        fi
    elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "cygwin"* ]]; then
        # Git Bash / Cygwin on Windows
        PS_PATH="$(cygpath -w "$WAV" 2>/dev/null || echo "$WAV")"
        powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '${PS_PATH//\'/\'\'}').PlaySync()" 2>/dev/null
    else
        aplay -r "$PLAY_RATE" -f S16_LE -t wav "$WAV" 2>/dev/null
    fi
    rm -f "$WAV"
elif command -v espeak >/dev/null 2>&1; then
    echo "Announcing (espeak fallback): $MESSAGE"
    # Text on stdin, never argv: a message like "-w/some/file" would be parsed as an option.
    printf '%s\n' "$MESSAGE" | espeak --stdin -s 140 -v en-us
elif command -v say >/dev/null 2>&1; then
    echo "Announcing (say fallback): $MESSAGE"
    printf '%s\n' "$MESSAGE" | say -f -
else
    echo "TTS: $MESSAGE"
fi
