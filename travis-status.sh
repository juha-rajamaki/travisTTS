#!/bin/bash

# travis-status.sh — show live state of all Travis features.
# Usage: ./travis-status.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=travis-config.sh
source "$SCRIPT_DIR/travis-config.sh"

# ── Helpers ──────────────────────────────────────────────────────────────────

on_off() {
    # on_off <value> — prints coloured ON or OFF
    if [ "$1" = "on" ]; then printf "ON "; else printf "OFF"; fi
}

file_switch() {
    # file_switch <state_file> — reads an on/off state file, defaults to "on"
    local f="$1"
    [ -f "$f" ] && tr -d '[:space:]' < "$f" || echo "on"
}

nag_running() {
    local pid_file="$SCRIPT_DIR/.waiting-nag.pid"
    local pid
    pid="$(cat "$pid_file" 2>/dev/null)"
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

waited_for() {
    local start_file="$SCRIPT_DIR/.waiting-nag.started"
    local began now
    began="$(cat "$start_file" 2>/dev/null)" || return
    [ -n "$began" ] || return
    now="$(date +%s)"
    local secs=$(( now - began ))
    [ "$secs" -lt 0 ] && return
    if [ "$secs" -ge 60 ]; then printf '%dm%02ds' $(( secs / 60 )) $(( secs % 60 ))
    else printf '%ds' "$secs"; fi
}

dnd_status() {
    if [ -z "${TRAVIS_QUIET_FROM:-}" ] || [ -z "${TRAVIS_QUIET_TO:-}" ]; then
        echo "disabled"
    elif travis_is_quiet; then
        echo "ACTIVE (${TRAVIS_QUIET_FROM}–${TRAVIS_QUIET_TO})"
    else
        echo "inactive (${TRAVIS_QUIET_FROM}–${TRAVIS_QUIET_TO})"
    fi
}

# ── Resolve effective feature states ─────────────────────────────────────────

# Each feature can be off via travis.env OR via its legacy state file.
# We show the effective state (both sources combined).

stop_hook_env="${TRAVIS_STOP_HOOK:-on}"
start_work_env="${TRAVIS_START_WORK:-on}"
nag_env="${TRAVIS_NAG:-on}"
announce_env="${TRAVIS_ANNOUNCE:-on}"

nag_file="$(file_switch "$SCRIPT_DIR/.waiting-nag-enabled")"
announce_file="$(file_switch "$SCRIPT_DIR/.claude-announce-enabled")"

stop_hook_state="$stop_hook_env"
start_work_state="$start_work_env"
nag_state="$( [ "$nag_env" = "off" ] || [ "$nag_file" = "off" ] && echo "off" || echo "on" )"
announce_state="$( [ "$announce_env" = "off" ] || [ "$announce_file" = "off" ] && echo "off" || echo "on" )"

# ── Resolve config source ─────────────────────────────────────────────────────

project_env=""
dir="$(pwd)"
while true; do
    if [ -f "$dir/.claude/travis.env" ]; then
        project_env="$dir/.claude/travis.env"
        break
    fi
    parent="$(dirname "$dir")"
    [ "$parent" = "$dir" ] && break
    dir="$parent"
done

# ── Print ─────────────────────────────────────────────────────────────────────

echo ""
echo "Travis TTS — status"
echo "════════════════════════════════════════"
echo ""
printf "  %-22s %s\n" "Voice:"         "${TRAVIS_VOICE:-ryan}"
printf "  %-22s %s\n" "Do-not-disturb:" "$(dnd_status)"
echo ""
printf "  %-22s %s\n" "Stop hook:"     "$(on_off "$stop_hook_state")  (speak when Claude finishes)"
printf "  %-22s %s\n" "Start work:"    "$(on_off "$start_work_state")  (say \"On it.\" when Claude starts)"
printf "  %-22s %s\n" "Idle nagger:"   "$(on_off "$nag_state")  (remind you while Claude waits)"
printf "  %-22s %s\n" "Manual announce:" "$(on_off "$announce_state")"
echo ""

# Nag loop live state
if nag_running; then
    w="$(waited_for)"
    printf "  %-22s %s\n" "Nagger running:" "yes${w:+, waiting ${w}}"
else
    printf "  %-22s %s\n" "Nagger running:" "no"
fi

echo ""
printf "  %-22s %s\n" "Stop max chars:"  "${TRAVIS_STOP_MAX_CHARS:-300}"
printf "  %-22s %s\n" "Nag intervals:"   "${CLAUDE_NAG_INTERVALS:-60 60 60 300 300 300}"
echo ""

# Config sources
printf "  %-22s %s\n" "Global config:"  "$HOME/.config/travis/travis.env"
if [ -n "$project_env" ]; then
    printf "  %-22s %s\n" "Project config:" "$project_env"
else
    printf "  %-22s %s\n" "Project config:" "(none)"
fi
echo ""
