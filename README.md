# TravisTTS

Travis is a voice announcement system for [Claude Code](https://claude.ai/code) sessions. It does two things:

- **Announce** — speaks a short summary out loud when a Claude coding task finishes ("Navigation buttons refactored, tests pass.")
- **Nag** — repeats a reminder at set intervals while Claude is idle, waiting for your input ("Travis here — still waiting on you.")

Both use [Piper TTS](https://github.com/rhasspy/piper) for natural-sounding offline speech, with automatic fallback to `espeak` or macOS `say` if Piper isn't available.

---

## Installation

### Prerequisites

1. **Piper TTS** — download the binary and at least the `samuel` voice model:

   ```bash
   # macOS (pip install into user Python)
   pip3 install --user piper-tts

   # Linux
   # Download the piper binary from https://github.com/rhasspy/piper/releases
   # and put it somewhere on your PATH (e.g. ~/.local/bin/piper)
   ```

### Install (all platforms)

Run the one-liner — it clones the repo, installs Piper TTS, and downloads the default voice model automatically:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/juha-rajamaki/travisTTS/main/install.sh)"
```

Works on macOS, Linux, and Windows (WSL or Git Bash). Re-running it on an existing install just pulls the latest changes.

#### Manual install

```bash
mkdir -p ~/tools
git clone https://github.com/juha-rajamaki/travisTTS.git ~/tools/travisTTS
chmod +x ~/tools/travisTTS/*.sh ~/tools/travisTTS/travis
# Then install piper and voices manually (see Prerequisites below)
```

#### Prerequisites (only needed for manual installs)

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

## Voice reference

Travis uses Piper voices stored in `~/.local/share/piper/voices/`.

| # | Name | Model file | Description |
|---|------|-----------|-------------|
| 1 | **ryan** | `en_US-ryan-medium.onnx` | US English male — Default. **Used by all Claude Code hooks.** |
| 2 | amy | `en_US-amy-medium.onnx` | US English female |
| 3 | lessac | `en_US-lessac-medium.onnx` | US English female, natural |
| 4 | alan | `en_GB-alan-medium.onnx` | UK English male |

> `samuel` is kept as an alias for `ryan` for back-compatibility with older installs.

### Usage examples

```bash
# Default voice (samuel / voice 1)
~/tools/travisTTS/travis "Hello, I finished the task."

# Specific voice by number
~/tools/travisTTS/travis 2 "Hello in amy's voice."
~/tools/travisTTS/travis 4 "Hello in alan's voice."

# Specific voice by name (via announce.sh)
~/tools/travisTTS/announce.sh "Hello" ryan
~/tools/travisTTS/announce.sh "Hello" lessac
```

---

## Claude Code wiring

Add these hooks to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/tools/travisTTS/waiting-nag.sh start"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/tools/travisTTS/waiting-nag.sh stop"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/tools/travisTTS/waiting-nag.sh stop"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/tools/travisTTS/waiting-nag.sh stop"
          }
        ]
      }
    ]
  }
}
```

Then add this line to your project's `CLAUDE.md` (inside the instructions Claude reads for every session):

```
At the end of every coding task, run: ~/tools/travisTTS/claude-announce.sh "<one or two sentence summary of what was done>"
```

---

## Per-project quick-start

Three steps to add Travis to any project:

1. **Install Travis once** (if not already installed):
   ```bash
   git clone git@github.com:juha-rajamaki/travisTTS.git ~/tools/travisTTS
   chmod +x ~/tools/travisTTS/*.sh ~/tools/travisTTS/travis
   ```

2. **Add hooks** to `.claude/settings.json` (copy the block from the Claude Code wiring section above).

3. **Tell Claude** in your `CLAUDE.md`:
   ```
   At the end of every coding task, run:
   ~/tools/travisTTS/claude-announce.sh "<short spoken summary>"
   ```

That's it. The next Claude Code session will start nagging when idle and announce when done.

---

## Usage reference

### `travis [voice_number] "message"`

Speaks a message using Piper. Falls back to `say` (macOS) if Piper isn't available.

```bash
~/tools/travisTTS/travis "Deploy complete."
~/tools/travisTTS/travis 2 "Deploy complete."   # voice 2 = amy
```

### `announce.sh "message" [voice]`

Lower-level wrapper: uses a speaker lock (so announcements never overlap), unique WAV tmpfiles, and the full fallback chain (Piper → espeak → say → silent). Used internally by `waiting-nag.sh`.

```bash
~/tools/travisTTS/announce.sh "Task complete." ryan
~/tools/travisTTS/announce.sh "Task complete." amy
```

### `claude-announce.sh "message" | on | off | status`

End-of-coding announcer. Speaks the message immediately, then schedules two reminder nags (at 60 s and 180 s) that only fire if Claude is still idle.

```bash
~/tools/travisTTS/claude-announce.sh "Refactoring done, tests pass."
~/tools/travisTTS/claude-announce.sh off     # disable announcements
~/tools/travisTTS/claude-announce.sh on      # re-enable
~/tools/travisTTS/claude-announce.sh status  # print ON / OFF
```

State is stored in `.claude-announce-enabled` next to the script.

### `waiting-nag.sh start [message] | stop | on | off | status | log [lines]`

Repeating idle nagger. Starts a detached loop that speaks at the configured interval schedule until stopped.

```bash
~/tools/travisTTS/waiting-nag.sh start              # start with default message
~/tools/travisTTS/waiting-nag.sh start "Come back!" # custom message
~/tools/travisTTS/waiting-nag.sh stop               # silence it
~/tools/travisTTS/waiting-nag.sh status             # ON/OFF + running pid
~/tools/travisTTS/waiting-nag.sh log                # tail the nag log
~/tools/travisTTS/waiting-nag.sh off                # disable permanently
~/tools/travisTTS/waiting-nag.sh on                 # re-enable
```

**Interval schedule** — set `CLAUDE_NAG_INTERVALS` (space-separated seconds):

```bash
export CLAUDE_NAG_INTERVALS="60 60 300"   # 3 nags: 1min, 1min, 5min, then stop
```

Default: `"60 60 60 300 300 300"` — six nags total, first three ~1 min apart, last three ~5 min apart.

---

## Enabling / disabling

Travis has two independent on/off switches:

| Switch | Controls | Command |
|--------|----------|---------|
| `claude-announce.sh` | End-of-coding announcements only | `claude-announce.sh on/off/status` |
| `waiting-nag.sh` | Idle nag reminders only | `waiting-nag.sh on/off/status` |

Turning one off does not affect the other.
