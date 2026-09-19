#!/bin/sh
# Installs discord-heartbeat on macOS: copies the script into
# ~/.discord-heartbeat and registers a LaunchAgent that starts it at login
# and keeps it alive.
#
# Usage:
#   ./install.sh                 # single machine (no sharding)
#   ./install.sh 0 2             # multi-machine: this is shard 0 of 2
#   ./install.sh 1 2             # multi-machine: this is shard 1 of 2
set -e

SHARD_ID="${1:-0}"
SHARD_COUNT="${2:-1}"

DIR="$HOME/.discord-heartbeat"
PLIST="$HOME/Library/LaunchAgents/com.discord.heartbeat.plist"
LABEL="com.discord.heartbeat"

mkdir -p "$DIR"
cp "$(dirname "$0")/heartbeat.py" "$DIR/heartbeat.py"
chmod 644 "$DIR/heartbeat.py"

ENV_BLOCK=""
if [ "$SHARD_COUNT" -gt 1 ]; then
  ENV_BLOCK="    <key>EnvironmentVariables</key>
    <dict>
        <key>HEARTBEAT_SHARD_ID</key>
        <string>$SHARD_ID</string>
        <key>HEARTBEAT_SHARD_COUNT</key>
        <string>$SHARD_COUNT</string>
    </dict>"
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$DIR/heartbeat.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
$ENV_BLOCK
    <key>StandardOutPath</key>
    <string>$DIR/keeper.out.log</string>
    <key>StandardErrorPath</key>
    <string>$DIR/keeper.err.log</string>
</dict>
</plist>
EOF

# Python dependency
if ! python3 -c "import websockets" 2>/dev/null; then
  echo "Installing the 'websockets' package..."
  python3 -m pip install --user websockets
fi

# (Re)load the agent
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart "gui/$(id -u)/$LABEL"

echo ""
echo "Installed. The heartbeat starts at every login."
echo "Next: put your bot token in $DIR/token"
echo "  printf '%s' 'YOUR_BOT_TOKEN' > \"$DIR/token\" && chmod 600 \"$DIR/token\""
echo "It picks the token up automatically within a minute."
