#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-/Users/littlerobot/working_code/tinyTypeless/.derived/Build/Products/Debug/tinyTypeless.app}"
KEYCHAIN_PATH="$HOME/Library/Keychains/tinyTypeless-dev-v2.keychain-db"
CERT_NAME="tinyTypeless Local Development"
KEYCHAIN_PASSWORD="${TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD:-}"

if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
  echo "Missing TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD"
  exit 1
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"

codesign --force --deep --sign "$CERT_NAME" --keychain "$KEYCHAIN_PATH" "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,12p'
