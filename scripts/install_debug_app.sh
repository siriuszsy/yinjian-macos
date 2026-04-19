#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DIR="$ROOT_DIR/.derived"
BUILD_APP="$DERIVED_DIR/Build/Products/Debug/voiceKey.app"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_APP="$INSTALL_DIR/voiceKey.app"
RESIGN_SCRIPT="$ROOT_DIR/scripts/resign_debug_app.sh"

xcodebuild \
  -project "$ROOT_DIR/voiceKey.xcodeproj" \
  -scheme voiceKey \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DIR" \
  build >/dev/null

zsh "$RESIGN_SCRIPT" "$BUILD_APP" >/dev/null

mkdir -p "$INSTALL_DIR"
ditto "$BUILD_APP" "$INSTALL_APP"

open -n "$INSTALL_APP"

echo "Installed debug app to $INSTALL_APP"
