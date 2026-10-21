#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/New Window Plz.app"
if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/build.sh"
fi
"$APP/Contents/MacOS/NewWindowPlz" --switcher-benchmark
