# Templar Wallet — Android build guide

Builds one APK per ABI: `arm64-v8a` for phones and `x86_64` for emulators
([decision 0003](../decisions/0003-android-abis.md)). Read
[`README.md`](README.md) first: the engine must be checked out beside this
repository.

## 1. Requirements

- An Android SDK: `$ANDROID_HOME`, else Android Studio's default location for
  the OS.
- Flutter at the CI pin, with the Android toolchain (`flutter doctor`).
- A JDK 17.
- Rust through [rustup](https://rustup.rs).

`scripts/build_android.sh` installs the rest on first use when it is
missing: NDK `28.2.13676358` (through the SDK's `sdkmanager`), `cargo-ndk`,
and the Rust targets `aarch64-linux-android` and `x86_64-linux-android`.

## 2. Build

```bash
./scripts/build_android.sh              # debug APKs
./scripts/build_android.sh --release    # release APKs
./scripts/build_android.sh --so-only    # only the Rust libraries, into jniLibs
./scripts/build_android.sh --apk-only   # only the APKs, from the libraries already built
```

The script:

1. builds `crates/wallet-ffi` for both ABIs with `cargo ndk`, with
   `--no-default-features` so the USB hardware stack stays out
   ([decision 0001](../decisions/0001-android-without-usb-hardware.md)),
   into `apps/gui/android/app/src/main/jniLibs/<abi>/` (gitignored);
2. checks that each library exports `wallet_call`, `wallet_free_string` and
   `wallet_set_data_dir`;
3. runs `flutter build apk --split-per-abi` for `android-arm64` and
   `android-x64`.

Output, in `apps/gui/build/app/outputs/flutter-apk/`:
`app-arm64-v8a-<mode>.apk` and `app-x86_64-<mode>.apk`. Install one with
`adb install -r <apk>`.

## 3. Signing

A `--release` build is signed with the release key when Gradle finds one
(environment variables or `apps/gui/android/key.properties`), otherwise with
your debug key, and the script says which. An APK signed with a debug key
cannot update one signed with the release key, or the reverse. Where the key
comes from and how CI holds it: [`RELEASE.md`](RELEASE.md) § 4.

## 4. Running on an emulator without funds

A debug build started with `--dart-define=TEMPLAR_MOCK_BRIDGE=true` serves
the in-memory mock instead of the engine, so populated screens can be checked
without funding a testnet wallet. It is ignored outside debug builds.

## Notes

- Minimum Android version: 7.0 (SDK 24).
- No USB hardware wallets on Android; air-gapped QR signing works.
- The app passes its private support directory to the engine at start-up
  ([decision 0002](../decisions/0002-host-injects-the-data-directory.md)).
- CI's `android` job runs `--release --so-only`, then `--release --apk-only`
  with the signing secrets, so the key is never in the environment while
  crates build.
