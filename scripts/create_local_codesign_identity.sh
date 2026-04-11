#!/bin/zsh
set -euo pipefail

ROOT="/Users/littlerobot/working_code/tinyTypeless"
CODESIGN_DIR="$ROOT/codesign"
KEYCHAIN_PATH="$HOME/Library/Keychains/tinyTypeless-dev-v2.keychain-db"
CERT_NAME="tinyTypeless Local Development"
OPENSSL_CONFIG="$CODESIGN_DIR/openssl-codesign.cnf"
KEY_PATH="$CODESIGN_DIR/tinyTypeless-dev.key.pem"
CERT_PATH="$CODESIGN_DIR/tinyTypeless-dev.cert.pem"
P12_PATH="$CODESIGN_DIR/tinyTypeless-dev.p12"
KEYCHAIN_PASSWORD="${TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD:-}"
P12_PASSWORD="${TINYTYPELESS_CODESIGN_P12_PASSWORD:-$KEYCHAIN_PASSWORD}"

if [[ -z "$KEYCHAIN_PASSWORD" ]]; then
  echo "Missing TINYTYPELESS_CODESIGN_KEYCHAIN_PASSWORD"
  exit 1
fi

if [[ -z "$P12_PASSWORD" ]]; then
  echo "Missing TINYTYPELESS_CODESIGN_P12_PASSWORD"
  exit 1
fi

mkdir -p "$CODESIGN_DIR"

if ! security show-keychain-info "$KEYCHAIN_PATH" >/dev/null 2>&1; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security list-keychains -d user -s "$KEYCHAIN_PATH" "$HOME/Library/Keychains/login.keychain-db"

if ! security find-certificate -c "$CERT_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1; then
  /opt/homebrew/bin/openssl req -x509 -newkey rsa:2048 -nodes \
    -days 3650 \
    -config "$OPENSSL_CONFIG" \
    -keyout "$KEY_PATH" \
    -out "$CERT_PATH"

  /opt/homebrew/bin/openssl pkcs12 -export \
    -inkey "$KEY_PATH" \
    -in "$CERT_PATH" \
    -out "$P12_PATH" \
    -passout "pass:$P12_PASSWORD"

  security import "$P12_PATH" -k "$KEYCHAIN_PATH" -P "$P12_PASSWORD" -A -f pkcs12
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

security find-identity -v -p codesigning "$KEYCHAIN_PATH"
