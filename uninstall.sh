#!/bin/sh
# Removes discord-heartbeat from macOS: unloads the LaunchAgent and deletes
# ~/.discord-heartbeat (including the token file and logs).
set -e

LABEL="com.discord.heartbeat"
DIR="$HOME/.discord-heartbeat"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$DIR"

echo "Uninstalled. No traces left."
