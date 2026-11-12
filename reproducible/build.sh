#!/usr/bin/env bash
# Runs INSIDE the reproducible build image (reproducible/Dockerfile), on a
# source tree that scripts/repro_build.sh extracted at /build from `git
# archive` of one commit. Writes the release files into /out:
#
#   build.sh linux     TemplarWallet-linux-x64.tar.gz
#   build.sh android   TemplarWallet-android-arm64.apk
#                      TemplarWallet-android-x86_64.apk
#
# The APKs come out signed with this container's throwaway debug key: the
# release workflow re-signs them with the release key afterwards, in a step
# that runs no build code, and changes nothing but the APK Signing Block.
# scripts/repro_compare_apk.py compares two APKs with that block taken out.
#
# Everything that could differ between two builds of one commit is fixed
# here or in the image: the paths (/build, /opt/...), the toolchains, the
# locale, the time zone, the umask, and SOURCE_DATE_EPOCH (the commit time),
# which dates every file in the tarball.
set -euo pipefail

target="${1:?usage: build.sh linux|android}"
: "${SOURCE_DATE_EPOCH:?set SOURCE_DATE_EPOCH to the commit time of the source}"
ROOT=/build
OUT=/out
umask 022
export TZ=UTC LC_ALL=C.UTF-8 CARGO_TERM_COLOR=never CARGO_INCREMENTAL=0
cd "$ROOT"
mkdir -p "$OUT"

# The C ABI Dart looks up by name must have survived the link.
check_exports() {
  local nm="$1" so="$2" symbols sym
  symbols="$("$nm" -D --defined-only "$so")"
  for sym in wallet_call wallet_free_string wallet_set_data_dir; do
    grep -qE " T $sym\$" <<<"$symbols" || { echo "$so does not export $sym" >&2; exit 1; }
  done
}

build_linux() {
  local bundle=apps/gui/build/linux/x64/release/bundle
  local name=TemplarWallet-linux-x64
  cargo build --locked --release -p wallet-ffi
  check_exports nm target/release/libwallet_ffi.so
  (cd apps/gui && flutter pub get --enforce-lockfile && flutter build linux --release)

  # The Dart loader looks for <exe dir>/lib/libwallet_ffi.so.
  cp target/release/libwallet_ffi.so "$bundle/lib/"
  cp INSTALL.md "$bundle/README.md"
  # templar:// handler registration (docs/guides/PROTOCOL_CONNECTOR.md)
  cp packaging/linux/dev.templarwallet.templar_wallet.desktop "$bundle/"

  # Every library the app loads must resolve: one that does not is a launch
  # failure on every machine.
  local missing
  missing="$(cd "$bundle" && LD_LIBRARY_PATH="$PWD/lib" ldd templar_wallet lib/*.so 2>&1 | grep 'not found' || true)"
  if [[ -n "$missing" ]]; then
    echo "unresolved libraries in the bundle:" >&2
    echo "$missing" >&2
    exit 1
  fi
  # The newest glibc symbol anything asks for = the oldest glibc it runs on.
  local glibc
  glibc="$(cd "$bundle" && objdump -T templar_wallet lib/*.so | grep -o 'GLIBC_[0-9][0-9.]*' | sed 's/GLIBC_//' | sort -uV | tail -n 1)"
  echo "Linux bundle: needs glibc $glibc or newer"

  # One top-level folder named like the file. Names sorted, owner root, every
  # mtime the commit time, permissions normalised, gzip without a name or a
  # timestamp: the archive depends on the files' contents only.
  local stage
  stage="$(mktemp -d)"
  cp -a "$bundle" "$stage/$name"
  tar -C "$stage" --sort=name --format=gnu \
      --owner=0 --group=0 --numeric-owner \
      --mtime="@$SOURCE_DATE_EPOCH" --mode='u+rwX,go+rX,go-w' \
      -cf - "$name" | gzip -9n > "$OUT/$name.tar.gz"
  rm -rf "$stage"
}

build_android() {
  # Two halves, as in scripts/build_android.sh: the Rust engine per ABI, then
  # the APKs. No signing key exists in this container, so Gradle signs with a
  # debug key it generates here (and says so).
  ./scripts/build_android.sh --release --so-only
  ./scripts/build_android.sh --release --apk-only
  local built=apps/gui/build/app/outputs/flutter-apk pair abi
  for pair in arm64-v8a:arm64 x86_64:x86_64; do
    abi="${pair%%:*}"
    cp "$built/app-$abi-release.apk" "$OUT/TemplarWallet-android-${pair#*:}.apk"
  done
}

case "$target" in
  linux) build_linux; files=(TemplarWallet-linux-x64.tar.gz) ;;
  android) build_android; files=(TemplarWallet-android-arm64.apk TemplarWallet-android-x86_64.apk) ;;
  *) echo "unknown target: $target (linux or android)" >&2; exit 2 ;;
esac

cd "$OUT"
sha256sum -- "${files[@]}"
# Hand the files to whoever started the container (a root-owned file in a
# bind mount is a nuisance on a Linux host).
if [[ -n "${HOST_UID:-}" && -n "${HOST_GID:-}" ]]; then
  chown "$HOST_UID:$HOST_GID" -- "${files[@]}"
fi
