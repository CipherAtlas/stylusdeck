#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT_ESCAPED="${REPO_ROOT//\\/\\\\}"
REPO_ROOT_ESCAPED="${REPO_ROOT_ESCAPED//\"/\\\"}"
REPO_ROOT_SHELL_ESCAPED="$(printf "%q" "$REPO_ROOT")"
APP_NAME="StylusDeck"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
LAUNCHER_PATH="$MACOS_DIR/$APP_NAME"

mkdir -p "$MACOS_DIR"

cat >"$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.stylusdeck.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

cat >"$LAUNCHER_PATH" <<EOF
#!/bin/bash
set -euo pipefail

REPO_ROOT="$REPO_ROOT_ESCAPED"
BINARY="\$REPO_ROOT/.build/debug/StylusDeck"

has_blackhole_device() {
  /usr/sbin/system_profiler SPAudioDataType 2>/dev/null | /usr/bin/grep -q "BlackHole 2ch"
}

launch_setup_in_terminal() {
  /usr/bin/osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "cd $REPO_ROOT_SHELL_ESCAPED && ./start.sh"
end tell
APPLESCRIPT
}

if [[ ! -d "\$REPO_ROOT" ]]; then
  /usr/bin/osascript -e 'display dialog "StylusDeck could not find its repo folder. Re-run ./start.sh from the repo to refresh the local app." buttons {"OK"} default button "OK" with icon stop'
  exit 1
fi

if [[ ! -x "\$BINARY" ]] || ! has_blackhole_device; then
  launch_setup_in_terminal
  exit 0
fi

cd "\$REPO_ROOT"
exec "\$BINARY"
EOF

chmod +x "$LAUNCHER_PATH"

/usr/bin/touch "$APP_DIR"
printf "%s\n" "$APP_DIR"
