# Reproducible builds

How anyone can check that the Linux and Android files of a Templar Wallet
release were built from the source of its tag, and nothing else.

Open source lets you read the code; a reproducible build lets you check that
the file you downloaded is that code. Every input of the build is pinned, so
building the same tag again, on any machine, gives the same bytes. If your
rebuild matches the published file, the file contains exactly what the tag's
source says, whoever ran the build server.

| Release file | Reproducible | Compared |
|---|---|---|
| `TemplarWallet-linux-x64.tar.gz` | yes | byte for byte |
| `TemplarWallet-android-arm64.apk` | yes | byte for byte, signature aside |
| `TemplarWallet-android-x86_64.apk` | yes | byte for byte, signature aside |
| `TemplarWallet-macos.dmg` | not yet | see [What is not covered](#what-is-not-covered) |
| `TemplarWallet-windows-x64-setup.exe`, `-x64.zip` | not yet | see [What is not covered](#what-is-not-covered) |

Releases from the first one built this way onward; `v0.1.0` predates it and
does not match.

## Verify a release

You need git, Docker (or Podman, with `CONTAINER=podman`), Python 3, about
40 GB of free disk, and time: the first run downloads a few GB of toolchains
per target (the Linux image alone is 4.2 GB), and on an ARM machine (Apple
silicon included) the `linux/amd64` image runs emulated, several times slower
than on an x86-64 PC. The result does not depend on the machine. With Colima
or a Podman machine, keep the clone under your home folder: by default it is
the only folder their VM shares with the container.

```bash
git clone https://github.com/0xB4LdW1n/templar-wallet.git
cd templar-wallet
scripts/repro_verify.sh v0.2.0                     # the tag to check
```

`--target linux` or `--target android` checks one half. The script:

1. downloads the release's Linux and Android files and `SHA256SUMS.txt`, and
   checks the downloads against it;
2. rebuilds them from the tag with `scripts/repro_build.sh`, in the container
   that tag defines;
3. compares, and prints `MATCH` or `DIFFER` per file. It exits 0 only when
   every file matches.

Everything lands in `dist/verify/<tag>/` (`release/` and `rebuilt/`). On a
`DIFFER`, [diffoscope](https://diffoscope.org) on the two files shows where
they part, and an issue with its output is welcome.

The release workflow does the same check on every release before publishing
(below), so a mismatch on your machine means something differs between your
rebuild and the ones CI ran: please report it.

## Why an APK is compared "signature aside"

Android refuses an app that is not signed, and only the maintainers hold the
release key, so your rebuild cannot carry the release signature. An APK
(minSdk 24, schemes v2/v3) keeps its signature in an *APK Signing Block*
between the files and the zip's central directory.
`scripts/repro_compare_apk.py` sets aside exactly what signing changes:

- the APK Signing Block;
- zero padding a signer may place before it (`apksigner` pads the files to a
  4 KiB boundary; Gradle's own signer need not);
- the central directory's offset in the zip's end record, which moves with
  the block.

Everything else must be identical: every file, its compression, its position
in the zip, the central directory. That is the same guarantee as F-Droid's
`apksigcopier compare`: copy the release's signature onto your rebuild and
you get the release file. To check who signed the release:

```bash
apksigner verify --print-certs TemplarWallet-android-arm64.apk
```

The certificate's SHA-256 is in each release's notes.

## What makes the build reproducible

| Input | Pinned by |
|---|---|
| The source | `git archive` of the tagged commit: no untracked file and no local change reaches the build |
| The base system | `ubuntu:22.04` by image digest (`reproducible/Dockerfile`) |
| System packages (clang, GTK, CMake, JDK, …) | a fixed snapshot of the Ubuntu archive, `snapshot.ubuntu.com/ubuntu/<date>`: its signed index sets every version and every file's hash (`reproducible/apt-install` fetches the files from the regular archive while it has them, checked against those hashes, since the snapshot service is slow) |
| Rust | `rustup-init` by SHA-256, toolchain 1.95.0 (components checked against the channel manifest) |
| Rust crates, the engine included | `Cargo.lock` (checksums; templarlib by tag and commit), `--locked` |
| Flutter | release 3.44.1, checked against its commit; Dart SDK and engine artifacts follow from it |
| Dart packages | `pubspec.lock` (content hashes), `--enforce-lockfile` |
| Android SDK | command-line tools by SHA-256; platform 36, build-tools 36.0.0, NDK 28.2.13676358 by exact version |
| Gradle and its plugins | `distributionSha256Sum` in `gradle-wrapper.properties`; AGP, Kotlin and plugin versions fixed in `apps/gui/android/` |
| cargo-ndk | 4.1.2, built with `--locked` |
| Paths, user, locale, time zone, umask | fixed by the container: the source is always at `/build`, toolchains under `/opt`, `TZ=UTC`, `C.UTF-8`, `022` |
| Time | `SOURCE_DATE_EPOCH` = the commit's time; every entry of the tarball carries it |
| The tarball | names sorted, owner `0:0`, normalised modes, `gzip -n` (no name, no timestamp in the header) |

The image is built from the Dockerfile (and `apt-install`) of the commit
being built, never downloaded ready-made: verifying a release does not mean
trusting an image someone else built. The build script
(`reproducible/build.sh`) comes from the same commit.

## In the release workflow

`release.yml` builds the published Linux and Android files exactly this way
(`scripts/repro_build.sh` on a GitHub runner), and checks them before
publishing:

- **`linux`, `android`** build the files that get published.
- **`android`** then signs the APKs. The build itself never sees the release
  key: it signs with a throwaway debug key, then `apksigner` from the same
  image re-signs in a container with no network that holds only the APKs and
  the keystore, with `--alignment-preserved` (no entry moves) and v1 signing
  off.
- **`reproduce`** builds both targets a second time, on a different runner
  image (another kernel, Docker and disk).
- **`compare`** checks the published files against the second build (the
  tarball byte for byte, the APKs signature aside) and puts a table in the
  run's summary. **`release` needs `compare`:** a release whose two builds
  disagree is never published.

Manual runs of `release.yml` (Actions → release → *Run workflow*) run the same
jobs, so a change that breaks reproducibility shows up there before a tag.

## Build without verifying

To build the files yourself, from any commit:

```bash
scripts/repro_build.sh                          # HEAD, Linux and Android
scripts/repro_build.sh --ref v0.2.0 --target linux
```

They land in `dist/repro/<commit>/`. The APKs carry your container's debug
key: fine for a test install, not an update of a release install.

## Changing a pin

A tag can be reproduced only with the pins that tag carries, so a pin changes
on purpose, in its own commit:

- **Rust, Flutter:** `RUST_TOOLCHAIN` and `FLUTTER_VERSION` in
  `reproducible/Dockerfile`, `ci.yml`, `release.yml`, `scripts/build_linux.sh`
  and `scripts/build_windows.ps1`, together. Flutter also needs
  `FLUTTER_COMMIT`: `git ls-remote https://github.com/flutter/flutter
  refs/tags/<version>`.
- **System packages:** move `UBUNTU_SNAPSHOT` to a later date
  (`YYYYMMDDTHHMMSSZ`). A new base image digest needs a snapshot taken after
  that image was built (its `created` time), or apt meets packages newer than
  the snapshot's and stops.
- **Android SDK, NDK:** the `ARG`s in the Dockerfile; the NDK also in
  `apps/gui/android/app/build.gradle.kts` and `scripts/build_android.sh`.
- **Gradle:** `distributionUrl` and `distributionSha256Sum` together.

Then run *release* by hand on the branch: `compare` must stay green.

## What is not covered

- **macOS** builds need Xcode, which runs only on macOS and cannot be pinned
  in a container. The app is then signed and, once code signing is set up,
  notarized; Apple's notarization ticket is stapled into the app, so even a
  bit-identical build would differ by its signature. A future check can
  compare the app bundle with its signatures removed (`codesign
  --remove-signature`), built with the same Xcode version.
- **Windows** builds use MSVC, which writes timestamps and a random GUID into
  every executable unless `/Brepro` is passed throughout, and Inno Setup,
  whose installers are not deterministic. Not attempted yet.
- **The terminal client** (`templar`) is not published as a release file. It
  builds with `cargo build --locked --release -p templar-tui`, and the same
  container would make it reproducible if it ever is.
- **The toolchains themselves** are trusted as published (Ubuntu, the Rust
  project, Google, the Flutter team, Gradle): reproducibility proves the
  release matches its source given those tools, not that the tools are
  honest. Pinning means a compromised tool would have to be compromised in
  the pinned version, for everyone who rebuilds.
