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
ICON_BASE="$RESOURCES_DIR/AppIconBase.png"

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

  python3 - "$ICON_SOURCE" "$ICON_BASE" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFilter

source_path, output_path = sys.argv[1], sys.argv[2]
size = 1024
radius = 228

mark = Image.open(source_path).convert("RGBA")
bbox = mark.getbbox()
if bbox is not None:
    mark = mark.crop(bbox)

canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
mask = Image.new("L", (size, size), 0)
draw_mask = ImageDraw.Draw(mask)
draw_mask.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)

background = Image.new("RGBA", (size, size), (7, 16, 24, 255))
bg_pixels = background.load()
for y in range(size):
    ratio = y / (size - 1)
    for x in range(size):
        radial = max(0, 1 - (((x - size * 0.5) / (size * 0.58)) ** 2 + ((y - size * 0.58) / (size * 0.52)) ** 2))
        r = int(7 + ratio * 7 + radial * 8)
        g = int(16 + ratio * 18 + radial * 42)
        b = int(24 + ratio * 30 + radial * 50)
        bg_pixels[x, y] = (r, g, b, 255)

glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
glow_draw = ImageDraw.Draw(glow)
glow_draw.ellipse((190, 245, 834, 895), fill=(67, 210, 232, 88))
glow = glow.filter(ImageFilter.GaussianBlur(90))
background.alpha_composite(glow)

tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
tile.alpha_composite(background)

inner_shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
shadow_draw = ImageDraw.Draw(inner_shadow)
shadow_draw.rounded_rectangle((24, 24, size - 25, size - 25), radius=radius - 32, outline=(255, 255, 255, 34), width=3)
tile.alpha_composite(inner_shadow)

target = 690
scale = min(target / mark.width, target / mark.height)
mark = mark.resize((int(mark.width * scale), int(mark.height * scale)), Image.Resampling.LANCZOS)
x = (size - mark.width) // 2
y = int((size - mark.height) * 0.49)
tile.alpha_composite(mark, (x, y))

canvas.alpha_composite(tile)
canvas.putalpha(mask)
canvas.save(output_path)
PY

  make_icon() {
    local size="$1"
    local name="$2"
    /usr/bin/sips -z "$size" "$size" "$ICON_BASE" --out "$ICONSET_DIR/$name" >/dev/null
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
