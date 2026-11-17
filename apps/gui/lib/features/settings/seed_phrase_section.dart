import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/banners.dart';
import '../../services/screen_security.dart';
import '../../shared/widgets/app_password_gate.dart' show BiometricGateButton;
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'settings_kit.dart';

/// The gate in front of every seed reveal: the app password, re-entered.
///
/// # Why the app password and not the per-wallet one
///
/// The per-wallet password is a hash in `shared_preferences` — it decides
/// which wallet the *UI* opens and protects nothing on disk, so anyone who can
/// edit that file walks past it. Worse, when no wallet password was set the
/// old gate degraded to a checkbox, which means a machine left unlocked for a
/// minute was one click away from showing a recovery phrase.
///
/// The app password is the key to the vault the seed is actually sealed with,
/// verified through Argon2id against a sealed verifier, and rate-limited in the
/// engine. There is no weaker path to the same secret, so the gate is worth
/// something. Verifying does *not* unlock a session: it proves the password
/// and drops the derived key.
///
/// # The 60-second grace
///
/// A user who views the words then immediately opens the private key is one
/// intent, not two, and a second prompt teaches password-typing as a reflex.
/// One window, short, process-lifetime only (never persisted).
class SeedRevealGate {
  static DateTime? _lastPassed;
  static const Duration _grace = Duration(seconds: 60);

  static bool get _inGrace {
    final t = _lastPassed;
    return t != null && DateTime.now().difference(t) < _grace;
  }

  /// Ask for the app password unless it was proven in the last minute.
  /// Returns true when the caller may go on to read secret material.
  static Future<bool> open(BuildContext context) async {
    if (_inGrace) return true;
    final ok = await showAppDialog<bool>(
      context,
      barrierDismissible: false,
      builder: (_) => const _AppPasswordGateDialog(),
    );
    if (ok != true) return false;
    _lastPassed = DateTime.now();
    return context.mounted;
  }

  /// Called when the vault is locked or the app backgrounds a reveal — the
  /// grace must not survive either.
  static void reset() => _lastPassed = null;
}

/// A clipboard that forgets.
///
/// Key material put on the clipboard is readable by every process on the
/// machine, by clipboard-history tools, and — on macOS — by the user's phone
/// via Universal Clipboard. Copying is still the *safest* way to move an xprv
/// (retyping 111 characters by hand is how the mistakes happen), so the fix is
/// not to forbid it but to bound how long it lasts.
///
/// The timer is static rather than owned by a dialog: closing the dialog must
/// not cancel the wipe, and must not perform it early either — the whole point
/// is that the user has a minute to paste somewhere else.
class SecretClipboard {
  SecretClipboard._();

  static Timer? _timer;
  static String? _pending;

  static const Duration ttl = Duration(seconds: 60);

  /// Copies [secret] and schedules a wipe [ttl] from now.
  static Future<void> copy(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    _pending = secret;
    _timer?.cancel();
    _timer = Timer(ttl, _wipe);
  }

  /// Clears the clipboard, but only if it still holds what we put there —
  /// wiping something the user copied afterwards would be a bug of its own.
  static Future<void> _wipe() async {
    final secret = _pending;
    _pending = null;
    _timer = null;
    if (secret == null) return;
    final current = await Clipboard.getData(Clipboard.kTextPlain);
    if (current?.text != secret) return;
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}

/// Settings → Security → Seed Phrase. Software wallets only.
///
/// View shows the words; Private key reveals the xprv. Both sit behind
/// [SeedRevealGate].
///
/// There is deliberately no Export. It only ever did `Clipboard.setData(seed)`,
/// which is the single worst place a recovery phrase can be put — every local
/// process can read it, clipboard managers keep history, and macOS syncs it to
/// the user's other devices. Writing the words down off the View dialog covers
/// the same need without leaving the machine.
class SeedPhraseCard extends StatelessWidget {
  const SeedPhraseCard({super.key, required this.walletId});

  final String walletId;

  Future<bool> _passGate(BuildContext context) => SeedRevealGate.open(context);

