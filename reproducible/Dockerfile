# The build environment of the reproducible Templar Wallet builds: the Linux
# x64 bundle and the Android APKs. The release workflow builds those files in
# this image, and anyone can rebuild them from the same tag in the same image
# and compare (scripts/repro_build.sh, scripts/repro_verify.sh,
# docs/build/REPRODUCIBLE.md).
#
# Every input is pinned, so building this file again later gives the same
# toolchain:
#   - the base image by digest;
#   - apt packages through a fixed snapshot of the Ubuntu archive;
#   - rustup-init, the Android command-line tools by SHA-256;
#   - Rust, Flutter, the Android SDK packages and cargo-ndk by exact version
#     (Flutter also by commit). Each of those downloads is checked by its own
#     tool against hashes it fetched over TLS.
# Change a pin only on purpose: a release can be reproduced only with the
# image its tag carries.
#
# Two targets:
#   docker build --platform linux/amd64 --target linux   -f reproducible/Dockerfile reproducible
#   docker build --platform linux/amd64 --target android -f reproducible/Dockerfile reproducible
# The build context is unused; the source never enters the image (it is fed
# to the container at run time, see scripts/repro_build.sh).
#
# Keep RUST_TOOLCHAIN and FLUTTER_VERSION in step with ci.yml and release.yml,
# and NDK_VERSION with apps/gui/android/app/build.gradle.kts and
# scripts/build_android.sh.

# Ubuntu 22.04 (glibc 2.35): the Linux bundle runs on Ubuntu 22.04+, Debian 12+.
# This image was built on 2026-11-10T08:08Z.
FROM ubuntu:22.04@sha256:74b12b11ffa550fba1929ad4d8d16533c34f6612728469671afba1b03b66881c AS base

# Must be later than the base image's build time: an older snapshot can hold
# older versions of packages the image already has, and apt cannot downgrade
# them (it fails on perl-base, for one).
ARG UBUNTU_SNAPSHOT=20261111T000000Z
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=UTC

# apt reads a frozen snapshot of the Ubuntu archive. Check-Valid-Until is off
# because a snapshot's Release files expire; their signatures are still
# checked. The snapshot service is slow and answers 503 at times: apt retries. The very first update runs before ca-certificates exists, so TLS
# peer verification is off for it alone: what apt installs is still checked
# against the signed InRelease of the snapshot.
RUN set -eux; \
    printf '%s\n' \
      "deb https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT} jammy main universe" \
      "deb https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT} jammy-updates main universe" \
      "deb https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT} jammy-security main universe" \
      > /etc/apt/sources.list; \
    rm -f /etc/apt/sources.list.d/*; \
    printf '%s\n' 'Acquire::Check-Valid-Until "false";' 'Acquire::Retries "10";' \
      > /etc/apt/apt.conf.d/99snapshot; \
    apt-get -o Acquire::https::Verify-Peer=false update; \
    apt-get -o Acquire::https::Verify-Peer=false install -y --no-install-recommends ca-certificates; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      binutils build-essential clang cmake curl file git libgtk-3-dev \
      liblzma-dev libstdc++-12-dev libudev-dev ninja-build pkg-config python3 \
      unzip xz-utils zip; \
    rm -rf /var/lib/apt/lists/*

# Rust: rustup-init by checksum, then the pinned toolchain (rustup checks
# every component against the signed channel manifest's hashes).
ARG RUSTUP_VERSION=1.29.3
ARG RUSTUP_SHA256=b1c8cb14e30889e7e2999e6b69e62d9e9b9ffc0f4df8180564d306d9680e6c55
ARG RUST_TOOLCHAIN=1.95.0
ENV RUSTUP_HOME=/opt/rustup \
    CARGO_HOME=/opt/cargo \
    PATH=/opt/cargo/bin:$PATH
RUN set -eux; \
    curl -fsSLo /tmp/rustup-init "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init"; \
    echo "${RUSTUP_SHA256}  /tmp/rustup-init" | sha256sum -c -; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "${RUST_TOOLCHAIN}"; \
    rm /tmp/rustup-init; \
    rustc --version

# Flutter: the release tag, checked against its commit. The SDK fetches the
# Dart SDK and engine artifacts of exactly that commit on first use.
ARG FLUTTER_VERSION=3.44.1
ARG FLUTTER_COMMIT=924134a44c189315be2148659913dda1671cbe99
ENV FLUTTER_ROOT=/opt/flutter \
    PUB_CACHE=/opt/pub-cache \
    PATH=/opt/flutter/bin:$PATH \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    CI=true
RUN set -eux; \
    git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter; \
    test "$(git -C /opt/flutter rev-parse HEAD)" = "${FLUTTER_COMMIT}"; \
    git config --system --add safe.directory /opt/flutter; \
    flutter config --no-analytics; \
    dart --disable-analytics; \
    flutter --version

# ── Linux x64 bundle ────────────────────────────────────────────────────────
FROM base AS linux
RUN flutter precache --linux --no-android --no-ios --no-web --no-macos --no-windows --no-fuchsia
WORKDIR /build

# ── Android APKs ────────────────────────────────────────────────────────────
FROM base AS android

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends openjdk-17-jdk-headless; \
    rm -rf /var/lib/apt/lists/*
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Android command-line tools (Google publishes a SHA-1, which matches this
# SHA-256's file), then the SDK packages by exact version; sdkmanager checks
# each archive against Google's repository manifest.
ARG ANDROID_CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8
ARG ANDROID_PLATFORM=android-36
ARG ANDROID_BUILD_TOOLS=36.0.0
ARG NDK_VERSION=28.2.13676358
ENV ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_NDK_HOME=/opt/android-sdk/ndk/28.2.13676358 \
    ANDROID_NDK_ROOT=/opt/android-sdk/ndk/28.2.13676358 \
    GRADLE_USER_HOME=/opt/gradle
ENV PATH=/opt/android-sdk/cmdline-tools/latest/bin:$PATH
RUN set -eux; \
    curl -fsSLo /tmp/clt.zip "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS}"; \
    echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/clt.zip" | sha256sum -c -; \
    mkdir -p /opt/android-sdk/cmdline-tools; \
    unzip -q /tmp/clt.zip -d /opt/android-sdk/cmdline-tools; \
    mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest; \
    rm /tmp/clt.zip; \
    yes | sdkmanager --licenses > /dev/null; \
    sdkmanager --install \
      "platforms;${ANDROID_PLATFORM}" \
      "build-tools;${ANDROID_BUILD_TOOLS}" \
      "ndk;${NDK_VERSION}" > /dev/null; \
    test -d "/opt/android-sdk/ndk/${NDK_VERSION}"; \
    flutter config --android-sdk /opt/android-sdk; \
    flutter precache --android --no-linux --no-ios --no-web --no-macos --no-windows --no-fuchsia

# cargo-ndk drives the NDK's clang for each ABI.
ARG CARGO_NDK_VERSION=4.1.2
RUN set -eux; \
    rustup target add aarch64-linux-android x86_64-linux-android; \
    cargo install --locked cargo-ndk --version "${CARGO_NDK_VERSION}"; \
    rm -rf /opt/cargo/registry /opt/cargo/git
WORKDIR /build
