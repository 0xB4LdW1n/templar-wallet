# 0006 — Biometric unlock opens the vault; it does not confirm on Android

**Status:** accepted, in force.

## Context

Typing a long app password on a phone at every launch is what makes people
pick short ones. A fingerprint is convenient, but a sensor pass proves less
than the password: anyone who can make the phone accept a finger gets past
it.

## Decision

- **Unlock.** Enabling biometric unlock exports the raw vault key from the
  engine (`export_vault_key`) and seals it behind the sensor; the next launch
  reads it back and opens the vault with `unlock_vault_with_key`, skipping
  the password. On Android the key is kept by the vendored
  `biometric_storage` plugin (`apps/gui/packages/biometric_storage`) in a
  file the Keystore encrypts, with a class-3 biometric required for every
  decrypt; on macOS it is sealed to a Secure Enclave key (Touch ID).
  Enrolling a new fingerprint invalidates the key and switches the feature
  off. Details: `apps/gui/lib/services/biometric_unlock_service.dart`.
- **Confirmation gates.** On Android the password is still required to sign,
  to share wallet data and to reveal a recovery phrase. Only on macOS can
  Touch ID stand in at those gates.
- **The vault's key derivation is not weakened for phones.** New vaults use
  the same Argon2id parameters on every platform; biometric unlock is the
  answer to the slow unlock, not a cheaper KDF.

## Consequences

- A phone with biometric unlock on still asks for the password before any
  signature.
- Losing the enrolled fingerprints only costs the shortcut; the password
  still opens the vault.
