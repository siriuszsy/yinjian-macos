#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$ROOT_DIR/tinyTypeless"

SWIFT_FILES=()
while IFS= read -r file; do
  SWIFT_FILES+=("$file")
done < <(rg --files "$SRC_DIR" -g '*.swift')

if [ "${#SWIFT_FILES[@]}" -eq 0 ]; then
  echo "No Swift files found under $SRC_DIR"
  exit 1
fi

xcrun swiftc -typecheck "${SWIFT_FILES[@]}"
echo "Source typecheck passed."
