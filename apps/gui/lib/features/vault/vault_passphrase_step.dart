import 'package:flutter/material.dart';

import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Strength score for a vault password: 0 (empty/too short) to 4 (strong).
/// Length is weighted over character variety — a long phrase of plain words
/// beats a short one with symbols.
int passphraseStrength(String p) {
  if (p.length < 8) return p.isEmpty ? 0 : 1;
  var classes = 0;
  if (RegExp(r'[a-z]').hasMatch(p)) classes++;
  if (RegExp(r'[A-Z]').hasMatch(p)) classes++;
  if (RegExp(r'[0-9]').hasMatch(p)) classes++;
  if (RegExp(r'[^a-zA-Z0-9]').hasMatch(p)) classes++;
  var score = 1;
  if (p.length >= 12 || classes >= 3) score++;
  if (p.length >= 12 && classes >= 3) score++;
  if (p.length >= 16 && classes >= 3 || p.length >= 20) score++;
  return score;
}

/// Body of the wizard's app-password step.
///
/// # Why this screen never says "passphrase"
///
/// In Bitcoin, *passphrase* already means the BIP39 25th word — a secret that
/// changes which wallet a seed derives. Asking a hardware-wallet user to "set a
/// passphrase" reads as "type your device's BIP39 passphrase", which is a
/// different secret, entered on a different machine, with different
/// consequences. Everything here is worded as an **app password** instead.
///
/// # Why the copy changes with the wallet type
///
/// The vault seals the whole wallet registry, so what it buys depends on what
/// is in there:
///
///   * **Software wallet** — the registry holds the recovery phrase. Without a
///     password it is readable on disk. Seed secrecy is the point.
///   * **Hardware, air-gap or watch-only** — no key of any kind is stored; the
///     device keeps it. The registry holds descriptors and public keys, so the
///     password buys privacy (an xpub is your whole transaction history) and
///     integrity (a rewritten descriptor makes the app display someone else's
///     receive addresses). Warning a QR/air-gap user about their seed sitting
///     in plain text is simply false, and false security copy is worse than
///     none — it teaches the user to discount the warnings that are true.
///
/// # Why the seed case cannot be skipped
///
/// That same split decides whether the step is optional (A2). When the seed
/// lands on this disk, "skip" means every mnemonic sits in a readable file, and
/// the whole security model reduces to a checkbox a tester clicks past — so the
/// opt-out is not offered, and the backend refuses to store the seed anyway.
/// Where the key stays on a device, the password buys privacy and integrity but
/// no seed secrecy, so skipping it stays the user's call.
class VaultPassphraseStep extends StatelessWidget {
  const VaultPassphraseStep({
    super.key,
    required this.passCtrl,
    required this.confirmCtrl,
    required this.declined,
    required this.done,
    required this.error,
    required this.seedOnDisk,
    required this.onChanged,
    required this.onDeclinedChanged,
    required this.onSubmitted,
  });

  final TextEditingController passCtrl;
  final TextEditingController confirmCtrl;
  final bool declined;

  /// The vault was already created on this pass through the wizard
  /// (user came Back from the setup phase).
  final bool done;
  final String? error;

  /// Whether the wallet being created keeps its signing key on this device.
  /// False for hardware, air-gap and watch-only — where the seed never touches
  /// the disk and seed-loss copy would be a lie.
  final bool seedOnDisk;

  /// A seed on this disk makes encryption mandatory (A2): there is no skip
  /// link, and `create_wallet` in the backend refuses without a vault.
  bool get mandatory => seedOnDisk;

  final VoidCallback onChanged;
  final ValueChanged<bool> onDeclinedChanged;
  final VoidCallback onSubmitted;

  /// Where the wallet file lives, named as the reader would name it: never
  /// "this computer" on a phone (design.md).
  static String _place(BuildContext context) =>
      AppLayout.isPhone(context) ? 'this device' : 'this computer';

