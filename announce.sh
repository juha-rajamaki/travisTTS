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


if [ -n "${TRAVIS_ACTIVE_FROM:-}${TRAVIS_ACTIVE_TO:-}" ] && ! travis_active_hours_set; then
    echo "Warning: active hours ignored, need valid HH:MM for both TRAVIS_ACTIVE_FROM and TRAVIS_ACTIVE_TO" >&2
fi
if ! travis_is_active; then
    echo "Outside active hours (${TRAVIS_ACTIVE_FROM}–${TRAVIS_ACTIVE_TO}): $MESSAGE"
    exit 0
fi

# Available voices (model files live in ~/.local/share/piper/voices/):
#   ryan       - en_US-ryan-high.onnx    (default)
#   amy        - en_US-amy-medium.onnx
#   lessac     - en_US-lessac-medium.onnx
#   bryce      - en_US-bryce-medium.onnx
#   joe        - en_US-joe-medium.onnx
#   john       - en_US-john-medium.onnx
#   hfc_female - en_US-hfc_female-medium.onnx
#   kristin    - en_US-kristin-medium.onnx
#   alan       - en_GB-alan-medium.onnx
#   jenny      - en_GB-jenny_dioco-medium.onnx
#   cori       - en_GB-cori-high.onnx
#   alba       - en_GB-alba-medium.onnx
#   samuel     - alias for ryan (back-compat)

VOICE_DIR="${HOME}/.local/share/piper/voices"
PLAY_RATE="22050"
LENGTH_SCALE="${TRAVIS_LENGTH_SCALE:-1}"   # piper's speaking pace: above 1 is slower

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
    "lessac")
        MODEL_FILE="$VOICE_DIR/en_US-lessac-medium.onnx"
        VOICE_NAME="lessac"
        ;;
    "bryce")
        MODEL_FILE="$VOICE_DIR/en_US-bryce-medium.onnx"
        VOICE_NAME="bryce"
        ;;
    "6"|"joe")
        MODEL_FILE="$VOICE_DIR/en_US-joe-medium.onnx"
        VOICE_NAME="joe"
        ;;
    "john")
        MODEL_FILE="$VOICE_DIR/en_US-john-medium.onnx"
        VOICE_NAME="john"
        ;;
    "hfc_female")
        MODEL_FILE="$VOICE_DIR/en_US-hfc_female-medium.onnx"
        VOICE_NAME="hfc_female"
        ;;
    "3"|"alan")
        MODEL_FILE="$VOICE_DIR/en_GB-alan-medium.onnx"
        VOICE_NAME="alan"
        ;;
    "4"|"jenny")
        MODEL_FILE="$VOICE_DIR/en_GB-jenny_dioco-medium.onnx"
        VOICE_NAME="jenny"
        ;;
    "cori")
        MODEL_FILE="$VOICE_DIR/en_GB-cori-high.onnx"
        VOICE_NAME="cori"
        ;;
    "alba")
        MODEL_FILE="$VOICE_DIR/en_GB-alba-medium.onnx"
        VOICE_NAME="alba"
        ;;
    "5"|"kristin")
        MODEL_FILE="$VOICE_DIR/en_US-kristin-medium.onnx"
        VOICE_NAME="kristin"
        ;;
    "satu")
        # macOS built-in Finnish voice — bypass Piper entirely
        VOICE_NAME="satu"
        if travis_is_quiet; then
            echo "DND (${TRAVIS_QUIET_FROM}–${TRAVIS_QUIET_TO}) [satu]: $MESSAGE"
            exit 0
        fi
        echo "Announcing [satu]: $MESSAGE"
        _say_rate_args=""
        [ -n "${TRAVIS_SAY_RATE:-}" ] && _say_rate_args="-r ${TRAVIS_SAY_RATE}"
        # shellcheck disable=SC2086
        printf '%s\n' "$MESSAGE" | say -v Satu $_say_rate_args -f -
        exit 0
        ;;
    *)
        MODEL_FILE="$VOICE_DIR/en_US-ryan-high.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/en_US-ryan-medium.onnx"
        [ -f "$MODEL_FILE" ] || MODEL_FILE="$VOICE_DIR/samuel.onnx"
        VOICE_NAME="ryan"
        ;;
