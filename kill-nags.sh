#!/bin/bash
# Kill pending Travis nag announcements. Called by Claude Code PreToolUse hook
# so nags stop the moment Claude starts working again.
NAG_PID_FILE="$(dirname "$0")/.claude-announce-nag-pids"
if [ -f "$NAG_PID_FILE" ]; then
    while IFS= read -r pid; do
        kill "$pid" 2>/dev/null || true
    done < "$NAG_PID_FILE"
    rm -f "$NAG_PID_FILE"
fi
