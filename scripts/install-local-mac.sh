#!/bin/sh

set -eu

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer only supports macOS." >&2
  exit 1
fi

LAUNCH_AFTER_INSTALL=0
if [ "${1-}" = "--launch" ]; then
  LAUNCH_AFTER_INSTALL=1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
DIST_DIR="$REPO_ROOT/dist"
TARGET_APP="/Applications/Desktopflow.app"

cd "$REPO_ROOT"

echo "Building Desktopflow.app ..."
npm run dist:dir

APP_SOURCE=$(find "$DIST_DIR" -maxdepth 3 -type d -name "Desktopflow.app" | head -n 1)
if [ -z "$APP_SOURCE" ]; then
  echo "Desktopflow.app was not found in $DIST_DIR after build." >&2
  exit 1
fi

echo "Installing to $TARGET_APP ..."
rm -rf "$TARGET_APP"
ditto "$APP_SOURCE" "$TARGET_APP"
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

echo "Installed Desktopflow to /Applications."
echo "Launch it from Spotlight, Launchpad, Finder, or keep it in your Dock."

if [ "$LAUNCH_AFTER_INSTALL" -eq 1 ]; then
  open "$TARGET_APP"
fi
