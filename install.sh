#!/bin/bash
# Travis TTS — one-shot installer
# Clones the repo to ~/tools/travisTTS and makes all scripts executable.
# Run this once on any machine you want Travis on.

set -e

INSTALL_DIR="$HOME/tools/travisTTS"
REPO="git@github.com:juha-rajamaki/travisTTS.git"

if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Travis is already installed at $INSTALL_DIR"
    echo "To update: cd $INSTALL_DIR && git pull"
    exit 0
fi

echo "Installing Travis to $INSTALL_DIR ..."
mkdir -p "$HOME/tools"
git clone "$REPO" "$INSTALL_DIR"
chmod +x "$INSTALL_DIR/travis" "$INSTALL_DIR/announce.sh" "$INSTALL_DIR/claude-announce.sh" \
         "$INSTALL_DIR/waiting-nag.sh" "$INSTALL_DIR/kill-nags.sh" "$INSTALL_DIR/install.sh"

echo ""
echo "Done. Travis installed at $INSTALL_DIR"
echo ""
echo "Quick test:"
echo "  $INSTALL_DIR/travis \"Hello from Travis\""
echo ""
echo "Wire up Claude Code hooks — add this to .claude/settings.json:"
echo '  "hooks": {'
echo '    "Notification":       [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh start" }] }],'
echo '    "UserPromptSubmit":   [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh stop" }] }],'
echo '    "PreToolUse":         [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh stop" }] }],'
echo '    "PostToolUse":        [{ "matcher": "", "hooks": [{ "type": "command", "command": "'"$INSTALL_DIR"'/waiting-nag.sh stop" }] }]'
echo '  }'
