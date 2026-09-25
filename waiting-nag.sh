#!/bin/bash

# Repeating "Claude is waiting for you" voice nagger for Claude Code hooks.
#
# While Claude is waiting on the user, speaks a reminder (Piper voice)
# every INTERVAL seconds, repeating until the user answers. Wired via
# .claude/settings.json hooks:
#     Notification  -> waiting-nag.sh start   (Claude is now waiting)
#     UserPromptSubmit    -> waiting-nag.sh stop     (user answered -> silence)
#     PreToolUse / PostToolUse -> waiting-nag.sh stop  (Claude is working again)
#
# Has its OWN on/off switch (.waiting-nag-enabled), independent of the
# end-of-coding announcements toggle (claude-announce.sh). Turn the nagging off
# without affecting anything else:
#     waiting-nag.sh off | on | status
#
# Every wait is logged to .waiting-nag.log — what started it, what Claude
# said it was waiting FOR (the Notification hook's own message, read off stdin),
# each reminder as it is spoken, which voice actually came out, and what finally
# stopped it. `waiting-nag.sh log` tails it.
#
# Usage: waiting-nag.sh start [message] | stop | on | off | status | log [lines]
# Env:   CLAUDE_NAG_INTERVALS  finite schedule in seconds between spoken reminders
#                              (default "60 60 60 300 300 300" = three reminders ~1min
#                              apart, then three ~5min apart, then STOP — six nags total).
#                              When the schedule is exhausted the nagger exits (no more
#                              reminders until the next wait). Each new wait restarts it.
#        CLAUDE_NAG_INTERVAL   legacy: a single fixed interval for every reminder.
#        CLAUDE_NAG_LOG        where to write the log (default .waiting-nag.log)
#        CLAUDE_NAG_LOG_MAX    rotate once the log passes this many bytes (default 256k)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.waiting-nag.pid"
STATE_FILE="$SCRIPT_DIR/.waiting-nag-enabled"
START_FILE="$SCRIPT_DIR/.waiting-nag.started"
LOG_FILE="${CLAUDE_NAG_LOG:-$SCRIPT_DIR/.waiting-nag.log}"
LOG_MAX_BYTES="${CLAUDE_NAG_LOG_MAX:-262144}"
# "samuel" — the Piper en_US-ryan-medium model. NOT "ryan": announce.sh maps that to
# en_US-ryan-high.onnx, which may not be downloaded. A missing model silently degrades
# the whole thing to espeak — the tinny robot voice.
VOICE="samuel"
if [ -n "$CLAUDE_NAG_INTERVAL" ]; then
    NAG_INTERVALS="$CLAUDE_NAG_INTERVAL"
else
    NAG_INTERVALS="${CLAUDE_NAG_INTERVALS:-60 60 60 300 300 300}"
fi
DEFAULT_MSG="Travis here — still waiting on you."

is_off() { [ -f "$STATE_FILE" ] && [ "$(tr -d '[:space:]' < "$STATE_FILE")" = "off" ]; }

log() {
    local size=0
    [ -f "$LOG_FILE" ] && size="$(stat -c %s "$LOG_FILE" 2>/dev/null || echo 0)"
    [ "$size" -gt "$LOG_MAX_BYTES" ] && mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    printf '%s  %-5s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$$" "$*" >> "$LOG_FILE" 2>/dev/null
    return 0
}

logev() {
    local label="$1"; shift
    log "$(printf '%-7s' "$label")— $*"
}

waited_for() {
    local began now
    began="$(cat "$START_FILE" 2>/dev/null)" || return 0
    [ -n "$began" ] || return 0
    now="$(date +%s)"
    local secs=$(( now - began ))
    [ "$secs" -lt 0 ] && return 0
    if [ "$secs" -ge 60 ]; then printf 'after %dm%02ds' $(( secs / 60 )) $(( secs % 60 ))
    else printf 'after %ds' "$secs"; fi
}

# True only for a real detached nag loop: argv must look like
# "<bash> <...>/waiting-nag.sh _loop [msg]". Matching on /proc argv instead of a
# `pkill -f` pattern matters - a plain pattern also matches any shell whose own
# command line happens to mention "waiting-nag.sh _loop" (including the caller).
is_loop_proc() {
    local p="$1"
    local argv=()
    [ -r "/proc/$p/cmdline" ] || return 1
    mapfile -d '' -t argv < "/proc/$p/cmdline" 2>/dev/null || return 1
    [ "${argv[2]}" = "_loop" ] && [[ "${argv[1]}" == *waiting-nag.sh ]]
}

kill_loop() {
    local pid="$1"
    [ -n "$pid" ] || return 0
    kill -- -"$pid" 2>/dev/null   # whole process group (loop + its sleep + any in-flight announce)
    kill "$pid" 2>/dev/null
    return 0
}

