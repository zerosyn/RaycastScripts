#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Chrome Sidebar
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📑
# @raycast.packageName Chrome Utils

script_dir="$(cd "$(dirname "$0")" && pwd)"
"$script_dir/toggle-chrome-sidebar"
