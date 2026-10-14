#!/usr/bin/env bash
# Installs the bridge as a LaunchAgent, creates a token, and copies it to the clipboard.
set -euo pipefail

readonly LABEL="com.nirwo.bariatric-bridge"
readonly PORT=8787
readonly BRIDGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_DIR="$HOME/.config/bariatric-bridge"
readonly TOKEN_FILE="$CONFIG_DIR/token"
readonly PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
readonly LOG_FILE="$HOME/Library/Logs/bariatric-bridge.log"

CLAUDE_BIN="$(command -v claude || true)"
PYTHON_BIN="$(command -v python3 || true)"
[[ -n "$CLAUDE_BIN" ]] || { echo "error: claude CLI not found in PATH" >&2; exit 1; }
[[ -n "$PYTHON_BIN" ]] || { echo "error: python3 not found in PATH" >&2; exit 1; }

mkdir -p "$CONFIG_DIR" "$(dirname "$PLIST")" "$(dirname "$LOG_FILE")"
chmod 700 "$CONFIG_DIR"
if [[ ! -s "$TOKEN_FILE" ]]; then
  (umask 077 && "$PYTHON_BIN" -c 'import secrets; print(secrets.token_urlsafe(32))' > "$TOKEN_FILE")
fi

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PYTHON_BIN</string>
    <string>$BRIDGE_DIR/server.py</string>
    <string>--port</string><string>$PORT</string>
    <string>--token-file</string><string>$TOKEN_FILE</string>
    <string>--claude</string><string>$CLAUDE_BIN</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>$(dirname "$CLAUDE_BIN"):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG_FILE</string>
  <key>StandardErrorPath</key><string>$LOG_FILE</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

TAILSCALE_BIN="$(command -v tailscale || true)"
[[ -z "$TAILSCALE_BIN" && -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]] \
  && TAILSCALE_BIN=/Applications/Tailscale.app/Contents/MacOS/Tailscale
HOST=""
if [[ -n "$TAILSCALE_BIN" ]]; then
  HOST="$("$TAILSCALE_BIN" status --json 2>/dev/null \
    | "$PYTHON_BIN" -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
fi
[[ -n "$HOST" ]] || HOST="$(ipconfig getifaddr en0 || echo '<mac-ip>')"

pbcopy < "$TOKEN_FILE"
echo "Bridge running (log: $LOG_FILE)"
echo "Address for the app: http://$HOST:$PORT"
echo "Token copied to the clipboard — paste it on the iPhone (Universal Clipboard)."