  /// What encryption is actually protecting, in this wallet's case.
  String _rationale(String place) => seedOnDisk
      ? 'This wallet\'s recovery phrase is saved on $place. A password '
            'encrypts it (Argon2id + XChaCha20-Poly1305) so it cannot be read '
            'from your disk, your backups, or by another program running as you.'
      : 'Your signing key stays on your device — Templar never sees it, and this '
            'password does not change that. What it protects is the wallet file '
            'on $place, which holds your account descriptors and public '
            'keys: encrypted, they cannot be read (an xpub reveals your whole '
            'transaction history) or altered (a swapped descriptor would make '
            'Templar show you someone else\'s receive addresses).';

  /// What losing the password costs — very different with keys on a device.
  String get _lossWarning => seedOnDisk
      ? 'If you lose this password, Templar cannot open these wallets. Only your '
            'written recovery phrase can bring them back — so write it down in '
            'the next step and keep it somewhere safe.'
      : 'If you lose this password, Templar cannot open these wallets. Your coins '
            'stay safe on your device: import it again to get the wallet back.';

  /// Only reachable where the key lives on a device — with a seed on this disk
  /// the step is [mandatory] and there is nothing to decline.
  String get _declineWarning =>
      'Without a password, the wallet file is stored unencrypted. Your keys '
      'stay on your device either way, but anyone who can read your files '
      'sees your full balance and history — and anyone who can *edit* them '
      'can change which addresses Templar shows you. You can turn encryption '
      'on later in Settings.';

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    if (done) {
      return _StatusNote(
        icon: Icons.verified_user_outlined,
        color: s.success,
        text:
            'Wallet storage is now encrypted. Templar will ask for this '
            'password each time it starts.',
      );
    }

    final place = _place(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _rationale(place),
          style: AppTypography.body.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is a password for the app on $place — not the BIP39 '
          'passphrase of a hardware wallet, and not part of your recovery '
          'phrase.',
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (!declined || mandatory) ...[
          PasswordField(
            controller: passCtrl,
            label: 'App password',
            autofocus: true,
            onChanged: (_) => onChanged(),
          ),
          const SizedBox(height: AppSpacing.sm),
          PassphraseStrengthMeter(strength: passphraseStrength(passCtrl.text)),
          const SizedBox(height: AppSpacing.lg),
          PasswordField(
            controller: confirmCtrl,
            label: 'Confirm password',
            errorText: error,
            onChanged: (_) => onChanged(),
            onSubmitted: onSubmitted,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (seedOnDisk)
            DangerBanner(message: _lossWarning)
          else
            WarningBanner(message: _lossWarning),
        ] else
          WarningBanner(message: _declineWarning),
        const SizedBox(height: AppSpacing.md),
        // No skip where the seed lands on this disk (A2): unencrypted, the
        // recovery phrase is a readable file and every other protection in the
        // app is decoration. Elsewhere the key is on a device, so the choice is
        // genuinely the user's.
        if (mandatory)
          Text(
            'Required for a wallet whose recovery phrase is kept on $place. '
            'One password covers every wallet in Templar.',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          )
        else
          GhostButton(
            label: declined
                ? 'Actually, I want a password'
                : 'Skip — don\'t encrypt wallet storage',
            onPressed: () => onDeclinedChanged(!declined),
          ),
      ],
    );
  }
}

/// A finished state, drawn like a banner: the raised surface, a 16 px glyph
/// in the status colour, the words in ink. The kit has no success banner.
class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: AppSpacing.iconSmall, color: color),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// How strong a vault password is (0..4 from [passphraseStrength]): a 2 px
/// neutral meter and one word. Neutral because a red-to-green bar turns a
/// hint into a verdict the engine never gave.
class PassphraseStrengthMeter extends StatelessWidget {
  const PassphraseStrengthMeter({super.key, required this.strength});

  /// 0..4 from [passphraseStrength].
  final int strength;

  static const _labels = ['', 'Weak', 'Fair', 'Good', 'Strong'];

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      children: [
        Expanded(
          child: ClipRect(
            child: Stack(
              children: [
                Container(height: 2, color: s.edge),
                FractionallySizedBox(
                  widthFactor: strength / 4,
                  child: Container(height: 2, color: s.inkSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: AppSpacing.xxxl,
          child: Text(
            _labels[strength],
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ),
      ],
    );
  }
}
