#!/bin/bash
# travis mute — silence all TTS for a given period, then auto-restore.
#
# Usage:
#   mute.sh 1h          mute for 1 hour
#   mute.sh 30m         mute for 30 minutes
#   mute.sh 2h30m       mute for 2h 30m
#   mute.sh             mute indefinitely (until 'mute.sh off')
#   mute.sh off         unmute immediately
#   mute.sh status      show mute status
#
# Mute is implemented via TRAVIS_QUIET_FROM/TO written into a temporary
# override file (~/.config/travis/mute.env) that travis-config.sh picks
# up automatically. The file is removed when the mute expires or is lifted.
#
# A background watcher unmutes at the right time — it writes a sentinel
# and exits, so there is no long-running daemon to worry about.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUTE_ENV="$HOME/.config/travis/mute.env"
MUTE_PID_FILE="$SCRIPT_DIR/.mute-watcher.pid"
CONFIG_DIR="$HOME/.config/travis"

mkdir -p "$CONFIG_DIR"

# ── Parse duration ────────────────────────────────────────────────────────────
# Returns seconds, or 0 for indefinite, or -1 on error.
parse_duration() {
    local s="$1"
    local total=0 matched=0
    if [[ "$s" =~ ^([0-9]+)h$ ]]; then
        total=$(( ${BASH_REMATCH[1]} * 3600 )); matched=1
    elif [[ "$s" =~ ^([0-9]+)m$ ]]; then
        total=$(( ${BASH_REMATCH[1]} * 60 )); matched=1
    elif [[ "$s" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
        total=$(( ${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60 )); matched=1
    elif [[ "$s" =~ ^([0-9]+)$ ]]; then
        total=$(( ${BASH_REMATCH[1]} * 60 )); matched=1  # bare number = minutes
    fi
    [ "$matched" = "1" ] && echo "$total" || echo "-1"
}

hhmm() { date -r "$1" +%H:%M 2>/dev/null || date -d "@$1" +%H:%M 2>/dev/null; }
now_epoch() { date +%s; }

kill_watcher() {
    if [ -f "$MUTE_PID_FILE" ]; then
        local pid; pid="$(cat "$MUTE_PID_FILE" 2>/dev/null)"
        [ -n "$pid" ] && kill "$pid" 2>/dev/null
        rm -f "$MUTE_PID_FILE"
    fi
}

write_mute_env() {
    local from="$1" to="$2" until_epoch="$3"
    cat > "$MUTE_ENV" <<EOF
# Travis mute — auto-generated, do not edit.
# Expires: $([ -n "$until_epoch" ] && hhmm "$until_epoch" || echo "never")
TRAVIS_QUIET_FROM=$from
TRAVIS_QUIET_TO=$to
EOF
}

do_unmute() {
    rm -f "$MUTE_ENV"
    kill_watcher
    echo "Travis unmuted."
    "$SCRIPT_DIR/announce.sh" "Travis unmuted." "${TRAVIS_STOP_VOICE:-${TRAVIS_VOICE:-ryan}}" >/dev/null 2>&1 &
}

do_status() {
    if [ ! -f "$MUTE_ENV" ]; then
        echo "Travis is NOT muted."
        return
    fi
    local from to
    from="$(grep TRAVIS_QUIET_FROM "$MUTE_ENV" | cut -d= -f2)"
    to="$(grep TRAVIS_QUIET_TO   "$MUTE_ENV" | cut -d= -f2)"
    local expires
    expires="$(grep 'Expires:' "$MUTE_ENV" | sed 's/.*Expires: //')"
    echo "Travis is MUTED ($from–$to, until: $expires)"
}

# ── Commands ──────────────────────────────────────────────────────────────────
case "$1" in
    off|unmute|--off)
        do_unmute
        exit 0
        ;;
    status|--status)
        do_status
        exit 0
        ;;
esac

# Duration argument (or empty for indefinite)
ARG="${1:-}"
SECS=0
INDEFINITE=0

if [ -z "$ARG" ]; then
    INDEFINITE=1
else
    SECS="$(parse_duration "$ARG")"
    if [ "$SECS" = "-1" ]; then
        echo "Usage: mute.sh [1h|30m|2h30m|<minutes>|off|status]"
        exit 1
    fi
fi

# Kill any previous watcher
kill_watcher

NOW="$(now_epoch)"

if [ "$INDEFINITE" = "1" ]; then
    # Mute from now until midnight (a window that definitely covers the rest of today).
    FROM="$(date +%H:%M)"
    write_mute_env "$FROM" "23:59" ""
    echo "Travis muted indefinitely (until 'mute.sh off')."
else
    UNTIL=$(( NOW + SECS ))
    FROM="$(date +%H:%M)"
    TO="$(hhmm "$UNTIL")"
    write_mute_env "$FROM" "$TO" "$UNTIL"

    HUMAN=""
    local_h=$(( SECS / 3600 ))
    local_m=$(( (SECS % 3600) / 60 ))
    [ "$local_h" -gt 0 ] && HUMAN="${local_h}h"
    [ "$local_m" -gt 0 ] && HUMAN="${HUMAN}${local_m}m"
    [ -z "$HUMAN" ] && HUMAN="${SECS}s"

    echo "Travis muted for $HUMAN (until $TO)."

    # Background watcher: sleep until expiry, then unmute.
    (
        sleep "$SECS"
        rm -f "$MUTE_ENV"
        rm -f "$MUTE_PID_FILE"
        # Speak the unmute notice (quiet window is now gone).
        source "$SCRIPT_DIR/travis-config.sh" 2>/dev/null
        "$SCRIPT_DIR/announce.sh" "Travis is back." "${TRAVIS_STOP_VOICE:-${TRAVIS_VOICE:-ryan}}" >/dev/null 2>&1
    ) >/dev/null 2>&1 &
    echo $! > "$MUTE_PID_FILE"
fi
