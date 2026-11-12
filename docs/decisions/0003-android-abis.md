# 0003 — Android ABIs: arm64-v8a and x86_64 only

**Status:** accepted, in force.

## Context

Every Android ABI means one more native library to build and ship. The
embedded database the Bitcoin engine uses (`sled` 0.34) is not a safe bet on
32-bit targets.

## Decision

- Build `arm64-v8a` (phones) and `x86_64` (emulators, x86_64 devices); drop
  `armeabi-v7a`.
- One APK per ABI (`flutter build apk --split-per-abi`), selected with
  `--target-platform android-arm64,android-x64` in
  `scripts/build_android.sh`. No fixed `abiFilters` in Gradle: they conflict
  with `--split-per-abi`.
- Minimum SDK 24 (Android 7.0), as `scripts/build_android.sh` and
  `apps/gui/android/app/build.gradle.kts` pin it.

## Consequences

- Releases carry two APKs, `TemplarWallet-android-arm64.apk` and
  `TemplarWallet-android-x86_64.apk`.
- 32-bit-only phones cannot install the wallet.
