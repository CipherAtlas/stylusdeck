#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

REPORT_LINES=()
NOTES=()

log() {
  printf "\n==> %s\n" "$1"
}

fail() {
  printf "\n[install] %s\n" "$1" >&2
  exit 1
}

add_report() {
  REPORT_LINES+=("$1|$2|$3|$4")
}

add_note() {
  NOTES+=("$1")
}

print_report() {
  printf "\nSetup report\n"
  printf "%s\n" "------------"

  for line in "${REPORT_LINES[@]}"; do
    IFS="|" read -r name status why detail <<<"$line"
    printf -- "- %s: %s\n" "$name" "$status"
    printf "  Why: %s\n" "$why"
    printf "  Detail: %s\n" "$detail"
  done

  printf "\nAudio behavior while running\n"
  printf "%s\n" "----------------------------"
  printf "%s\n" "- The app taps live system audio, applies the tablet volume/EQ processing, and mirrors the wet signal to two places."
  printf "%s\n" "- Monitor path: your real playback device such as headphones or speakers."
  printf "%s\n" "- Capture path: BlackHole 2ch so OBS can record the same processed signal."
  printf "%s\n" "- Safety behavior: if macOS is currently using BlackHole as the live monitor output, the app temporarily redirects monitor playback back to your real output device and restores the prior routing on exit."

  if ((${#NOTES[@]} > 0)); then
    printf "\nNotes\n"
    printf "%s\n" "-----"
    for note in "${NOTES[@]}"; do
      printf -- "- %s\n" "$note"
    done
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "This installer only supports macOS."
fi

add_report "Platform" "verified" "The app depends on macOS CoreAudio and AppKit APIs." "Detected $(sw_vers -productName) $(sw_vers -productVersion)."

if [[ ! -x /usr/bin/xcode-select ]]; then
  fail "xcode-select is missing. Install Xcode Command Line Tools first."
fi

if ! xcode-select -p >/dev/null 2>&1; then
  log "Requesting Xcode Command Line Tools install"
  xcode-select --install >/dev/null 2>&1 || true
  fail "Finish the Xcode Command Line Tools install dialog, then rerun ./start.sh."
fi

add_report "Xcode Command Line Tools" "already present" "Swift builds and macOS toolchain commands require them." "$(xcode-select -p)"

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    add_report "Homebrew" "already present" "Used to install BlackHole when missing and can also provision optional web UI support later." "$(brew --version | head -n 1)"
    return
  fi

  log "Installing Homebrew"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  add_report "Homebrew" "installed" "Used to install BlackHole when missing and can also provision optional web UI support later." "$(brew --version | head -n 1)"
}

ensure_homebrew

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  fail "Homebrew installation did not complete successfully."
fi

if command -v python3 >/dev/null 2>&1 && python3 - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 9) else 1)
PY
then
  add_report "Python 3" "available for optional web UI" "Only needed for the browser-based secondary interface." "$(python3 --version 2>&1)"
else
  add_report "Python 3" "not installed by default" "The native StylusDeck app is now the primary interface, so Python is only needed for the optional web UI." "Run brew install python later if you want the browser UI."
fi

has_blackhole_device() {
  system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 2ch"
}

log "Ensuring BlackHole 2ch is available"
if has_blackhole_device; then
  add_report "BlackHole 2ch" "already present" "Provides the virtual capture device for OBS while the wet monitor signal still plays through headphones or speakers." "Device is visible to macOS."
elif brew list --cask blackhole-2ch >/dev/null 2>&1; then
  add_report "BlackHole 2ch" "installed but not active yet" "Provides the virtual capture device for OBS while the wet monitor signal still plays through headphones or speakers." "The cask is installed, but the device is not visible to macOS yet."
  add_note "Reboot once so macOS finishes loading BlackHole 2ch, then rerun ./start.sh."
  print_report
  fail "BlackHole 2ch is installed but not yet active."
else
  if [[ ! -t 0 || ! -t 1 ]]; then
    fail "Installing BlackHole 2ch requires an interactive terminal because macOS will ask for your password."
  fi

  brew install --cask blackhole-2ch
  add_report "BlackHole 2ch" "installed" "Provides the virtual capture device for OBS while the wet monitor signal still plays through headphones or speakers." "Installed with Homebrew cask."

  if has_blackhole_device; then
    add_note "BlackHole 2ch is ready now."
  else
    add_note "Reboot once so macOS finishes loading BlackHole 2ch, then rerun ./start.sh."
    print_report
    fail "BlackHole 2ch was installed, but macOS has not activated the device yet."
  fi
fi

log "Building native targets"
cd "$REPO_ROOT"
swift build --product StylusDeck --product VolumeBridge --product EqBridge
add_report "Native targets" "built" "The primary deliverable is the native StylusDeck app. The bridge binaries are also built so the optional web UI can be used later without another compile step." "Built StylusDeck, VolumeBridge, and EqBridge in .build/debug."

print_report

cat <<'EOF'

Setup complete.

Next:
- The launcher will now start the native StylusDeck app.
- OBS should use BlackHole 2ch as its audio input device.
- If you want the browser-based secondary UI later, run ./scripts/run-web.sh.

EOF
