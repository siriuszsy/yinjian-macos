#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is not installed."
  echo "Install it with: brew install xcodegen"
  exit 1
fi

cd "$ROOT_DIR"
xcodegen generate --spec project.yml
echo "Generated $ROOT_DIR/tinyTypeless.xcodeproj"
