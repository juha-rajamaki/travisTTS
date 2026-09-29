# TravisTTS

Travis is a voice announcement system for [Claude Code](https://claude.ai/code) sessions. It gives you a running audio commentary of what Claude is doing:

- **"On it."** — spoken the moment Claude starts working on your prompt
- **Announce** — speaks Claude's response summary automatically when a task finishes (Stop hook)
- **Nag** — repeats a reminder at set intervals while Claude is idle, waiting for your input

All speech uses [Piper TTS](https://github.com/rhasspy/piper) for natural-sounding offline audio, with automatic fallback to `espeak` or macOS `say`.

---

## Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/juha-rajamaki/travisTTS/main/install.sh)"
```

Works on macOS, Linux, and Windows (WSL or Git Bash). Re-running on an existing install just pulls the latest.

#### Manual install

```bash
mkdir -p ~/tools
git clone https://github.com/juha-rajamaki/travisTTS.git ~/tools/travisTTS
chmod +x ~/tools/travisTTS/*.sh ~/tools/travisTTS/travis
pip3 install --user piper-tts
mkdir -p ~/.local/share/piper/voices && cd ~/.local/share/piper/voices
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx
wget https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/ryan/high/en_US-ryan-high.onnx.json
```

---

## Claude Code wiring

Add these hooks to `~/.claude/settings.json` (global — works in every project automatically, no per-project setup needed):

```json
{
  "hooks": {
    "Notification": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh start" }] }
    ],
    "UserPromptSubmit": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh stop" },
        { "type": "command", "command": "$HOME/tools/travisTTS/start-work.sh arm" }
      ]}
    ],
    "PreToolUse": [
      { "matcher": "", "hooks": [
        { "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh stop" },
        { "type": "command", "command": "$HOME/tools/travisTTS/start-work.sh fire" }
      ]}
    ],
    "PostToolUse": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/tools/travisTTS/waiting-nag.sh stop" }] }
    ],
    "Stop": [
      { "matcher": "", "hooks": [{ "type": "command", "command": "$HOME/tools/travisTTS/stop-hook.sh" }] }
    ]
  }
}
```

### Optional: a different voice per subagent

Travis can speak a subagent's result in its own voice when that agent finishes, so you can tell by ear who is talking. Add a `SubagentStop` block next to the hooks above. `matcher` is a regex on the agent type, and the voice set in the command overrides any `travis.env`:

```json
"SubagentStop": [
  { "matcher": "^code-security-auditor$", "hooks": [{ "type": "command", "command": "TRAVIS_VOICE=alan $HOME/tools/travisTTS/stop-hook.sh" }] },
  { "matcher": "^Plan$",                  "hooks": [{ "type": "command", "command": "TRAVIS_VOICE=amy $HOME/tools/travisTTS/stop-hook.sh" }] }
]
```

Use any agent type (`Explore`, `general-purpose`, your own agents) and any installed voice. Agents with no matching entry stay silent. The travisTTS repo itself ships this setup in its `.claude/settings.json`.

---

## Per-project configuration

Drop a `travis.env` file in your project's `.claude/` directory to override settings for that project. Copy from the template:

```bash
cp ~/tools/travisTTS/travis.env.example <your-project>/.claude/travis.env
```

**Config priority (highest wins):**
1. Environment variables set in the shell (e.g. `TRAVIS_VOICE=amy ./some-script.sh`)
2. `<project>/.claude/travis.env` — per-project overrides
3. `~/.config/travis/travis.env` — your global defaults

**Available settings:**

```bash
# Which features are active (on|off)
TRAVIS_STOP_HOOK=on       # Speak Claude's last message when a task finishes
TRAVIS_START_WORK=on      # Say "On it." when Claude starts working
TRAVIS_NAG=on             # Repeat reminders while Claude is idle
TRAVIS_ANNOUNCE=on        # Manual claude-announce.sh calls

# Voice: ryan (default) | amy | alan | jenny | kristin
TRAVIS_VOICE=ryan

# How many characters of the Stop hook message to speak
TRAVIS_STOP_MAX_CHARS=300

# Nag schedule: space-separated seconds between reminders
CLAUDE_NAG_INTERVALS="60 60 60 300 300 300"
```

---

## Voice reference

Run `voicemodels.sh` to hear each voice before choosing:

```bash
~/tools/travisTTS/voicemodels.sh
```

| # | Name | Model file | Description |
|---|------|-----------|-------------|
| 1 | **ryan** | `en_US-ryan-high.onnx` | US English male — Default |
| 2 | amy | `en_US-amy-medium.onnx` | US English female |
| 3 | alan | `en_GB-alan-medium.onnx` | UK English male |
| 4 | jenny | `en_GB-jenny_dioco-medium.onnx` | UK English female |
| 5 | kristin | `en_US-kristin-medium.onnx` | US English female |

Set your preferred voice in `~/.config/travis/travis.env` or per-project in `.claude/travis.env`.

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
| `SubagentStop` (`code-security-auditor`) | `TRAVIS_VOICE=alan stop-hook.sh` | Speaks the security audit result in **alan's** voice, so security findings stand out from ryan (this repo's `.claude/settings.json`) |
| `SubagentStop` (`Plan`) | `TRAVIS_VOICE=amy stop-hook.sh` | Speaks the plan summary in **amy's** voice when a Plan agent finishes (this repo's `.claude/settings.json`) |

---

## Script reference

### `testvoice.sh [single|multi]`
Checks that each role is spoken in the right voice by running the real hooks from `.claude/settings.json` with simulated hook events. Each clip also says which voice should be speaking, so you can confirm by ear. With no argument it detects the mode from the settings.
- `single` — every role (planning, coding, security) is spoken by the Stop hook in the default voice (ryan)
- `multi` — planning → amy, coding → ryan, security → alan

Exits non-zero if any role is spoken in the wrong voice or has no hook.

### `voicemodels.sh`
Plays a sample sentence in each installed voice. Run once to pick your preferred voice.

### `travis [voice_number] "message"`
Speaks a message. Voice number: 1=ryan, 2=amy, 3=alan, 4=jenny, 5=kristin.

### `announce.sh "message" [voice]`
Low-level wrapper: speaker lock (no overlapping audio), tmp WAV, full fallback chain (Piper → espeak → say). Used internally by all other scripts.

### `stop-hook.sh`
Wired as the `Stop` hook. Reads `last_assistant_message` from hook JSON, strips markdown, trims to `TRAVIS_STOP_MAX_CHARS` chars (default 300), speaks it. Falls back to "Done." if message is empty. Disable with `TRAVIS_STOP_HOOK=off` in travis.env.

### `start-work.sh arm | fire | status`
"On it." announcer. `arm` on `UserPromptSubmit`, `fire` on `PreToolUse` — speaks once then disarms. Disable with `TRAVIS_START_WORK=off`.

### `claude-announce.sh "message" | on | off | status`
Manual announcer. Speaks immediately and schedules two nag repeats (60 s and 180 s). The Stop hook covers this automatically — use for manual overrides. Disable with `TRAVIS_ANNOUNCE=off`.

### `waiting-nag.sh start [msg] | stop | on | off | status | log [n]`
Idle nagger. Starts a detached loop that speaks on a configurable schedule. Disable with `TRAVIS_NAG=off`.

```bash
~/tools/travisTTS/waiting-nag.sh status
~/tools/travisTTS/waiting-nag.sh log        # tail the nag log
export CLAUDE_NAG_INTERVALS="60 60 300"     # custom schedule (3 nags then stop)
```

Default schedule: `"60 60 60 300 300 300"` — six nags, first three ~1 min apart, last three ~5 min apart.

---

## On/off switches

| Feature | travis.env variable | Default |
|---------|-------------------|---------|
| Stop hook announcement | `TRAVIS_STOP_HOOK=off` | on |
| "On it." start announcement | `TRAVIS_START_WORK=off` | on |
| Idle nagger | `TRAVIS_NAG=off` | on |
| Manual announce | `TRAVIS_ANNOUNCE=off` | on |
