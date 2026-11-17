#!/usr/bin/env bash
# Build the Flutter macOS app (debug) as "Templar Wallet Testlab.app" for
# manual testing against a Templar test server (docs/guides/TEST_SERVER.md).
#
# Unlike build_debug_app.sh this build has its OWN bundle id, so macOS gives
# it its own sandbox container, preferences and keychain: it never opens the
# real vault, and joining a test server (which switches the Liquid network)
# does not touch the everyday installation. The bundle id is overridden on
# the xcodebuild command line; no project file changes.
#
# Usage: scripts/build_testlab_app.sh [DEST_DIR]   (default: <repo>/dist)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST_DIR="${1:-$ROOT/dist}"
BUNDLE_ID="dev.templarwallet.testlab"
cd "$ROOT/apps/gui"
flutter pub get >/dev/null
FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" flutter build macos --debug
SRC="build/macos/Build/Products/Debug/templar_wallet.app"
BUILT_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SRC/Contents/Info.plist")"
if [ "$BUILT_ID" != "$BUNDLE_ID" ]; then
  echo "error: built bundle id is $BUILT_ID, not $BUNDLE_ID; refusing to hand over" >&2
  echo "       an app that would open the real vault." >&2
  exit 1
fi
mkdir -p "$DEST_DIR"
DEST="$DEST_DIR/Templar Wallet Testlab.app"
rm -rf "$DEST"
cp -R "$SRC" "$DEST"
BRANCH="$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
echo "Built Templar Wallet Testlab ($BUNDLE_ID) from $BRANCH @ $COMMIT"
echo "→ $DEST"
echo "Its data lives in ~/Library/Containers/$BUNDLE_ID/ — delete that folder to start over."
