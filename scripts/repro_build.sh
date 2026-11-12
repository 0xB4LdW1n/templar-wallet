#!/usr/bin/env bash
# Build Templar Wallet's reproducible release files from one commit, in the
# pinned container of that commit (reproducible/Dockerfile).
#
#   scripts/repro_build.sh                    Linux + Android from HEAD
#   scripts/repro_build.sh --ref v0.2.0       from a tag (or any commit)
#   scripts/repro_build.sh --target linux     linux | android | all (default)
#   scripts/repro_build.sh --out DIR          default dist/repro/<commit>/
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
#
# Needs git and Docker (or Podman: CONTAINER=podman). The image is
# linux/amd64; on an ARM machine it runs emulated, slower, same result.
# A first run downloads ~4 GB of toolchains per target and takes a while.
# Docs: docs/build/REPRODUCIBLE.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF=HEAD
TARGET=all
OUT=
while (( $# )); do
  case "$1" in
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    --target) TARGET="${2:?--target needs a value}"; shift 2 ;;
    --out) OUT="${2:?--out needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,24p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$TARGET" in
  all) TARGETS=(linux android) ;;
  linux|android) TARGETS=("$TARGET") ;;
  *) echo "--target must be linux, android or all" >&2; exit 2 ;;
esac

ENGINE="${CONTAINER:-docker}"
command -v "$ENGINE" >/dev/null || { echo "$ENGINE not found (set CONTAINER=podman to use Podman)" >&2; exit 1; }

commit="$(git -C "$ROOT" rev-parse --verify "$REF^{commit}")"
epoch="$(git -C "$ROOT" log -1 --format=%ct "$commit")"
OUT="${OUT:-$ROOT/dist/repro/$commit}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir "$work/context"
git -C "$ROOT" archive --format=tar -o "$work/source.tar" "$commit"
git -C "$ROOT" show "$commit:reproducible/Dockerfile" > "$work/Dockerfile"
if command -v sha256sum >/dev/null; then sha256() { sha256sum "$@"; }; else sha256() { shasum -a 256 "$@"; }; fi
dockerfile_id="$(sha256 "$work/Dockerfile" | cut -c1-12)"

echo "== source  $commit ($(git -C "$ROOT" log -1 --format=%cI "$commit"))"
echo "== output  $OUT"
for t in "${TARGETS[@]}"; do
  image="templar-wallet-build:$t-$dockerfile_id"
  echo "== image   $image"
  "$ENGINE" build --platform linux/amd64 --target "$t" -t "$image" -f "$work/Dockerfile" "$work/context"
  echo "== build   $t"
  "$ENGINE" run --rm -i --platform linux/amd64 \
    -e SOURCE_DATE_EPOCH="$epoch" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -v "$OUT:/out" "$image" \
    bash -c 'set -e; mkdir -p /build; tar -x -C /build; exec bash /build/reproducible/build.sh "$1"' _ "$t" \
    < "$work/source.tar"
done

echo "== done"
(cd "$OUT" && sha256 TemplarWallet-*)
