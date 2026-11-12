#!/usr/bin/env bash
# Check that a published release's Linux and Android files are exactly what
# its tag's source builds to.
#
#   scripts/repro_verify.sh v0.2.0
#   scripts/repro_verify.sh v0.2.0 --target android     linux | android | all
#
# Downloads the release's TemplarWallet-linux-x64.tar.gz,
# TemplarWallet-android-arm64.apk, TemplarWallet-android-x86_64.apk and
# SHA256SUMS.txt, rebuilds the same files from the tag with
# scripts/repro_build.sh, and compares:
#   - the tarball byte for byte;
#   - each APK with its signature set aside (scripts/repro_compare_apk.py):
#     the release is signed with the release key, the rebuild with a
#     throwaway one; every file inside, and where it sits, must be the same.
# Prints MATCH or DIFFER per file; exits 0 only when every file matches.
#
# The tag must exist in this clone (git fetch --tags). Releases built before
# reproducible builds existed (v0.1.0) do not match. macOS and Windows files
# are not covered: docs/build/REPRODUCIBLE.md says why.
# REPO=owner/name verifies a fork's releases.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage: repro_verify.sh <tag> [--target linux|android|all]}"
shift
TARGET=all
while (( $# )); do
  case "$1" in
    --target) TARGET="${2:?--target needs a value}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
case "$TARGET" in
  all) FILES=(TemplarWallet-linux-x64.tar.gz TemplarWallet-android-arm64.apk TemplarWallet-android-x86_64.apk) ;;
  linux) FILES=(TemplarWallet-linux-x64.tar.gz) ;;
  android) FILES=(TemplarWallet-android-arm64.apk TemplarWallet-android-x86_64.apk) ;;
  *) echo "--target must be linux, android or all" >&2; exit 2 ;;
esac
REPO="${REPO:-0xB4LdW1n/templar-wallet}"

git -C "$ROOT" rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null \
  || { echo "no tag $TAG in this clone: git fetch --tags" >&2; exit 1; }
if command -v sha256sum >/dev/null; then sha256() { sha256sum "$@"; }; else sha256() { shasum -a 256 "$@"; }; fi

DIR="$ROOT/dist/verify/$TAG"
mkdir -p "$DIR/release" "$DIR/rebuilt"

echo "== downloading the $TAG release files from github.com/$REPO"
for f in SHA256SUMS.txt "${FILES[@]}"; do
  curl -fsSL --retry 3 -o "$DIR/release/$f" "https://github.com/$REPO/releases/download/$TAG/$f"
done
# The downloads must be the files the release lists, before comparing them.
for f in "${FILES[@]}"; do
  line="$(awk -v f="$f" '$2 == f || $2 == "*" f' "$DIR/release/SHA256SUMS.txt")"
  [[ -n "$line" ]] || { echo "$f is not listed in the release's SHA256SUMS.txt" >&2; exit 1; }
  (cd "$DIR/release" && sha256 -c - <<<"$line")
done

"$ROOT/scripts/repro_build.sh" --ref "$TAG" --target "$TARGET" --out "$DIR/rebuilt"

echo "== comparing"
status=0
for f in "${FILES[@]}"; do
  case "$f" in
    *.apk)
      python3 "$ROOT/scripts/repro_compare_apk.py" "$DIR/release/$f" "$DIR/rebuilt/$f" || status=1 ;;
    *)
      if cmp -s "$DIR/release/$f" "$DIR/rebuilt/$f"; then
        echo "MATCH  $f  $(sha256 "$DIR/release/$f" | cut -d' ' -f1)"
      else
        echo "DIFFER $f"
        echo "  release $(sha256 "$DIR/release/$f" | cut -d' ' -f1)"
        echo "  rebuilt $(sha256 "$DIR/rebuilt/$f" | cut -d' ' -f1)"
        status=1
      fi ;;
  esac
done
if (( status == 0 )); then
  echo "== $TAG: every checked file is reproducible from its source"
else
  echo "== $TAG: NOT reproduced. diffoscope release/<file> rebuilt/<file> (in $DIR) shows where." >&2
fi
exit "$status"
