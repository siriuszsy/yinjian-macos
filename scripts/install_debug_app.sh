#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DIR="$ROOT_DIR/.derived"
BUILD_APP="$DERIVED_DIR/Build/Products/Debug/tinyTypeless.app"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/tinyTypeless.app"

xcodebuild \
  -project "$ROOT_DIR/tinyTypeless.xcodeproj" \
  -scheme tinyTypeless \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DIR" \
  build >/dev/null

mkdir -p "$INSTALL_DIR"
ditto "$BUILD_APP" "$INSTALL_APP"

open -n "$INSTALL_APP"

echo "Installed debug app to $INSTALL_APP"
