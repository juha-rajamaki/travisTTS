#!/bin/bash

# testvoice.sh — check that every Claude Code role is spoken in the right voice.
#
# Runs the real hook commands from this project's .claude/settings.json with a simulated hook
# event, so it tests the wiring (matchers, voice overrides, config) and not just announce.sh.
# The voice is read back from announce.sh's "Announcing (<voice>)" line, which names the model
# that actually spoke, so a missing model that falls back to another voice shows up as a FAIL.
#
# Usage: ./testvoice.sh [single|multi]
#   (no argument)  detect the mode from .claude/settings.json
#   single         every role speaks through the Stop hook in the default voice (ryan)
#   multi          each role speaks through its own hook:
#                    planning  -> amy      (SubagentStop, agent "Plan")
#                    coding    -> default voice, ryan  (Stop)
#                    security  -> alan     (SubagentStop, agent "code-security-auditor")
#
# Exit status is 0 only when every role was spoken in the expected voice.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="$SCRIPT_DIR/.claude/settings.json"

# Hooks run with the project as cwd, so resolve config the same way. A TRAVIS_VOICE exported in
# this shell would override every role and hide what the hooks do, so drop it.
cd "$SCRIPT_DIR" || exit 1
unset TRAVIS_VOICE
# shellcheck source=travis-config.sh
source "$SCRIPT_DIR/travis-config.sh"
DEFAULT_VOICE="${TRAVIS_VOICE:-ryan}"

# Format: "role:hook_event:agent_type:multi_voice:message"
# multi_voice "default" means the project's default voice.
ROLES=(
    "planning:SubagentStop:Plan:amy:Planning is done."
    "coding:Stop::default:Coding is done."
    "security:SubagentStop:code-security-auditor:alan:Security review is done."
)

# Print the first stop-hook.sh command registered for <event> whose matcher matches <agent_type>.
hook_command() {
    [ -f "$SETTINGS" ] || return 1
    python3 - "$SETTINGS" "$1" "$2" <<'PY'
import json, re, sys
path, event, agent = sys.argv[1:4]
try:
    hooks = json.load(open(path)).get("hooks", {})
except Exception:
    sys.exit(1)
for entry in hooks.get(event, []):
    matcher = entry.get("matcher", "")
    if matcher and not re.search(matcher, agent):
        continue
    for h in entry.get("hooks", []):
        cmd = h.get("command", "")
        if h.get("type") == "command" and "stop-hook.sh" in cmd:
            print(cmd)
            sys.exit(0)
sys.exit(1)
PY
}

# Multi-voice when any SubagentStop hook speaks through stop-hook.sh.
detect_mode() {
    python3 - "$SETTINGS" <<'PY' 2>/dev/null
import json, sys
try:
    hooks = json.load(open(sys.argv[1])).get("hooks", {})
except Exception:
    print("single"); sys.exit(0)
multi = any("stop-hook.sh" in h.get("command", "")
            for e in hooks.get("SubagentStop", []) for h in e.get("hooks", []))
print("multi" if multi else "single")
PY
}

MODE="${1:-$(detect_mode)}"
case "$MODE" in
    single|multi) ;;
    *) echo "Usage: testvoice.sh [single|multi]"; exit 2 ;;
esac

STOP_CMD="$(hook_command Stop "")"
if [ -z "$STOP_CMD" ]; then
    echo "FAIL: no Stop hook running stop-hook.sh in $SETTINGS"
    exit 1
fi

echo ""
echo "Travis TTS — voice test ($MODE voice, default voice: $DEFAULT_VOICE)"
echo "════════════════════════════════════════════════════════════"
echo ""

failures=0
for entry in "${ROLES[@]}"; do
    IFS=: read -r role event agent multi_voice message <<< "$entry"

    if [ "$MODE" = "single" ]; then
        # Single voice: only the Stop hook speaks, always in the default voice.
        expected="$DEFAULT_VOICE"
        cmd="$STOP_CMD"
        event="Stop"
    else
        [ "$multi_voice" = "default" ] && expected="$DEFAULT_VOICE" || expected="$multi_voice"
        if [ "$event" = "Stop" ]; then
            cmd="$STOP_CMD"
        else
            cmd="$(hook_command "$event" "$agent")"
        fi
    fi

    printf "  %-9s expect %-8s " "$role" "$expected"
    if [ -z "$cmd" ]; then
        echo "FAIL  (no $event hook matches agent \"$agent\")"
        failures=$(( failures + 1 ))
        continue
    fi

    # Say which voice SHOULD be speaking, so a wrong voice is audible, not just printed.
    message="$message This should be $expected speaking."
    json="$(python3 -c 'import json,sys; print(json.dumps({"hook_event_name": sys.argv[1], "agent_type": sys.argv[2], "last_assistant_message": sys.argv[3]}))' "$event" "$agent" "$message")"
    # Force speech on for the test: DND and the Stop-hook switch would otherwise silence it.
    out="$(printf '%s' "$json" | CLAUDE_PROJECT_DIR="$SCRIPT_DIR" TRAVIS_QUIET_FROM= TRAVIS_QUIET_TO= TRAVIS_STOP_HOOK=on bash -c "$cmd" 2>&1)"
    heard="$(printf '%s' "$out" | sed -n 's/.*Announcing (\([^)]*\)).*/\1/p' | head -1)"

    if [ "$heard" = "$expected" ]; then
        echo "ok    (heard $heard)"
    else
        echo "FAIL  (heard ${heard:-nothing})"
        [ -n "$heard" ] && echo "            model for \"$expected\" missing? run: ./voicemodels.sh --download $expected"
        failures=$(( failures + 1 ))
    fi
done

echo ""
if [ "$failures" -eq 0 ]; then
    echo "All roles spoke in the expected voice."
else
    echo "$failures role(s) failed."
fi
exit $(( failures > 0 ))
