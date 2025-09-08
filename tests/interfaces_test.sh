#!/usr/bin/env bash
set -e
source "$(dirname "$0")/../best403unlocker-tui.sh"
interfaces=$(get_available_interfaces)
if [[ -z "$interfaces" ]]; then
    echo "No interfaces detected"
else
    echo "Detected interfaces: $interfaces"
fi
