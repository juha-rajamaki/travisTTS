#!/bin/bash

# Stop hook — reads last_assistant_message from Claude Code's Stop hook JSON
# and speaks it via Travis. Wired as a Stop hook in ~/.claude/settings.json.
#
# Claude Code pipes JSON to stdin:
#   { "last_assistant_message": "...", "hook_event_name": "Stop", ... }
#
# The message is trimmed to TRAVIS_STOP_MAX_CHARS (default 300) before speaking
# so long responses don't become a wall of speech.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAX_CHARS="${TRAVIS_STOP_MAX_CHARS:-300}"

# Read JSON from stdin (Claude passes it automatically).
# `timeout` is unreliable on macOS; use IFS read with a 2-second deadline instead.
HOOK_JSON=""
if [ -t 0 ]; then
    : # no stdin (interactive call) — skip
else
    IFS= read -r -t 2 HOOK_JSON 2>/dev/null || true
    # Handle multi-line JSON by reading remaining lines
    while IFS= read -r -t 0.1 line 2>/dev/null; do
        HOOK_JSON="${HOOK_JSON}${line}"
    done
fi

# Extract last_assistant_message
MSG="$(printf '%s' "$HOOK_JSON" | python3 -c "
import sys, json, re
try:
    data = json.load(sys.stdin)
    msg = data.get('last_assistant_message', '')
    # Strip markdown: code fences, bold/italic, backticks, headings
    msg = re.sub(r'\`\`\`.*?\`\`\`', '', msg, flags=re.DOTALL)
    msg = re.sub(r'[#*\`_>]', '', msg)
    # Collapse whitespace
    msg = ' '.join(msg.split())
    print(msg[:int(sys.argv[1])])
except Exception:
    pass
" "$MAX_CHARS" 2>/dev/null)"

# Fall back to a generic message if extraction failed or message is empty
if [ -z "$MSG" ]; then
    MSG="Done."
fi

"$SCRIPT_DIR/claude-announce.sh" "$MSG" </dev/null
