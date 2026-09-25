#!/usr/bin/env bash
# Travis TTS — full installer
# Installs the repo, Piper TTS, and the default voice model.
# Supports macOS, Linux, and Windows (WSL or Git Bash).
#
# One-liner:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/juha-rajamaki/travisTTS/main/install.sh)"

set -e

INSTALL_DIR="$HOME/tools/travisTTS"
REPO="https://github.com/juha-rajamaki/travisTTS.git"
VOICE_DIR="$HOME/.local/share/piper/voices"
VOICE_MODEL_BASE="en_US-ryan-medium"
HF_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/en_US/en_US-ryan-medium"

# ── Helpers ──────────────────────────────────────────────────────────────────

say_step() { echo ""; echo "==> $*"; }
say_ok()   { echo "    ✓ $*"; }
say_info() { echo "    • $*"; }
say_warn() { echo "    ! $*"; }

need() {
    command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required but not found. $2"; exit 1; }
}

download() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fSL --progress-bar "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress "$url" -O "$dest"
    else
        echo "ERROR: neither curl nor wget found — cannot download files."
        exit 1
    fi
}

detect_os() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux)
            # Detect WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# ── Detect OS ────────────────────────────────────────────────────────────────

OS="$(detect_os)"
say_step "Detected OS: $OS"

# ── Step 1: Clone / update the repo ──────────────────────────────────────────

say_step "Installing Travis to $INSTALL_DIR"

if [ -d "$INSTALL_DIR/.git" ]; then
    say_info "Already installed — pulling latest changes..."
    git -C "$INSTALL_DIR" pull --ff-only
else
    need git "Install git first: https://git-scm.com/"
    mkdir -p "$HOME/tools"
    git clone "$REPO" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/travis" "$INSTALL_DIR/"*.sh
say_ok "Repo ready at $INSTALL_DIR"

# ── Step 2: Install Piper TTS ─────────────────────────────────────────────────

say_step "Installing Piper TTS"

install_piper_pip() {
    if command -v piper >/dev/null 2>&1; then
        say_ok "piper already on PATH"
        return 0
    fi
    need python3 "Install Python 3: https://www.python.org/downloads/"
    say_info "Running: pip3 install --user piper-tts"
    pip3 install --user piper-tts
    # Make sure the user bin dir is on PATH for this session
    local user_bin
    user_bin="$(python3 -m site --user-base 2>/dev/null)/bin"
    export PATH="$user_bin:$PATH"
    if command -v piper >/dev/null 2>&1; then
        say_ok "piper installed via pip"
    else
        say_warn "piper installed but not on PATH yet."
        say_warn "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
        echo ""
        echo "    export PATH=\"$user_bin:\$PATH\""
        echo ""
    fi
}

install_piper_linux_binary() {
    if command -v piper >/dev/null 2>&1; then
        say_ok "piper already on PATH"
        return 0
    fi
    say_info "Downloading Piper binary for Linux..."
    local arch
    arch="$(uname -m)"
    local asset
    case "$arch" in
        x86_64)  asset="piper_linux_x86_64.tar.gz" ;;
        aarch64) asset="piper_linux_aarch64.tar.gz" ;;
        armv7l)  asset="piper_linux_armv7l.tar.gz" ;;
        *)
            say_warn "Unsupported architecture: $arch. Falling back to pip."
            install_piper_pip
            return
            ;;
    esac
    local latest_url="https://api.github.com/repos/rhasspy/piper/releases/latest"
    local dl_url
    dl_url="$(curl -fsSL "$latest_url" | grep "browser_download_url.*$asset" | head -1 | cut -d'"' -f4)"
    if [ -z "$dl_url" ]; then
        say_warn "Could not fetch latest Piper release URL. Falling back to pip."
        install_piper_pip
        return
    fi
    local tmp_tar
    tmp_tar="$(mktemp /tmp/piper_XXXXXX.tar.gz)"
    download "$dl_url" "$tmp_tar"
    mkdir -p "$HOME/.local/bin"
    tar -xzf "$tmp_tar" -C "$HOME/.local/bin" --strip-components=1 piper/piper 2>/dev/null || \
        tar -xzf "$tmp_tar" -C "$HOME/.local/bin" piper 2>/dev/null
    rm -f "$tmp_tar"
    chmod +x "$HOME/.local/bin/piper"
    export PATH="$HOME/.local/bin:$PATH"
    say_ok "piper binary installed at $HOME/.local/bin/piper"
}

case "$OS" in
    macos)
        install_piper_pip
        ;;
    linux|wsl)
        # Try pip first (simpler), fall back to binary
        if command -v pip3 >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
            install_piper_pip
        else
            install_piper_linux_binary
        fi
        ;;
    windows)
        # Git Bash / MSYS — pip is the only viable option
        say_info "Windows detected. Using pip to install piper-tts."
        install_piper_pip
        ;;
    *)
        say_warn "Unknown OS — attempting pip install."
        install_piper_pip
        ;;
esac

# ── Step 3: Download voice model ──────────────────────────────────────────────

say_step "Downloading default voice model (en_US-ryan-medium)"

mkdir -p "$VOICE_DIR"

RYAN_ONNX="$VOICE_DIR/${VOICE_MODEL_BASE}.onnx"
RYAN_JSON="$VOICE_DIR/${VOICE_MODEL_BASE}.onnx.json"

model_ok() {
    local f="$1"
    [ -f "$f" ] && \
        [ "$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)" -gt 1000000 ]
}

if model_ok "$RYAN_ONNX" && [ -f "$RYAN_JSON" ]; then
    say_ok "Voice model already present ($VOICE_MODEL_BASE)"
else
    say_info "Downloading from Hugging Face..."
    download "$HF_BASE/${VOICE_MODEL_BASE}.onnx"      "$RYAN_ONNX"
    download "$HF_BASE/${VOICE_MODEL_BASE}.onnx.json" "$RYAN_JSON"
    say_ok "Voice model downloaded to $VOICE_DIR"
fi

# Keep samuel.onnx as an alias for back-compat with older installs
if [ ! -f "$VOICE_DIR/samuel.onnx" ]; then
    ln -sf "$RYAN_ONNX"      "$VOICE_DIR/samuel.onnx"      2>/dev/null || \
        cp "$RYAN_ONNX"      "$VOICE_DIR/samuel.onnx"
    ln -sf "$RYAN_JSON"      "$VOICE_DIR/samuel.onnx.json"  2>/dev/null || \
        cp "$RYAN_JSON"      "$VOICE_DIR/samuel.onnx.json"
    say_info "samuel.onnx → symlinked as alias for ryan-medium"
fi

# ── Step 4: Smoke test ────────────────────────────────────────────────────────

say_step "Running smoke test"

if "$INSTALL_DIR/travis" "Travis installed successfully." 2>/dev/null; then
    say_ok "Voice announcement works"
else
    say_warn "Smoke test failed — Travis may still work with the say/espeak fallback."
fi

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Travis is installed at: $INSTALL_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo ""
echo "  1. Wire up Claude Code hooks — add to .claude/settings.json:"
echo ""
echo '     "hooks": {'
echo '       "Notification":     [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh start" }] }],'
echo '       "UserPromptSubmit": [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh stop" }] }],'
echo '       "PreToolUse":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh stop" }] }],'
echo '       "PostToolUse":      [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh stop" }] }]'
echo '     }'
echo ""
echo "  2. Add to your CLAUDE.md:"
echo ""
echo '     At the end of every coding task, run:'
echo '     ~/tools/travisTTS/claude-announce.sh "<one or two sentence summary>"'
echo ""
