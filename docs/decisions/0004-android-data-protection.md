# 0004 — Android: no app backup, secure screens for secrets

**Status:** accepted, in force.

## Context

Android's Auto Backup copies an app's private files to the cloud by default,
and the system can capture any screen for the recents view or a screenshot.
The wallet's private files include the encrypted vault, the registry and the
chain databases; some screens show recovery phrases and private keys.

## Decision

- `android:allowBackup="false"` in `apps/gui/android/app/src/main/AndroidManifest.xml`:
  the vault and the databases never leave the device through Auto Backup.
  The recovery phrase is the backup.
- Screens that show a recovery phrase or a private key are wrapped in
  `SecureScreen` (`apps/gui/lib/services/screen_security.dart`), which sets
  `FLAG_SECURE` through a method channel in `MainActivity.kt`: no
  screenshots, no recents thumbnail.

## Consequences

- Moving to a new phone means restoring from the recovery phrase.
- Desktop builds are unaffected.
