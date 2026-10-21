#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi

echo "==> Generating Xcode project"
xcodegen generate

DERIVED="$ROOT/.build/ReleaseDerivedData"
APP_SOURCE="$DERIVED/Build/Products/Release/NewWindowPlz.app"
APP_DEST="$ROOT/dist/New Window Plz.app"

echo "==> Building Release"
rm -rf "$DERIVED"
xcodebuild \
  -project NewWindowPlz.xcodeproj \
  -scheme NewWindowPlz \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  build \
  CODE_SIGNING_ALLOWED=YES

echo "==> Staging app bundle"
mkdir -p "$ROOT/dist"
rm -rf "$APP_DEST"
ditto "$APP_SOURCE" "$APP_DEST"
codesign --force --deep --sign - --timestamp=none "$APP_DEST"
codesign --verify --deep --strict --verbose=2 "$APP_DEST"

echo
echo "Built: $APP_DEST"
echo "Move it to /Applications, launch it, then grant Accessibility access."
