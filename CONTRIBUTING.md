# Contributing to Templar Wallet

How to set up a working tree and what every change must pass. What the
pieces are: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

Changes to the wallet engine (transaction building, signing, the vault,
Miniscript, the JSON methods) belong in
[templarlib](https://github.com/0xB4LdW1n/templarlib), not here.

## Set up

Until templarlib publishes its first tag, the manifests read it from a
sibling checkout named `templarlib`:

```bash
git clone https://github.com/0xB4LdW1n/templarlib.git
git clone https://github.com/0xB4LdW1n/TemplarWallet.git
cd TemplarWallet
```

Toolchains: Rust and Flutter at the versions `.github/workflows/ci.yml` pins
(`RUST_TOOLCHAIN`, `FLUTTER_VERSION`), with the `clippy` and `rustfmt`
components. On Linux, `libudev-dev` and `pkg-config` too. Per-platform
requirements: [`docs/build/`](docs/build/README.md).

Run the app during development:

```bash
cd apps/gui
flutter run -d macos          # or -d linux / -d windows / an Android device
```

On macOS the Xcode build compiles and bundles the Rust library by itself. On
Linux and Windows build it first (`cargo build --release -p wallet-ffi`) and
copy it beside the executable, as the platform guides show.

Run the terminal client without installing it:

```bash
cargo run -p templar-tui -- --help
cargo run -p templar-tui -- methods
```

The app and the terminal client cannot use the same data folder at once.
Point a scratch run elsewhere with `TEMPLAR_DATA_DIR` (or `--data-dir` for the
terminal client) to keep it away from your own test wallets.

## The gate

Every change passes exactly what CI runs. From the repository root:

```bash
cargo fmt --all -- --check
cargo clippy --locked --workspace --all-targets -- -D warnings
cargo test --locked --workspace
```

and in `apps/gui`:

```bash
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos --fatal-warnings
flutter test
```

The tree is kept at zero analyzer issues of any level. `--locked` and
`--enforce-lockfile` mean `Cargo.lock` and `pubspec.lock` decide every
dependency version: update them on purpose, in their own commit.

Until the library is consumed by tag, the GitHub workflows cannot build (they
check out this repository alone), so run the gate locally.

## Conventions

- **English** for code, comments, UI strings and public docs. The one
  exception is `INSTALL.it.md`.
- **Design.** Every screen follows [`design.md`](design.md); read it before
  changing a pixel. A phone layout goes behind `AppLayout.isPhone` and must
  leave the desktop tree unchanged
  ([decision 0005](docs/decisions/0005-mobile-shell.md)).
- **Brand rasters** are build products: edit `assets/brand/*.svg`, then run
  `./scripts/generate_icons.sh` (macOS).
- **Test networks only.** Nothing may add a mainnet path.
- **Frozen coins are never spent**, and a signature never happens without the
  user's confirmation: keep both properties in every new flow.
- **Docs.** Each file answers one question for one reader; `docs/README.md`
  is the index. A decision that shapes the code gets a record in
  `docs/decisions/`.
- **CI** runs on GitHub-hosted runners only. Never attach a self-hosted runner
  to this public repository.

## Licence

The repository is licensed under `MIT OR Apache-2.0`
([LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE)); the vendored
`apps/gui/packages/biometric_storage` keeps its MIT licence and the fonts
their OFL.

Security issues: not in a public issue — see [SECURITY.md](SECURITY.md).
