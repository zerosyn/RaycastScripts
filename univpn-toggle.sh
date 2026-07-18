#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title UniVPN Toggle
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🔒
# @raycast.packageName VPN
# @raycast.description Toggle UniVPN and verify the resulting connection state

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "$script_dir/univpn-toggle"
