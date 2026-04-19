#!/bin/zsh
set -euo pipefail

APP_PATH="${1:-/Users/littlerobot/working_code/tinyTypeless/.derived/Build/Products/Debug/tinyTypeless.app}"
LOGIN_KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"
LOCAL_KEYCHAIN_PATH="${TINYTYPELESS_CODESIGN_KEYCHAIN_PATH:-$HOME/Library/Keychains/tinyTypeless-dev-v2.keychain-db}"
LOCAL_CERT_NAME="${TINYTYPELESS_CODESIGN_CERT_NAME:-tinyTypeless Local Development}"
KEYCHAIN_PATH=""
CERT_NAME=""
KEYCHAIN_PASSWORD="${TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD:-}"

detect_apple_development_identity() {
  security find-identity -v -p codesigning "$LOGIN_KEYCHAIN_PATH" 2>/dev/null \
    | awk -F'"' '/Apple Development/ { print $2; exit }'
}

APPLE_DEVELOPMENT_IDENTITY="$(detect_apple_development_identity)"

if [[ -n "$APPLE_DEVELOPMENT_IDENTITY" ]]; then
  CERT_NAME="$APPLE_DEVELOPMENT_IDENTITY"
  KEYCHAIN_PATH="$LOGIN_KEYCHAIN_PATH"
else
  CERT_NAME="$LOCAL_CERT_NAME"
  KEYCHAIN_PATH="$LOCAL_KEYCHAIN_PATH"
fi

if [[ "$KEYCHAIN_PATH" == "$LOCAL_KEYCHAIN_PATH" && -z "$KEYCHAIN_PASSWORD" ]]; then
  KEYCHAIN_PASSWORD="$(launchctl getenv TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD 2>/dev/null || true)"
fi

if [[ "$KEYCHAIN_PATH" == "$LOCAL_KEYCHAIN_PATH" && -z "$KEYCHAIN_PASSWORD" ]]; then
  echo "No Apple Development identity found in login.keychain-db"
  echo "Missing TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD for local fallback signing"
  exit 1
fi

if [[ -n "$KEYCHAIN_PASSWORD" ]]; then
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

security list-keychains -d user -s "$KEYCHAIN_PATH" "$LOGIN_KEYCHAIN_PATH"

codesign --force --deep --sign "$CERT_NAME" --keychain "$KEYCHAIN_PATH" "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | sed -n '1,12p'
