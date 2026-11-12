#!/bin/sh
# Rebuilds the Rust FFI dylib and bundles it into the built .app so Dart's
# dlopen() finds it at Contents/Frameworks/libwallet_ffi.dylib.
#
# Invoked from the Runner target's "Run Script" build phase, so Xcode build
# vars ($SRCROOT, $BUILT_PRODUCTS_DIR, $CONTENTS_FOLDER_PATH) are in scope.
# $SRCROOT = <repo>/apps/gui/macos  →  repo root = $SRCROOT/../../..
set -e

REPO_ROOT="$SRCROOT/../../.."

# rustup's own install puts cargo in $CARGO_HOME/bin (~/.cargo/bin); Homebrew's
# rustup (GitHub's macOS runners) in its prefix. Xcode may run this script with
# a shorter PATH than the shell's, so look in those places by name too.
find_tool() {
    for c in "${CARGO_HOME:-$HOME/.cargo}/bin/$1" "$(command -v "$1" 2>/dev/null)" \
             "/opt/homebrew/opt/rustup/bin/$1" "/opt/homebrew/bin/$1" "/usr/local/bin/$1"; do
        if [ -n "$c" ] && [ -x "$c" ]; then echo "$c"; return 0; fi
    done
    return 1
}
CARGO="$(find_tool cargo)" || { echo "error: cargo not found (install Rust: https://rustup.rs)" >&2; exit 1; }
RUSTUP="$(find_tool rustup || true)"

# Flutter builds the app universal (arm64 + x86_64); the dylib must match or
# Intel Macs crash at dlopen. Build every architecture whose Rust target is
# installed and lipo them together — with only the host target installed this
# degrades to a host-arch dylib (fine for local dev runs).
SLICES=""
for TARGET in aarch64-apple-darwin x86_64-apple-darwin; do
    if [ -n "$RUSTUP" ] && "$RUSTUP" target list --installed 2>/dev/null | grep -q "$TARGET"; then
        "$CARGO" build --release -p wallet-ffi --target "$TARGET" \
            --manifest-path "$REPO_ROOT/Cargo.toml"
        SLICES="$SLICES $REPO_ROOT/target/$TARGET/release/libwallet_ffi.dylib"
    fi
done

DEST="$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Frameworks"
mkdir -p "$DEST"

if [ -z "$SLICES" ]; then
    # rustup missing (plain cargo install): host-only build, old behavior.
    "$CARGO" build --release -p wallet-ffi --manifest-path "$REPO_ROOT/Cargo.toml"
    cp "$REPO_ROOT/target/release/libwallet_ffi.dylib" "$DEST/"
else
    lipo -create $SLICES -output "$DEST/libwallet_ffi.dylib"
fi

# Ad-hoc sign so the hardened-runtime app will load it.
codesign --force --sign - "$DEST/libwallet_ffi.dylib"

echo "wallet-ffi: bundled libwallet_ffi.dylib ($(lipo -archs "$DEST/libwallet_ffi.dylib" 2>/dev/null || echo host)) -> $DEST"
