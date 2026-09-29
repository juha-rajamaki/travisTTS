#!/bin/bash

# Stop hook — reads last_assistant_message from Claude Code's Stop hook JSON
# and speaks it via Travis. Wired as a Stop hook in ~/.claude/settings.json.
#
# Claude Code pipes JSON to stdin:
#   { "last_assistant_message": "...", "hook_event_name": "Stop", ... }
#
# Config (travis.env):
#   TRAVIS_STOP_HOOK=off          disable this hook entirely
#   TRAVIS_STOP_MAX_CHARS=N       max characters spoken (default 300)
#   TRAVIS_VOICE=ryan|amy|...     voice to use

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=travis-config.sh
source "$SCRIPT_DIR/travis-config.sh"

[ "${TRAVIS_STOP_HOOK:-on}" = "off" ] && exit 0

MAX_CHARS="${TRAVIS_STOP_MAX_CHARS:-300}"

# Read JSON from stdin (Claude passes it automatically).
# `timeout` is unreliable on macOS; read all of stdin up to EOF with a 5-second deadline instead.
# (A line-by-line read with a short per-line timeout could stop halfway through the JSON.)
HOOK_JSON=""
if [ -t 0 ]; then
    : # no stdin (interactive call) — skip
else
    IFS= read -r -d '' -t 5 HOOK_JSON 2>/dev/null || true
fi

MSG="$(printf '%s' "$HOOK_JSON" | python3 -c "
import sys, json, re
try:
    data = json.load(sys.stdin)
    msg = data.get('last_assistant_message', '')
    msg = re.sub(r'\`\`\`.*?\`\`\`', '', msg, flags=re.DOTALL)
    msg = re.sub(r'[#*\`_>]', '', msg)
    msg = ' '.join(msg.split())
    print(msg[:int(sys.argv[1])])
except Exception:
    pass
" "$MAX_CHARS" 2>/dev/null)"

[ -z "$MSG" ] && MSG="Done."

"$SCRIPT_DIR/announce.sh" "$MSG" </dev/null