esac

# The text printed with the speech names the role as well as the voice: "[coding · ryan]".
SPEAKER="$VOICE_NAME"
_role="$(travis_voice_role "$VOICE_NAME")"
[ -n "$_role" ] && SPEAKER="$_role · $VOICE_NAME"

if travis_is_quiet; then
    echo "DND (${TRAVIS_QUIET_FROM}–${TRAVIS_QUIET_TO}) [$SPEAKER]: $MESSAGE"
    exit 0
fi

# ── A chosen voice that is not installed is downloaded first ─────────────────
# Travis speaks in the voice that was chosen, not a stand-in: a missing model is fetched now
# (voicemodels.sh: temp file, size check) and this message waits for it - for up to 45 seconds,
# before taking the speaker, so other announcements are never held up. If it is not there in
# time, or fails, another installed voice speaks this once (below); a failed or unfinished try is
# not repeated for 30 minutes, so an offline machine is not slowed down on every message.
_fell_back=0
if [ ! -s "$MODEL_FILE" ] && [ -n "${MODEL_FILE:-}" ] && grep -q "\"$VOICE_NAME:" "$SCRIPT_DIR/voicemodels.sh" 2>/dev/null; then
    _tried="$HOME/.config/travis/download-tried-$VOICE_NAME"
    if [ -z "$(find "$_tried" -mmin -30 2>/dev/null)" ]; then
        mkdir -p "$(dirname "$_tried")" 2>/dev/null && touch "$_tried"
        echo "Voice '$VOICE_NAME' is not installed yet: downloading it first..."
        "$SCRIPT_DIR/voicemodels.sh" --download "$VOICE_NAME" </dev/null >/dev/null 2>&1 &
        _dl_pid=$!
        _dl_deadline=$(( $(date +%s) + 45 ))
        while kill -0 "$_dl_pid" 2>/dev/null && [ "$(date +%s)" -lt "$_dl_deadline" ]; do sleep 0.5; done
        # still going: let it finish on its own (the next message gets the voice), but do not wait
        if [ -s "$MODEL_FILE" ]; then echo "Voice '$VOICE_NAME' installed."; rm -f "$_tried"
        else echo "Voice '$VOICE_NAME' is not ready yet: speaking in another voice this time." >&2; fi
    fi
fi

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

[ -s "$MODEL_FILE" ] || _fell_back=1

