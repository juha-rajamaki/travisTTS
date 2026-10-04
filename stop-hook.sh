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
#   TRAVIS_MULTIVOICE=on          speak in the role's voice: the main session as coding (ryan),
#                                 a Plan agent as planning (jenny), a security agent as security
#                                 (alan). Wire subagents with a SubagentStop hook to this script.
#
# A TRAVIS_VOICE set on the hook command itself still wins over the role's voice.

# Before the config is loaded, which merges the files' TRAVIS_VOICE into the same variable.
CALLER_VOICE="${TRAVIS_VOICE-}"

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

AGENT_TYPE="$(printf '%s' "$HOOK_JSON" | python3 -c "
import sys, json
try:
    print(str(json.load(sys.stdin).get('agent_type') or '')[:100])
except Exception:
    pass
" 2>/dev/null)"

VOICE="$CALLER_VOICE"
[ -z "$VOICE" ] && VOICE="$(travis_role_voice "$(travis_role "$AGENT_TYPE")")"

if [ -n "$VOICE" ]; then
    "$SCRIPT_DIR/announce.sh" "$MSG" "$VOICE" </dev/null
else
    "$SCRIPT_DIR/announce.sh" "$MSG" </dev/null
fi
