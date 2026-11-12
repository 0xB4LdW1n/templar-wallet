#!/usr/bin/env bash
# Build Templar Wallet's reproducible release files from one commit, in the
# pinned container of that commit (reproducible/Dockerfile).
#
#   scripts/repro_build.sh                    Linux + Android from HEAD
#   scripts/repro_build.sh --ref v0.2.0       from a tag (or any commit)
#   scripts/repro_build.sh --target linux     linux | android | all (default)
#   scripts/repro_build.sh --out DIR          default dist/repro/<commit>/
#   scripts/repro_build.sh --print-image --target android
#                                             print the image's name and exit
#
# Output: TemplarWallet-linux-x64.tar.gz, TemplarWallet-android-arm64.apk,
# TemplarWallet-android-x86_64.apk. The tarball must match the release file
# byte for byte; the APKs carry a throwaway debug signature, so compare them
# with scripts/repro_compare_apk.py (scripts/repro_verify.sh does all of it).
#
# What makes two runs agree: the source is `git archive` of the commit (no
# untracked file, no local edit reaches the build), the image and the build
# script come from that same commit, the build runs at /build inside the
# container whatever the host, and SOURCE_DATE_EPOCH is the commit time.
# The image is named after its inputs (Dockerfile and apt-install), so a
# commit that changes neither reuses the image an earlier run built.
#
# Needs git and Docker (or Podman: CONTAINER=podman). The image is
# linux/amd64; on an ARM machine it runs emulated, slower, same result.
# --out must be a folder the container engine can share (Colima and Podman
# machines share your home folder by default, not /tmp).
# A first run downloads ~4 GB of toolchains per target and takes a while.
# Docs: docs/build/REPRODUCIBLE.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF=HEAD
TARGET=all
OUT=
PRINT_IMAGE=false
while (( $# )); do
  case "$1" in
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    --target) TARGET="${2:?--target needs a value}"; shift 2 ;;
    --out) OUT="${2:?--out needs a value}"; shift 2 ;;
    --print-image) PRINT_IMAGE=true; shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$TARGET" in
  all) TARGETS=(linux android) ;;
  linux|android) TARGETS=("$TARGET") ;;
  *) echo "--target must be linux, android or all" >&2; exit 2 ;;
esac

commit="$(git -C "$ROOT" rev-parse --verify "$REF^{commit}")"
if command -v sha256sum >/dev/null; then sha256() { sha256sum "$@"; }; else sha256() { shasum -a 256 "$@"; }; fi
# The image's inputs: the files reproducible/Dockerfile builds from.
IMAGE_FILES=(reproducible/Dockerfile reproducible/apt-install)
image_id="$(for f in "${IMAGE_FILES[@]}"; do git -C "$ROOT" rev-parse "$commit:$f"; done | sha256 | cut -c1-12)"

if [[ "$PRINT_IMAGE" == true ]]; then
  (( ${#TARGETS[@]} == 1 )) || { echo "--print-image needs --target linux or --target android" >&2; exit 2; }
  echo "templar-wallet-build:${TARGETS[0]}-$image_id"
  exit 0
fi

ENGINE="${CONTAINER:-docker}"
command -v "$ENGINE" >/dev/null || { echo "$ENGINE not found (set CONTAINER=podman to use Podman)" >&2; exit 1; }

epoch="$(git -C "$ROOT" log -1 --format=%ct "$commit")"
OUT="${OUT:-$ROOT/dist/repro/$commit}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/context"
git -C "$ROOT" archive --format=tar -o "$work/source.tar" "$commit"
git -C "$ROOT" archive --format=tar "$commit" "${IMAGE_FILES[@]}" | tar -x -C "$work/context"

echo "== source  $commit ($(git -C "$ROOT" log -1 --format=%cI "$commit"))"
echo "== output  $OUT"
for t in "${TARGETS[@]}"; do
  image="templar-wallet-build:$t-$image_id"
  echo "== image   $image"
  "$ENGINE" build --platform linux/amd64 --target "$t" -t "$image" \
    -f "$work/context/reproducible/Dockerfile" "$work/context/reproducible"
  echo "== build   $t"
  "$ENGINE" run --rm -i --platform linux/amd64 \
    -e SOURCE_DATE_EPOCH="$epoch" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$OUT:/out" "$image" \
    bash -c 'set -e; mkdir -p /build; tar -x -C /build; exec bash /build/reproducible/build.sh "$1"' _ "$t" \
    < "$work/source.tar"
  # A folder the engine's VM does not share gets the files inside the VM.
  case "$t" in
    linux) expect=(TemplarWallet-linux-x64.tar.gz) ;;
    android) expect=(TemplarWallet-android-arm64.apk TemplarWallet-android-x86_64.apk) ;;
  esac
  for f in "${expect[@]}"; do
    [[ -f "$OUT/$f" ]] || { echo "the build wrote $f, but it is not in $OUT: is that folder shared with $ENGINE's VM? Pass --out under your home folder." >&2; exit 1; }
  done
done

echo "== done"
(cd "$OUT" && sha256 TemplarWallet-*)
