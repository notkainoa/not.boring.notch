#!/bin/zsh
# Build this checkout (ad-hoc signed, own DerivedData) and run it.
# Usage: scripts/dev.sh [run|build|kill]   (default: run)
# Works from any git worktree; each worktree builds into its own .build/dev.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD
DD="$ROOT/.build/dev"
APP="$DD/Build/Products/Debug/Boring Notch.app"
BIN="$APP/Contents/MacOS/Boring Notch"

kill_ours() { pkill -f "$DD/Build/Products/Debug/Boring Notch.app" 2>/dev/null || true; }

case "${1:-run}" in
  kill) kill_ours; exit 0 ;;
  build|run) ;;
  *) echo "usage: $0 [run|build|kill]"; exit 2 ;;
esac

# The installed Boring Notch uses the same bundle id and XPC service name.
# Two copies fight over the notch, so refuse to start while it is running.
if [[ "${1:-run}" == run ]] && pgrep -f "/Applications/Boring Notch.app/Contents/MacOS" >/dev/null; then
  echo "The installed Boring Notch is running. Quit it first (menu: notch > Quit), then rerun." >&2
  exit 1
fi

kill_ours
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch -configuration Debug \
  -derivedDataPath "$DD" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM= \
  build | tail -n 25

[[ "${1:-run}" == build ]] && { echo "Built: $APP"; exit 0; }
echo "Running $APP (Ctrl-C to quit)"
exec "$BIN"
