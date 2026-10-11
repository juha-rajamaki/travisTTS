#!/bin/bash

# deploy-announce.sh — speak a deploy or publish announcement.
#
# The deploy role's voice with TRAVIS_MULTIVOICE=on (TRAVIS_VOICE_DEPLOY or TRAVIS_DEPLOY_VOICE,
# default joe); otherwise TRAVIS_DEPLOY_VOICE, then TRAVIS_VOICE, then ryan.
# Same as: TRAVIS_ROLE=deploy claude-announce.sh "..." but without the nag repeats.
# Inherits the on/off state from TRAVIS_ANNOUNCE so a single toggle
# silences all Claude announcements including deploys.
#
# Usage:
#   deploy-announce.sh "Deployed to production successfully."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/travis-config.sh"

MESSAGE="$1"
if [ -z "$MESSAGE" ]; then
    echo "Usage: deploy-announce.sh \"message\""
    exit 1
fi

[ "${TRAVIS_ANNOUNCE:-on}" = "off" ] && exit 0

VOICE="$(travis_role_voice deploy)"
[ -z "$VOICE" ] && VOICE="${TRAVIS_DEPLOY_VOICE:-${TRAVIS_VOICE:-ryan}}"
"$SCRIPT_DIR/announce.sh" "$MESSAGE" "$VOICE"
