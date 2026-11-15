#!/bin/bash
# start-work.sh — retired. Travis no longer announces when Claude starts working.
# Kept as a silent no-op so existing installs whose hooks still call it keep working;
# remove the start-work.sh hooks from your Claude Code settings at any time.
rm -f "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.start-work-armed"
exit 0
