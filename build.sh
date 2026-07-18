#!/bin/bash
set -e

output_dir="$HOME/Documents/Raycast"
mkdir -p "$output_dir"
swiftc -O toggle-chrome-sidebar.swift -o "$output_dir/toggle-chrome-sidebar"
swiftc -O RemoteTypingCore.swift paste-to-remote-desktop.swift -o "$output_dir/paste-to-remote-desktop"
swiftc -O univpn-toggle.swift -o "$output_dir/univpn-toggle"
