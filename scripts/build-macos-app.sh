#!/usr/bin/env bash
# Build Taskit as a launchable .app on macOS (requires Xcode / Swift 5.9+).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/dist/Taskit.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script must run on macOS with Xcode installed."
  exit 1
fi

cd "$ROOT/Taskit"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/Taskit"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BIN" "$MACOS/Taskit"
cp "$ROOT/Taskit/Sources/Taskit/Resources/Info.plist" "$CONTENTS/Info.plist"

# Bundle resources produced by SPM if present.
if [[ -d "$(swift build -c release --show-bin-path)/Taskit_Taskit.bundle" ]]; then
  cp -R "$(swift build -c release --show-bin-path)/Taskit_Taskit.bundle" "$RESOURCES/"
fi

chmod +x "$MACOS/Taskit"

# Ad-hoc sign so macOS treats it as one app (needed for Open at login and notifications).
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
echo "Open with: open \"$APP_DIR\""
