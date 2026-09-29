#!/bin/bash

# travis-config.sh — sourced by all Travis scripts to load env config.
#
# Config is loaded in priority order (lowest to highest — later wins):
#   1. Built-in defaults (below)
#   2. ~/.config/travis/travis.env   — global user config
#   3. <project>/.claude/travis.env  — per-project overrides
#      (project root = first ancestor of $CWD that has a .claude/ dir)
#   4. Environment variables already set by the caller (highest priority)
#
# Available variables:
#   TRAVIS_STOP_HOOK=on|off          Stop hook auto-announcement (default: on)
#   TRAVIS_START_WORK=on|off         "On it." on task start (default: on)
#   TRAVIS_NAG=on|off                Idle waiting nagger (default: on)
#   TRAVIS_ANNOUNCE=on|off           Manual claude-announce.sh (default: on)
#   TRAVIS_VOICE=ryan|amy|alan         Default voice (default: ryan)
#   TRAVIS_STOP_MAX_CHARS=N          Max chars spoken by Stop hook (default: 300)
#   CLAUDE_NAG_INTERVALS="60 60 300" Nag schedule in seconds

# Snapshot a variable if it is set. Outputs an eval-able assignment or nothing.
_travis_snapshot() {
    local var="$1"
    # ${!var+x} expands to "x" if var is set (even if empty), "" if unset
    if [ -n "${!var+x}" ]; then
        printf '%s=%q\n' "$var" "${!var}"
    fi
}

_travis_load_config() {
    # Snapshot caller-set vars before loading files (so they can win at the end)
    local _snap_STOP_HOOK; _snap_STOP_HOOK="$(_travis_snapshot TRAVIS_STOP_HOOK)"
    local _snap_START_WORK; _snap_START_WORK="$(_travis_snapshot TRAVIS_START_WORK)"
    local _snap_NAG; _snap_NAG="$(_travis_snapshot TRAVIS_NAG)"
    local _snap_ANNOUNCE; _snap_ANNOUNCE="$(_travis_snapshot TRAVIS_ANNOUNCE)"
    local _snap_VOICE; _snap_VOICE="$(_travis_snapshot TRAVIS_VOICE)"
    local _snap_MAX_CHARS; _snap_MAX_CHARS="$(_travis_snapshot TRAVIS_STOP_MAX_CHARS)"
    local _snap_INTERVALS; _snap_INTERVALS="$(_travis_snapshot CLAUDE_NAG_INTERVALS)"

    # 1. Global user config
    local global_env="$HOME/.config/travis/travis.env"
    # shellcheck source=/dev/null
    [ -f "$global_env" ] && source "$global_env"

    # 2. Per-project config: walk up from CWD to find .claude/travis.env
    local dir="${CWD:-$(pwd)}"
    local project_env=""
    while true; do
        if [ -f "$dir/.claude/travis.env" ]; then
            project_env="$dir/.claude/travis.env"
            break
        fi
        local parent
        parent="$(dirname "$dir")"
        [ "$parent" = "$dir" ] && break
        dir="$parent"
    done
    # shellcheck source=/dev/null
    [ -f "$project_env" ] && source "$project_env"

    # 3. Restore caller-set vars so they always win over file config
    [ -n "$_snap_STOP_HOOK"  ] && eval "$_snap_STOP_HOOK"
    [ -n "$_snap_START_WORK" ] && eval "$_snap_START_WORK"
    [ -n "$_snap_NAG"        ] && eval "$_snap_NAG"
    [ -n "$_snap_ANNOUNCE"   ] && eval "$_snap_ANNOUNCE"
    [ -n "$_snap_VOICE"      ] && eval "$_snap_VOICE"
    [ -n "$_snap_MAX_CHARS"  ] && eval "$_snap_MAX_CHARS"
    [ -n "$_snap_INTERVALS"  ] && eval "$_snap_INTERVALS"
}

_travis_load_config
