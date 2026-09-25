#!/bin/bash

# Claude Code end-of-coding voice announcements (Travis / Piper).
#
# Speaking is delegated to travis, the Piper entry point, which renders
# the default voice and falls back to macOS `say` when piper isn't available.
#
# Usage:
#   claude-announce.sh "Short spoken summary"   # speak it + schedule 2 nag repeats
#   claude-announce.sh on        | enable        # turn announcements ON
#   claude-announce.sh off       | disable       # turn announcements OFF
#   claude-announce.sh status                    # print ON / OFF
#
# After each announcement, two nag repeats are scheduled:
#   • 1st nag at 60 s
#   • 2nd nag at 3 min (180 s after the first announcement)
# Starting a new announcement cancels any pending nags.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.claude-announce-enabled"
NAG_PID_FILE="$SCRIPT_DIR/.claude-announce-nag-pids"

is_off() {
    [ -f "$STATE_FILE" ] && [ "$(tr -d '[:space:]' < "$STATE_FILE")" = "off" ]
}

kill_nags() {
    if [ -f "$NAG_PID_FILE" ]; then
        while IFS= read -r pid; do
            [ -n "$pid" ] || continue
            pkill -P "$pid" 2>/dev/null || true
            kill "$pid" 2>/dev/null || true
        done < "$NAG_PID_FILE"
        rm -f "$NAG_PID_FILE"
    fi
}

speak() {
    local msg="$1"
    "$SCRIPT_DIR/travis" "$msg"
}

case "$1" in
    on|enable|--enable)
        echo "on" > "$STATE_FILE"
        echo "Claude voice announcements: ON"
        exit 0
        ;;
    off|disable|--disable)
        echo "off" > "$STATE_FILE"
        echo "Claude voice announcements: OFF"
        exit 0
        ;;
    status|--status)
        if is_off; then echo "OFF"; else echo "ON"; fi
        exit 0
        ;;
esac

MESSAGE="$1"
if [ -z "$MESSAGE" ]; then
    echo "Usage: claude-announce.sh \"message\" | on | off | status"
    exit 1
fi

# Silent no-op when disabled.
if is_off; then
    exit 0
fi

# Cancel any pending nags from the previous announcement.
kill_nags

# Speak immediately (foreground so the caller sees the echo before returning).
speak "$MESSAGE"

# Schedule nags in background: 60 s then 180 s from now, but only while
# waiting-nag is active (meaning Claude is still waiting for user input).
NAG_PID_FILE_WN="$SCRIPT_DIR/.waiting-nag.pid"

is_waiting() {
    local p
    p="$(cat "$NAG_PID_FILE_WN" 2>/dev/null)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

# Both nags detach from this script's stdout and stderr. Inheriting them keeps the caller's pipe
# open for three minutes after the announcement has been spoken — which, called from a tool that
# reads until end of output, looks exactly like a script that has hung.
(
    sleep 60
    is_off && exit 0
    is_waiting && speak "$MESSAGE"
) >/dev/null 2>&1 &
NAG1_PID=$!

(
    sleep 180
    is_off && exit 0
    is_waiting && speak "$MESSAGE"
) >/dev/null 2>&1 &
NAG2_PID=$!

# Save both PIDs so the next announcement can cancel them.
printf '%s\n%s\n' "$NAG1_PID" "$NAG2_PID" > "$NAG_PID_FILE"
