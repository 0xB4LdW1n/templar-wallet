# wallet-ffi

Thin C ABI adapter between the Flutter app (`apps/gui`) and
[templarlib](https://github.com/0xB4LdW1n/templarlib). Builds
`libwallet_ffi.dylib` / `libwallet_ffi.so` / `wallet_ffi.dll`.

It exports `wallet_call`, `wallet_free_string` and `wallet_set_data_dir`.
Wallet state, DTOs, dispatch and workflows belong to templarlib; this crate
only owns C-string conversion, panic containment and zeroizing the strings
that cross it. The boundary is described in
[`docs/ARCHITECTURE.md`](../../docs/ARCHITECTURE.md#the-ffi-boundary).

Until templarlib's first tag the dependency is a path to a sibling checkout
(`../templarlib` next to this repository); see the TODO in `Cargo.toml`.

| Feature | Default | Effect |
|---|---|---|
| templarlib `protocol` | always on | Templar Protocol connector methods |
| `hardware` | on | USB hardware wallets (`templarlib/hardware`); off on Android, where hardware methods answer `HW_UNSUPPORTED` |

```bash
cargo build --release -p wallet-ffi                        # desktop
cargo build --release -p wallet-ffi --no-default-features  # no USB stack
```

Android builds go through `scripts/build_android.sh`
([`docs/build/AndroidBuild.md`](../../docs/build/AndroidBuild.md)).
