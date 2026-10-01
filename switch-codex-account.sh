#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Switch Codex Account
# @raycast.mode compact
# @raycast.icon 🔄
# @raycast.packageName Codex
# @raycast.argument1 {"type": "dropdown", "placeholder": "选择账号", "data": [{"title": "cpa", "value": "cpa"}, {"title": "origin", "value": "origin"}, {"title": "sub", "value": "sub"}]}

export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$PATH"
script_dir="$(cd "$(dirname "$0")" && pwd)"
exec uv run --quiet --script "$script_dir/codex-account.py" switch "$1"