stop_nag() {
    local reason="${1:-stop}"
    local killed=""
    if [ -f "$PID_FILE" ]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null)"
        if [ -n "$pid" ]; then
            kill_loop "$pid"
            killed="$pid"
        fi
        rm -f "$PID_FILE"
    fi
    local p
    for p in $(pgrep -f "waiting-nag\.sh _loop" 2>/dev/null); do
        [ "$p" = "$$" ] && continue
        if is_loop_proc "$p"; then
            kill_loop "$p"
            killed="${killed:+$killed,}$p (orphan)"
        fi
    done
    if [ -n "$killed" ]; then
        local waited
        waited="$(waited_for)"
        logev "$reason" "silenced nagger $killed ${waited:-(start time unknown)}"
    fi
    rm -f "$START_FILE"
    return 0
}

case "$1" in
    _loop)
        MSG="${2:-$DEFAULT_MSG}"
        echo $$ > "$PID_FILE"
        read -r -a intervals <<< "$NAG_INTERVALS"
        [ "${#intervals[@]}" -eq 0 ] && intervals=(60)
        spoken=0
        for cur in "${intervals[@]}"; do
            sleep "$cur"
            if is_off; then
                logev "off" "switched off mid-wait, $spoken reminder(s) spoken"
                break
            fi
            out="$("$SCRIPT_DIR/announce.sh" "$MSG" "$VOICE" 2>&1)"
            rc=$?
            spoken=$(( spoken + 1 ))
            heard="$(printf '%s' "$out" | sed -n 's/.*Announcing (\([^)]*\)).*/\1/p' | head -1)"
            w="$(waited_for)"
            if [ "$rc" -ne 0 ]; then
                logev "spoke" "reminder $spoken/${#intervals[@]} FAILED (announce.sh exit $rc)${w:+ $w}"
            elif [ -z "$heard" ]; then
                logev "spoke" "reminder $spoken/${#intervals[@]}, voice unknown${w:+ $w}"
            elif [ "$heard" = "$VOICE" ]; then
                logev "spoke" "reminder $spoken/${#intervals[@]}, voice $heard${w:+ $w}"
            else
                logev "spoke" "reminder $spoken/${#intervals[@]}, voice '$heard' NOT '$VOICE'${w:+ $w}"
            fi
        done
        if [ "$(cat "$PID_FILE" 2>/dev/null)" = "$$" ]; then
            w="$(waited_for)"
            logev "done" "schedule exhausted, $spoken reminder(s) spoken${w:+ $w} — silent until the next wait"
            rm -f "$PID_FILE" "$START_FILE"
        fi
        ;;
    start)
        WHY=""
        if [ ! -t 0 ]; then
            HOOK_JSON="$(timeout 0.3 cat 2>/dev/null | tr -d '\n' | head -c 2000)"
            WHY="$(printf '%s' "$HOOK_JSON" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
        fi
        if is_off; then
            logev "start" "IGNORED, reminders are switched off${WHY:+ (waiting for: $WHY)}"
            exit 0
        fi
        stop_nag "restart"
        MSG="${2:-$DEFAULT_MSG}"
        date +%s > "$START_FILE"
        logev "start" "waiting for: ${WHY:-<no reason given by the hook>}"
        logev "" "schedule ${NAG_INTERVALS// /s, }s; will say \"$MSG\""
        setsid "$SCRIPT_DIR/waiting-nag.sh" _loop "$MSG" </dev/null >/dev/null 2>&1 &
        for _ in $(seq 1 40); do
            [ -s "$PID_FILE" ] && break
            sleep 0.05
        done
        if [ -s "$PID_FILE" ]; then
            logev "" "nagger running (pid $(cat "$PID_FILE" 2>/dev/null))"
        else
            logev "" "WARNING: the nagger never published a pid, nothing will be spoken"
        fi
        ;;
    stop)
        stop_nag "stop"
        ;;
    on|enable)
        echo "on" > "$STATE_FILE"
        logev "toggle" "switched ON"
        echo "Waiting-for-you voice reminders: ON"
        ;;
    off|disable)
        echo "off" > "$STATE_FILE"
        stop_nag "off"
        logev "toggle" "switched OFF"
        echo "Waiting-for-you voice reminders: OFF"
        ;;
    status)
        if is_off; then echo "OFF"; else echo "ON"; fi
        nag_pid="$(cat "$PID_FILE" 2>/dev/null)"
        if [ -n "$nag_pid" ] && is_loop_proc "$nag_pid"; then
            echo "(currently nagging, pid $nag_pid $(waited_for))"
        fi
        echo "log: $LOG_FILE"
        ;;
    log)
        [ -f "$LOG_FILE" ] || { echo "No log yet: $LOG_FILE"; exit 0; }
        tail -n "${2:-40}" "$LOG_FILE"
        ;;
    *)
        echo "Usage: waiting-nag.sh start [message] | stop | on | off | status | log [lines]"
        exit 1
        ;;
esac
