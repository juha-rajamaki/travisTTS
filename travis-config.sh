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
#   TRAVIS_VOICE=ryan|amy|alan|jenny|kristin  Default voice (default: ryan)
#   TRAVIS_STOP_MAX_CHARS=N          Max chars spoken by Stop hook (default: 300)
#   CLAUDE_NAG_INTERVALS="60 60 300" Nag schedule in seconds
#   TRAVIS_QUIET_FROM=HH:MM          Start of do-not-disturb window (default: unset)
#   TRAVIS_QUIET_TO=HH:MM            End of do-not-disturb window (default: unset)
#   TRAVIS_ACTIVE_FROM=HH:MM         Start of active hours; speech only inside (default: unset = always)
#   TRAVIS_ACTIVE_TO=HH:MM           End of active hours (default: unset = always)

# Snapshot a variable if it is set. Outputs an eval-able assignment or nothing.
_travis_snapshot() {
    local var="$1"
    # ${!var+x} expands to "x" if var is set (even if empty), "" if unset
    if [ -n "${!var+x}" ]; then
        printf '%s=%q\n' "$var" "${!var}"
    fi
}

# Read a travis.env file WITHOUT executing it. The project lookup walks up from $CWD, so a
# travis.env can come from any cloned repo; sourcing it would run that repo's shell code on
# every hook. Only known keys with plain values are accepted, everything else is ignored.
_TRAVIS_KEYS='TRAVIS_STOP_HOOK|TRAVIS_START_WORK|TRAVIS_NAG|TRAVIS_ANNOUNCE|TRAVIS_VOICE|TRAVIS_STOP_MAX_CHARS|CLAUDE_NAG_INTERVALS|TRAVIS_QUIET_FROM|TRAVIS_QUIET_TO|TRAVIS_ACTIVE_FROM|TRAVIS_ACTIVE_TO'
_TRAVIS_LINE_RE="^[[:space:]]*(export[[:space:]]+)?($_TRAVIS_KEYS)=(.*)\$"
_TRAVIS_DQ_RE='^"([^"]*)"'
_TRAVIS_SQ_RE="^'([^']*)'"
_TRAVIS_SAFE_RE='^[A-Za-z0-9:._ -]*$'

_travis_read_env() {
    local line key val
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [[ "$line" =~ $_TRAVIS_LINE_RE ]] || continue
        key="${BASH_REMATCH[2]}"
        val="${BASH_REMATCH[3]}"
        if [[ "$val" =~ $_TRAVIS_DQ_RE ]] || [[ "$val" =~ $_TRAVIS_SQ_RE ]]; then
            val="${BASH_REMATCH[1]}"
        else
            val="${val%%#*}"                        # drop trailing comment
            val="${val%"${val##*[![:space:]]}"}"    # trim trailing whitespace
        fi
        [[ "$val" =~ $_TRAVIS_SAFE_RE ]] || continue
        printf -v "$key" '%s' "$val"
    done < "$1"
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
    local _snap_QUIET_FROM; _snap_QUIET_FROM="$(_travis_snapshot TRAVIS_QUIET_FROM)"
    local _snap_QUIET_TO;   _snap_QUIET_TO="$(_travis_snapshot TRAVIS_QUIET_TO)"
    local _snap_ACTIVE_FROM; _snap_ACTIVE_FROM="$(_travis_snapshot TRAVIS_ACTIVE_FROM)"
    local _snap_ACTIVE_TO;   _snap_ACTIVE_TO="$(_travis_snapshot TRAVIS_ACTIVE_TO)"

    # 1. Global user config
    local global_env="$HOME/.config/travis/travis.env"
    [ -f "$global_env" ] && _travis_read_env "$global_env"

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
    [ -f "$project_env" ] && _travis_read_env "$project_env"

    # 3. Restore caller-set vars so they always win over file config
    [ -n "$_snap_STOP_HOOK"  ] && eval "$_snap_STOP_HOOK"
    [ -n "$_snap_START_WORK" ] && eval "$_snap_START_WORK"
    [ -n "$_snap_NAG"        ] && eval "$_snap_NAG"
    [ -n "$_snap_ANNOUNCE"   ] && eval "$_snap_ANNOUNCE"
    [ -n "$_snap_VOICE"      ] && eval "$_snap_VOICE"
    [ -n "$_snap_MAX_CHARS"  ] && eval "$_snap_MAX_CHARS"
    [ -n "$_snap_INTERVALS"  ] && eval "$_snap_INTERVALS"
    [ -n "$_snap_QUIET_FROM" ] && eval "$_snap_QUIET_FROM"
    [ -n "$_snap_QUIET_TO"   ] && eval "$_snap_QUIET_TO"
    [ -n "$_snap_ACTIVE_FROM" ] && eval "$_snap_ACTIVE_FROM"
    [ -n "$_snap_ACTIVE_TO"   ] && eval "$_snap_ACTIVE_TO"
}

_travis_load_config

# _travis_hhmm <HH:MM> — prints minutes since midnight, or fails if not a valid 24h time.
# Strict parsing: a value like "8am" or "25:00" must not be silently compared as a number.
_travis_hhmm() {
    [[ "$1" =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] || return 1
    echo $(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
}

# _travis_in_window <FROM> <TO> — returns 0 if the current time is in [FROM, TO).
# Handles overnight windows (e.g. 22:00–08:00); FROM == TO covers the whole day.
# Returns 2 if either bound is missing or invalid, so callers can treat the window as unset.
_travis_in_window() {
    local from to now
    from="$(_travis_hhmm "${1:-}")" || return 2
    to="$(_travis_hhmm "${2:-}")"   || return 2
    now="$(_travis_hhmm "$(date +%H:%M)")" || return 2
    if [ "$from" -lt "$to" ]; then
        [ "$now" -ge "$from" ] && [ "$now" -lt "$to" ]
    else
        [ "$now" -ge "$from" ] || [ "$now" -lt "$to" ]
    fi
}

# travis_is_quiet — returns 0 (true) if current time is inside the DND window.
travis_is_quiet() {
    _travis_in_window "${TRAVIS_QUIET_FROM:-}" "${TRAVIS_QUIET_TO:-}"
}

# travis_active_hours_set — returns 0 if a valid active-hours window is configured.
travis_active_hours_set() {
    _travis_hhmm "${TRAVIS_ACTIVE_FROM:-}" >/dev/null && _travis_hhmm "${TRAVIS_ACTIVE_TO:-}" >/dev/null
}

# travis_is_active — returns 0 (true) if Travis may speak now according to active hours.
# With no (or an invalid) active-hours window configured, Travis is always active.
travis_is_active() {
    travis_active_hours_set || return 0
    _travis_in_window "$TRAVIS_ACTIVE_FROM" "$TRAVIS_ACTIVE_TO"
}
