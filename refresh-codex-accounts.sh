#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Refresh Codex Accounts
# @raycast.mode compact
# @raycast.icon 🔄
# @raycast.packageName Codex

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
script_dir="$(cd "$(dirname "$0")" && pwd)"
exec uv run --quiet --script "$script_dir/codex-account.py" refresh
