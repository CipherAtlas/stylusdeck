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
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST_PATH="$CONTENTS_DIR/Info.plist"
LAUNCHER_PATH="$MACOS_DIR/$APP_NAME"
ICON_SOURCE="$REPO_ROOT/assets/brand/stylusdeck-mark.png"
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

if [[ -f "$ICON_SOURCE" ]]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  make_icon() {
    local size="$1"
    local name="$2"
    /usr/bin/sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$name" >/dev/null
  }

  make_icon 16 icon_16x16.png
  make_icon 32 icon_16x16@2x.png
  make_icon 32 icon_32x32.png
  make_icon 64 icon_32x32@2x.png
  make_icon 128 icon_128x128.png
  make_icon 256 icon_128x128@2x.png
  make_icon 256 icon_256x256.png
  make_icon 512 icon_256x256@2x.png
  make_icon 512 icon_512x512.png
  make_icon 1024 icon_512x512@2x.png

  /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
  rm -rf "$ICONSET_DIR"
fi

/usr/bin/touch "$APP_DIR"
printf "%s\n" "$APP_DIR"
