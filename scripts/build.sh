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
SIGN_KEYCHAIN="${SIGN_KEYCHAIN:-$ROOT/build/signing/dev.keychain}"
SIGN_PASSWORD_FILE="${SIGN_PASSWORD_FILE:-$ROOT/build/signing/.password}"
SIGN_IDENTITY="${SIGN_IDENTITY:-New Window Plz Development}"

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

if [[ -f "$SIGN_KEYCHAIN" && -f "$SIGN_PASSWORD_FILE" ]]; then
  echo "==> Signing with stable identity: $SIGN_IDENTITY"
  security unlock-keychain -p "$(cat "$SIGN_PASSWORD_FILE")" "$SIGN_KEYCHAIN" >/dev/null
  SIGN_ARGS=(--force --timestamp=none --keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY")
else
  echo "warning: stable signing keychain not found; falling back to ad-hoc"
  echo "         run scripts/setup-signing.sh once to keep Accessibility across rebuilds"
  SIGN_ARGS=(--force --timestamp=none --sign -)
fi

codesign "${SIGN_ARGS[@]}" "$APP_DEST/Contents/MacOS/NewWindowPlz"
codesign "${SIGN_ARGS[@]}" "$APP_DEST"
codesign --verify --deep --strict --verbose=2 "$APP_DEST"
echo "==> Designated requirement"
codesign -d -r- "$APP_DEST" 2>&1 | tail -1

echo
echo "Built: $APP_DEST"
echo "Move it to /Applications and launch it. Accessibility is retained when this stable identity is used; grant once if prompted."
