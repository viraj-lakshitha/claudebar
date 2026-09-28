#!/usr/bin/env bash
# Builds ClaudeBar.app into ./build using SwiftPM (no Xcode project needed).
#   UNIVERSAL=1 scripts/build-app.sh   # arm64 + x86_64 (needs full Xcode)
set -euo pipefail

cd "$(dirname "$0")/.."

ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="build/ClaudeBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClaudeBar" "$APP/Contents/MacOS/ClaudeBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so Keychain items and the login item stick to this app.
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