# ── Fallback: first usable model present ────────────────────────────────────
if [ ! -s "$MODEL_FILE" ]; then
    for candidate in "$VOICE_DIR/en_US-ryan-medium.onnx" "$VOICE_DIR/samuel.onnx" "$VOICE_DIR"/*.onnx; do
        [ -f "$candidate" ] && [ -f "$candidate.json" ] || continue
        [ "$(stat -f%z "$candidate" 2>/dev/null || stat -c%s "$candidate" 2>/dev/null || echo 0)" -gt 1000000 ] || continue
        MODEL_FILE="$candidate"
        VOICE_NAME="$(basename "$candidate" .onnx | sed -E 's/^[a-z]{2}_[A-Z]{2}-//; s/-(x_low|low|medium|high)$//; s/_dioco$//')"
        break
    done
fi
[ "$_fell_back" = 1 ] && SPEAKER="$VOICE_NAME, standing in"   # printed with the speech

# One line per announcement: which player spoke it. Rarely a line plays at several times normal
# speed; the log tells whether those went through Windows or the Linux (WSLg) fallback.
PLAY_LOG="$SCRIPT_DIR/.announce.log"
log_play() { printf '%s  %-8s %-11s %s\n' "$(date '+%F %T')" "$VOICE_NAME" "$1" "${MESSAGE:0:60}" >> "$PLAY_LOG" 2>/dev/null; }

# ── A new voice introduces itself ────────────────────────────────────────────
# The voice each project (and, with multivoice, each role) last spoke in is remembered in
# ~/.config/travis/voices. When it has changed - or speaks there for the first time - the new
# voice says who it is before the message. A one-off voice passed as $2 (`travis 3 "..."`, the
# voicemodels.sh demo) is not a change. Read and written while holding the speaker lock.
if [ -z "${2:-}" ] && [ "$_fell_back" = 0 ] && [ -x "$PIPER_BIN" ] && [ -f "$MODEL_FILE" ]; then   # a stand-in, or no Piper, does not count
    _voices_file="$HOME/.config/travis/voices"
    _voice_key="${TRAVIS_PROJECT_ROOT:-global}|${_role:-all}"
    _voice_key="${_voice_key//$'\t'/ }"; _voice_key="${_voice_key//$'\n'/ }"   # one line, one tab per entry
    _last_voice="$(TRAVIS_K="$_voice_key" awk -F'\t' '$1 == ENVIRON["TRAVIS_K"] { v = $2 } END { print v }' "$_voices_file" 2>/dev/null)"
    if [ "$_last_voice" != "$VOICE_NAME" ]; then
        MESSAGE="$(travis_voice_intro "$VOICE_NAME" "$_role") $MESSAGE"
        mkdir -p "$(dirname "$_voices_file")" 2>/dev/null
        { TRAVIS_K="$_voice_key" awk -F'\t' '$1 != ENVIRON["TRAVIS_K"]' "$_voices_file" 2>/dev/null; printf '%s\t%s\n' "$_voice_key" "$VOICE_NAME"; } \
            > "$_voices_file.tmp" 2>/dev/null && mv -f "$_voices_file.tmp" "$_voices_file"
    fi
fi

# ── Speak ────────────────────────────────────────────────────────────────────
if [ -x "$PIPER_BIN" ] && [ -f "$MODEL_FILE" ]; then
    echo "Announcing [$SPEAKER]: $MESSAGE"
    WAV="$(mktemp "${TMPDIR:-/tmp}/announce_speech.XXXXXX")" || WAV="/tmp/announce_speech_$$.tmp"
    WIN_WAV=""
    # One cleanup for every exit path; INT/TERM (e.g. a hook timeout) exit through the EXIT trap.
    trap 'rm -f "$WAV" "$WAV.pad" "$WIN_WAV" "$AFPLAY_PID_FILE"; rm -rf "$LOCK_DIR"' EXIT
    trap 'exit 130' INT TERM
    # stdout too: piper prints the output path, which is noise next to the "Announcing" line.
    printf '%s\n' "$MESSAGE" | "$PIPER_BIN" --model "$MODEL_FILE" --length_scale "$LENGTH_SCALE" --output_file "$WAV" >/dev/null 2>&1
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Prepend 300 ms of silence so Bluetooth/wireless audio devices have time to wake up
        # and don't swallow the first syllable. Same fix as the WSL path above.
        python3 - "$WAV" "$WAV.pad" <<'PY' 2>/dev/null && mv -f "$WAV.pad" "$WAV"
import sys, wave
src, dst = sys.argv[1], sys.argv[2]
with wave.open(src, 'rb') as r:
    params, frames = r.getparams(), r.readframes(r.getnframes())
pad = b'\0' * int(params.framerate * 0.3) * params.sampwidth * params.nchannels
with wave.open(dst, 'wb') as w:
    w.setparams(params)
    w.writeframes(pad + frames)
PY
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
            log_play "windows"
            powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '${PS_PATH//\'/\'\'}').PlaySync()" >/dev/null 2>&1
            rm -f "$WIN_WAV"
        else
            log_play "wslg-paplay"
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
    # Not Travis's real voice: Piper (or every voice model) is missing. Say so, and how to fix it.
    echo "Piper TTS or its voice models are missing, so this is the robotic espeak voice. Run $SCRIPT_DIR/install.sh to fix it." >&2
    echo "Announcing (espeak fallback): $MESSAGE"
    # Text on stdin, never argv: a message like "-w/some/file" would be parsed as an option.
    printf '%s\n' "$MESSAGE" | espeak --stdin -s 140 -v en-us
elif command -v say >/dev/null 2>&1; then
    echo "Announcing (say fallback): $MESSAGE"
    _say_rate_args=""
    [ -n "${TRAVIS_SAY_RATE:-}" ] && _say_rate_args="-r ${TRAVIS_SAY_RATE}"
    # shellcheck disable=SC2086
    printf '%s\n' "$MESSAGE" | say $_say_rate_args -f -
else
    echo "TTS: $MESSAGE"
fi
