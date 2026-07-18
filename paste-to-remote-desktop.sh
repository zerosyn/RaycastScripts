#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Paste to Remote Desktop
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Remote Desktop Utils

script_dir="$(cd "$(dirname "$0")" && pwd)"
"$script_dir/paste-to-remote-desktop"
