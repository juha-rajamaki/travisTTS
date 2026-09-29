# TravisTTS

Travis is a voice announcement system for [Claude Code](https://claude.ai/code) sessions. It gives you a running audio commentary of what Claude is doing:

- **"On it."** — spoken the moment Claude starts working on your prompt
- **Announce** — speaks Claude's actual response summary when a task finishes (extracted from the Stop hook JSON automatically — no CLAUDE.md instruction needed)
- **Nag** — repeats a reminder at set intervals while Claude is idle, waiting for your input ("Travis here — still waiting on you.")

All speech uses [Piper TTS](https://github.com/rhasspy/piper) for natural-sounding offline audio, with automatic fallback to `espeak` or macOS `say`.

---

## Installation

Run the one-liner — it clones the repo, installs Piper TTS, and downloads the default voice model:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/juha-rajamaki/travisTTS/main/install.sh)"
```

Works on macOS, Linux, and Windows (WSL or Git Bash). Re-running on an existing install just pulls the latest.

#### Manual install

```bash
mkdir -p ~/tools
git clone https://github.com/juha-rajamaki/travisTTS.git ~/tools/travisTTS
chmod +x ~/tools/travisTTS/*.sh ~/tools/travisTTS/travis
# Then install piper and voices manually (see Prerequisites below)
```

#### Prerequisites (manual installs only)

1. **Piper TTS**
   ```bash
   pip3 install --user piper-tts
   ```

2. **Default voice model** (ryan-medium):
   ```bash
   mkdir -p ~/.local/share/piper/voices
   cd ~/.local/share/piper/voices
   wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en_US/en_US-ryan-medium/en_US-ryan-medium.onnx
   wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en_US/en_US-ryan-medium/en_US-ryan-medium.onnx.json
   ```

---

## Claude Code wiring

Add these hooks to `~/.claude/settings.json` (global — works in every project automatically):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh start" }]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh stop" },
          { "type": "command", "command": "$HOME/tools/travisTTS/start-work.sh arm" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh stop" },
          { "type": "command", "command": "$HOME/tools/travisTTS/start-work.sh fire" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh stop" }]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "$HOME/tools/travisTTS/stop-hook.sh" }]
      }
    ]
  }
}
```

No `CLAUDE.md` instruction needed — the `Stop` hook reads Claude's last message directly and speaks it automatically.

---

## Hook behaviour

| Hook | Script | What happens |
|------|--------|-------------|
| `UserPromptSubmit` | `waiting-nag.sh stop` + `start-work.sh arm` | Silence nagger; arm the "On it." trigger |
| `PreToolUse` (first) | `start-work.sh fire` | Says **"On it."** once, then disarms |
| `PreToolUse` (rest) | `waiting-nag.sh stop` | Keeps nagger silenced while Claude works |
| `PostToolUse` | `waiting-nag.sh stop` | Keeps nagger silenced |
| `Notification` | `waiting-nag.sh start` | Starts the idle nagger (Claude waiting for you) |
| `Stop` | `stop-hook.sh` | Extracts `last_assistant_message` and speaks it |

---

## Voice reference

Travis uses Piper voices stored in `~/.local/share/piper/voices/`.

| # | Name | Model file | Description |
|---|------|-----------|-------------|
| 1 | **ryan** | `en_US-ryan-medium.onnx` | US English male — Default |
| 2 | amy | `en_US-amy-medium.onnx` | US English female |
| 3 | lessac | `en_US-lessac-medium.onnx` | US English female, natural |
| 4 | alan | `en_GB-alan-medium.onnx` | UK English male |

> `samuel` is kept as a back-compat alias for `ryan`.

```bash
~/tools/travisTTS/travis "Hello."          # default voice (ryan)
~/tools/travisTTS/travis 2 "Hello."        # amy
~/tools/travisTTS/travis 4 "Hello."        # alan
~/tools/travisTTS/announce.sh "Hello" lessac
```

---

## Script reference

### `travis [voice_number] "message"`
Speaks a message. Falls back to `say` (macOS) if Piper isn't available.

### `announce.sh "message" [voice]`
Low-level wrapper: speaker lock (no overlapping audio), tmp WAV, full fallback chain (Piper → espeak → say). Used internally by all other scripts.

### `stop-hook.sh`
Wired as the `Stop` hook. Reads `last_assistant_message` from the hook JSON on stdin, strips markdown, trims to `TRAVIS_STOP_MAX_CHARS` characters (default 300), and speaks it. Falls back to "Done." if the message is empty.

```bash
export TRAVIS_STOP_MAX_CHARS=150   # speak shorter summaries
```

### `start-work.sh arm | fire | on | off | status`
"On it." announcer. `arm` is called on `UserPromptSubmit`; `fire` is called on `PreToolUse` — it speaks once then disarms itself.

```bash
~/tools/travisTTS/start-work.sh off     # disable "On it." announcements
~/tools/travisTTS/start-work.sh on
~/tools/travisTTS/start-work.sh status
```

### `claude-announce.sh "message" | on | off | status`
Manual end-of-coding announcer (fallback / override). Speaks the message immediately and schedules two nag repeats (60 s and 180 s). The `Stop` hook covers this automatically now, but you can still call it directly.

```bash
~/tools/travisTTS/claude-announce.sh "Refactoring done, tests pass."
~/tools/travisTTS/claude-announce.sh off
~/tools/travisTTS/claude-announce.sh status
```

### `waiting-nag.sh start [message] | stop | on | off | status | log [lines]`
Idle nagger. Starts a detached loop that speaks on a configurable interval schedule.

```bash
~/tools/travisTTS/waiting-nag.sh status
~/tools/travisTTS/waiting-nag.sh log        # tail the nag log
~/tools/travisTTS/waiting-nag.sh off        # disable nagger
export CLAUDE_NAG_INTERVALS="60 60 300"     # custom schedule
```

Default schedule: `"60 60 60 300 300 300"` — six nags, first three ~1 min apart, last three ~5 min apart, then stops.

---

## On/off switches

Travis has three independent on/off switches:

| Switch | Controls | Command |
|--------|----------|---------|
| `stop-hook.sh` | Automatic Stop announcements | `TRAVIS_STOP_MAX_CHARS=0` or disable the hook |
| `start-work.sh` | "On it." on task start | `start-work.sh on/off/status` |
| `claude-announce.sh` | Manual end-of-coding announcements | `claude-announce.sh on/off/status` |
| `waiting-nag.sh` | Idle nag reminders | `waiting-nag.sh on/off/status` |
