#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
xcodegen generate
xcodebuild \
  -project NewWindowPlz.xcodeproj \
  -scheme NewWindowPlz \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  -destination 'platform=macOS,arch=arm64' \
  test \
  CODE_SIGNING_ALLOWED=YES
