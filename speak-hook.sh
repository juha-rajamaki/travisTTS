#!/bin/bash

# speak-hook.sh — "speak with travis <text>" typed in a Claude session speaks <text>.
#
# Wired as a UserPromptSubmit hook. A prompt that starts with "speak with travis"
# (any case, optionally followed by ":" "," or "-") is spoken by Travis and blocked,
# so Claude never sees it. Every other prompt passes through untouched.
#
#   speak with travis: the build is green, go get coffee
#
# Speech goes through announce.sh, so voice, mute, DND and active hours all apply.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

HOOK_JSON=""
if [ ! -t 0 ]; then
    IFS= read -r -d '' -t 5 HOOK_JSON 2>/dev/null || true
fi

# Prints the text to speak (possibly empty) when the prompt is a speak command; exits 1 otherwise.
TEXT="$(printf '%s' "$HOOK_JSON" | python3 -c "
import sys, json, re
try:
    prompt = json.load(sys.stdin).get('prompt') or ''
except Exception:
    sys.exit(1)
m = re.match(r'\s*speak\s+with\s+travis(?![\w\x27-])[\s:,.-]*(.*)', prompt, flags=re.IGNORECASE | re.DOTALL)
if not m:
    sys.exit(1)
text = ' '.join(m.group(1).split())
if len(text) >= 2 and text[0] == text[-1] and text[0] in '\"\'':
    text = text[1:-1].strip()
print(text[:2000])
" 2>/dev/null)" || exit 0

# Block the prompt; the reason is shown to the user instead of being sent to Claude.
block() {
    rm -f "$SCRIPT_DIR/.start-work-armed"   # no tool call follows a blocked prompt, so don't leave "On it." armed
    python3 -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' "$1"
    exit 0
}

[ -z "$TEXT" ] && block 'Travis: nothing to say. Usage: speak with travis <text>'

# Detached, so a long message doesn't hold the prompt up or hit the hook timeout.
nohup "$SCRIPT_DIR/announce.sh" "$TEXT" </dev/null >/dev/null 2>&1 &

block "Travis says: $TEXT"
