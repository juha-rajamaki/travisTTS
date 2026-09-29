#!/bin/bash

# start-work.sh — says "On it." on the first tool use after a user prompt.
#
# Wired as a PreToolUse hook. Uses a state flag file that is:
#   - SET   by the UserPromptSubmit hook (new prompt arrived)
#   - CLEARED here on the first PreToolUse (Claude just started working)
#
# This way only the very first tool call speaks — not every tool call.
#
# Usage (hooks):
#   UserPromptSubmit -> start-work.sh arm
#   PreToolUse       -> start-work.sh fire

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAG_FILE="$SCRIPT_DIR/.start-work-armed"
STATE_FILE="$SCRIPT_DIR/.start-work-enabled"

is_off() { [ -f "$STATE_FILE" ] && [ "$(tr -d '[:space:]' < "$STATE_FILE")" = "off" ]; }

case "$1" in
    arm)
        is_off && exit 0
        touch "$FLAG_FILE"
        ;;
    fire)
        if [ -f "$FLAG_FILE" ]; then
            rm -f "$FLAG_FILE"
            is_off && exit 0
            "$SCRIPT_DIR/travis" "On it."
        fi
        ;;
    on|enable)
        echo "on" > "$STATE_FILE"
        echo "Start-work announcement: ON"
        ;;
    off|disable)
        echo "off" > "$STATE_FILE"
        rm -f "$FLAG_FILE"
        echo "Start-work announcement: OFF"
        ;;
    status)
        if is_off; then echo "OFF"; else echo "ON"; fi
        ;;
    *)
        echo "Usage: start-work.sh arm | fire | on | off | status"
        exit 1
        ;;
esac