  /// Reveal the recovery phrase. The words are handed straight to the dialog
  /// and never stored on this widget — the shorter a secret lives in the Dart
  /// heap the better, since a Dart String cannot be zeroized.
  Future<void> _view(BuildContext context) async {
    if (!await _passGate(context) || !context.mounted) return;
    final List<String> words;
    try {
      words = await walletBridge.getMnemonic(walletId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load seed: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    await showAppDialog<void>(
      context,
      builder: (_) => _SeedWordsDialog(words: words),
    );
  }

  /// Reveal the raw extended private key (xprv) — gated, blurred until asked
  /// for, copy-only, no QR.
  Future<void> _viewPrivateKey(BuildContext context) async {
    if (!await _passGate(context) || !context.mounted) return;
    final String key;
    try {
      key = await walletBridge.getPrivateKey(walletId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load private key: $e')),
        );
      }
      return;
    }
    if (!context.mounted) return;
    await showAppDialog<void>(
      context,
      builder: (_) => _PrivateKeyDialog(privateKey: key),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Two tools that each open something behind the gate: two rows. The
    // warning goes under the group, where it can be read whole.
    return SettingsGroup(
      label: 'Recovery phrase',
      note:
          'Anyone with these words can spend your funds. Only use these '
          'tools in a private place.',
      children: [
        ListRow(
          icon: Icons.visibility_outlined,
          title: 'View',
          subtitle: 'Shows the words',
          chevron: true,
          onTap: () => _view(context),
        ),
        ListRow(
          icon: Icons.key_outlined,
          title: 'Private key',
          subtitle: "Reveals this wallet's xprv",
          chevron: true,
          onTap: () => _viewPrivateKey(context),
        ),
      ],
    );
  }
}

// ── Gates ─────────────────────────────────────────────────────────────────────

class _AppPasswordGateDialog extends StatefulWidget {
  const _AppPasswordGateDialog();

  @override
  State<_AppPasswordGateDialog> createState() => _AppPasswordGateDialogState();
}

class _AppPasswordGateDialogState extends State<_AppPasswordGateDialog> {
  final _ctrl = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_ctrl.text.isEmpty || _checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      await walletBridge.verifyVaultPassphrase(_ctrl.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // The engine's message already carries the useful part — attempts left,
      // or how long the gate is locked. Show it verbatim rather than flatten
      // every failure to "wrong password".
      setState(() {
        _checking = false;
        // Strip the transport's framing — "Exception: wallet-ffi: Wrong app
        // password" is the engine talking to a developer, not to the user.
        _error = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('wallet-ffi: ', '');
        _ctrl.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return PromptDialog(
      title: 'Enter your app password',
      icon: Icons.shield_outlined,
      // In a sheet the actions land in an end-aligned Wrap: full width, they
      // stack as bars instead of two right-hugging chips.
      actions: [
        GhostButton(
          label: 'Cancel',
          onPressed: _checking ? null : () => Navigator.of(context).pop(false),
          isFullWidth: phone,
        ),
        PrimaryButton(
          label: 'Continue',
          isLoading: _checking,
          onPressed: _checking ? null : _submit,
          isFullWidth: phone,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This is the password that encrypts wallet storage — the same one '
            'you enter when Templar starts. You are about to reveal secret key '
            'material.',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          PasswordField(
            controller: _ctrl,
            autofocus: true,
            errorText: _error,
            onSubmitted: _submit,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          // The Mac's sensor, where the user has it standing in for the
          // password at confirmation gates (Settings › Security).
          BiometricGateButton(
            reason: 'reveal secret key material',
            onConfirmed: () => Navigator.of(context).pop(true),
            onMessage: (m) => setState(() => _error = m),
            fullWidth: phone,
          ),
        ],
      ),
    );
  }
}

// ── View ──────────────────────────────────────────────────────────────────────

class _SeedWordsDialog extends StatefulWidget {
  const _SeedWordsDialog({required this.words});
  final List<String> words;

  @override
  State<_SeedWordsDialog> createState() => _SeedWordsDialogState();
}

class _SeedWordsDialogState extends State<_SeedWordsDialog> {
  @override
  void dispose() {
    // Best effort: drop the references the moment the dialog closes so the
    // list stops pinning the words. Dart Strings are immutable and GC-managed,
    // so this shortens their lifetime — it cannot wipe them.
    widget.words.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    // Phone: two columns; desktop: three. Aligned cells, numbered in their
    // own fixed column, because the one thing this dialog is for is copying
    // a phrase onto paper in order.
    final columns = phone ? 2 : 3;

    return AppDialog(
      title: const Text('Seed phrase'),
      content: SecureScreen(
        child: SizedBox(
          width: phone ? double.infinity : 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const WarningBanner(
                message:
                    'Anyone with these words can spend your funds. Write them '
                    'down in a private place.',
              ),
              const SizedBox(height: AppSpacing.lg),
              LayoutBuilder(
                builder: (context, c) {
                  // Floored: the cells plus the gaps must never round up past
                  // the line, or the grid loses a column.
                  final cell =
                      ((c.maxWidth - AppSpacing.sm * (columns - 1)) / columns)
                          .floorToDouble();
                  return Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (var i = 0; i < widget.words.length; i++)
                        SizedBox(
                          width: cell,
                          child: _WordWell(index: i, word: widget.words[i]),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
          isFullWidth: phone,
        ),
      ],
    );
  }
}

/// One word of the phrase: its number right-aligned in a fixed column so
/// `1.` and `24.` line up, then the word in mono.
class _WordWell extends StatelessWidget {
  const _WordWell({required this.index, required this.word});
  final int index;
  final String word;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: s.edge),
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppSpacing.xl,
            child: Text(
              '${index + 1}.',
              textAlign: TextAlign.right,
              style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            // Never ellipsised: a clipped word is a wrong backup.
            child: Text(word, style: AppTypography.mono.copyWith(color: s.ink)),
          ),
        ],
      ),
    );
  }
}

// ── Private key ─────────────────────────────────────────────────────────────

/// The xprv reveal.
///
/// Three rules, all aimed at the same failure — a key that gets copied wrong
/// or seen by the wrong person:
///
///   * blurred until asked for, so opening the dialog on a shared screen does
///     not itself leak the key;
///   * copy-only. A 111-character key transcribed by hand is the mistake; the
///     dialog never encourages it. The paste is confirmed by showing the first
///     and last six characters, which is what you check on the far side;
///   * the clipboard is wiped a minute later (see [SecretClipboard]).
class _PrivateKeyDialog extends StatefulWidget {
  const _PrivateKeyDialog({required this.privateKey});
  final String privateKey;

  @override
  State<_PrivateKeyDialog> createState() => _PrivateKeyDialogState();
}

class _PrivateKeyDialogState extends State<_PrivateKeyDialog> {
  bool _revealed = false;
  bool _copied = false;

  String get _head => widget.privateKey.length >= 6
      ? widget.privateKey.substring(0, 6)
      : widget.privateKey;

  String get _tail => widget.privateKey.length >= 6
      ? widget.privateKey.substring(widget.privateKey.length - 6)
      : widget.privateKey;

  Future<void> _copy() async {
    await SecretClipboard.copy(widget.privateKey);
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return AppDialog(
      title: const Text('Private key'),
      content: SecureScreen(
        child: SizedBox(
          width: phone ? double.infinity : 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const WarningBanner(
                message:
                    'Anyone with this key controls every coin in this wallet. '
                    'Never share it or paste it online.',
              ),
              const SizedBox(height: AppSpacing.lg),
              _KeyWell(
                value: widget.privateKey,
                revealed: _revealed,
                onReveal: () => setState(() => _revealed = true),
              ),
              const SizedBox(height: AppSpacing.md),
              // Phone: beside the button the check-the-paste line gets about
              // 150 dp and wraps to four ragged lines. Stacked, the button is a
              // full-width bar and the line reads across the sheet.
              if (phone) ...[
                SecondaryButton(
                  label: _copied ? 'Copied' : 'Copy key',
                  icon: _copied ? Icons.check_outlined : Icons.copy_outlined,
                  onPressed: _copy,
                  isFullWidth: true,
                ),
                if (_copied) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Check the paste starts $_head… and ends …$_tail. '
                    'The clipboard clears in ${SecretClipboard.ttl.inSeconds}s.',
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ],
              ] else
                Row(
                  children: [
                    SecondaryButton(
                      label: _copied ? 'Copied' : 'Copy key',
                      icon: _copied
                          ? Icons.check_outlined
                          : Icons.copy_outlined,
                      onPressed: _copy,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    if (_copied)
                      Expanded(
                        child: Text(
                          'Check the paste starts $_head… and ends …$_tail. '
                          'The clipboard clears in ${SecretClipboard.ttl.inSeconds}s.',
                          style: AppTypography.caption.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
      actions: [
        GhostButton(
          label: 'Done',
          onPressed: () => Navigator.of(context).pop(),
          isFullWidth: phone,
        ),
      ],
    );
  }
}

/// The key itself, blurred until [onReveal].
class _KeyWell extends StatelessWidget {
  const _KeyWell({
    required this.value,
    required this.revealed,
    required this.onReveal,
  });

  final String value;
  final bool revealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final text = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: SelectableText(
        value,
        style: AppTypography.monoSmall.copyWith(color: s.ink),
        maxLines: 3,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Extended private key (xprv)',
          style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: s.well,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: s.edge),
          ),
          clipBehavior: Clip.antiAlias,
          child: revealed
              ? text
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    // The real string is laid out underneath so the well does
                    // not resize on reveal — only its legibility changes. The
                    // blur is a privacy mask over a secret, not decoration.
                    ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                      child: IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            value,
                            style: AppTypography.monoSmall.copyWith(
                              color: s.ink,
                            ),
                            maxLines: 3,
                          ),
                        ),
                      ),
                    ),
                    SecondaryButton(
                      label: 'Reveal',
                      icon: Icons.visibility_outlined,
                      onPressed: onReveal,
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
