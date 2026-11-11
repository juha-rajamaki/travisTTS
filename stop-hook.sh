#!/bin/bash

# Stop hook — reads last_assistant_message from Claude Code's Stop hook JSON
# and speaks it via Travis. Wired as a Stop hook in ~/.claude/settings.json.
#
# Claude Code pipes JSON to stdin:
#   { "last_assistant_message": "...", "hook_event_name": "Stop", ... }
#
# Config (travis.env):
#   TRAVIS_STOP_HOOK=off          disable this hook entirely
#   TRAVIS_ANNOUNCE=off           also silences this hook (same as claude-announce.sh off)
#   TRAVIS_STOP_MAX_CHARS=N       max characters spoken (default 300), cut at the last whole sentence
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

# Also respect claude-announce.sh off — if the user muted manual announcements, the stop hook
# should be silent too.
_STATE_FILE="$SCRIPT_DIR/.claude-announce-enabled"
if [ "${TRAVIS_ANNOUNCE:-on}" = "off" ] || { [ -f "$_STATE_FILE" ] && [ "$(tr -d '[:space:]' < "$_STATE_FILE")" = "off" ]; }; then
    exit 0
fi

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
    limit = int(sys.argv[1])
    if len(msg) > limit:
        # End on the last whole sentence that fits, not mid-word; else on the last whole word.
        cut = msg[:limit + 1]
        ends = [m.end() for m in re.finditer(r'[.!?](?=\s)', cut)]
        if ends and ends[-1] >= limit // 3:
            msg = cut[:ends[-1]]
        else:
            msg = cut.rsplit(' ', 1)[0].rstrip(',;:') + '.'
    print(msg)
except Exception:
    pass
" "$MAX_CHARS" 2>/dev/null)"

[ -z "$MSG" ] && MSG="Done."

# Skip very short messages — they're usually acknowledgement one-liners (e.g. "Deployed.")
# that fire a second time when a background task notification arrives.
[ "${#MSG}" -lt 15 ] && exit 0

AGENT_TYPE="$(printf '%s' "$HOOK_JSON" | python3 -c "
import sys, json
try:
    print(str(json.load(sys.stdin).get('agent_type') or '')[:100])
except Exception:
    pass
" 2>/dev/null)"

# Voice: one set on the hook command > TRAVIS_STOP_VOICE (main session only) > the role's voice
# (multivoice) > the default.
ROLE="$(travis_role "$AGENT_TYPE")"
VOICE="$CALLER_VOICE"
[ -z "$VOICE" ] && [ "$ROLE" = "coding" ] && VOICE="${TRAVIS_STOP_VOICE:-}"
[ -z "$VOICE" ] && VOICE="$(travis_role_voice "$ROLE")"

if [ -n "$VOICE" ]; then
    "$SCRIPT_DIR/announce.sh" "$MSG" "$VOICE" </dev/null
else
    "$SCRIPT_DIR/announce.sh" "$MSG" </dev/null
fi
