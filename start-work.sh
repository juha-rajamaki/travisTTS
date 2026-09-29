#!/bin/bash

# start-work.sh — says "On it." on the first tool use after a user prompt.
#
# arm/fire pair: arm is called on UserPromptSubmit, fire on PreToolUse.
# Speaks once per prompt then disarms until the next prompt.
#
# Config (travis.env):
#   TRAVIS_START_WORK=off   disable entirely
#   TRAVIS_VOICE=ryan|...   voice to use

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=travis-config.sh
source "$SCRIPT_DIR/travis-config.sh"

FLAG_FILE="$SCRIPT_DIR/.start-work-armed"

is_off() { [ "${TRAVIS_START_WORK:-on}" = "off" ]; }

case "$1" in
    arm)
        is_off && exit 0
        touch "$FLAG_FILE"
        ;;
    fire)
        if [ -f "$FLAG_FILE" ]; then
            rm -f "$FLAG_FILE"
            is_off && exit 0
            "$SCRIPT_DIR/announce.sh" "On it." "${TRAVIS_VOICE:-ryan}"
        fi
        ;;
    status)
        if is_off; then echo "OFF (travis.env)"; else echo "ON"; fi
        ;;
    *)
        echo "Usage: start-work.sh arm | fire | status"
        exit 1
        ;;
esac
