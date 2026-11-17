import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'vault_passphrase_step.dart';
import 'vault_unlock_screen.dart';

/// Startup gate for an install that is still holding recovery phrases in
/// cleartext.
///
/// # Why this blocks instead of nagging
///
/// The engine refuses to *write* a new seed without a vault, but that check
/// runs at wallet creation and can do nothing about phrases an earlier build
/// already wrote: those installs keep a readable `registry.json` forever. A
/// banner would leave the decision with the user, and the decision is between
/// "encrypted" and "every mnemonic on this disk is a plain string" — that is
/// not a preference, and there is no version of using the wallet meanwhile
/// that is safe. So the app does not open until it is done.
///
/// Setting the passphrase migrates the existing wallets into the sealed store
/// and shreds the plaintext file and its backups, so nothing is lost and
/// nothing readable is left behind. What Templar cannot reach is a copy made
/// before now — a Time Machine snapshot, a synced folder — which is why the
/// screen says so rather than implying the exposure is undone.
class VaultMigrationScreen extends StatefulWidget {
  const VaultMigrationScreen({
    super.key,
    required this.seedWalletCount,
    required this.onMigrated,
  });

  /// How many wallets currently have a phrase in the clear.
  final int seedWalletCount;
  final VoidCallback onMigrated;

  @override
  State<VaultMigrationScreen> createState() => _VaultMigrationScreenState();
}

class _VaultMigrationScreenState extends State<VaultMigrationScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final p = _passCtrl.text;
    if (p.length < 8) {
      setState(() => _error = 'Use at least 8 characters');
      return;
    }
    if (p != _confirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await walletBridge.setupVault(p);
      if (!mounted) return;
      widget.onMigrated();
    } catch (e) {
      if (!mounted) return;
      // `setup` rolls back on failure, so the install is exactly as it was —
      // say that, or the user assumes a half-encrypted registry.
      setState(() {
        _busy = false;
        _error = 'Encryption failed, nothing was changed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final n = widget.seedWalletCount;
    final plural = n == 1 ? 'wallet' : 'wallets';
    final place = Platform.isAndroid ? 'device' : 'computer';

    return Scaffold(
      backgroundColor: s.canvas,
      // SafeArea: edge-to-edge on Android draws under the system bars.
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    kVaultColumnWidth + 2 * AppSpacing.pagePadding(context),
              ),
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const VaultBrandLine(),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      'Encrypt your wallets to continue',
                      style: AppTypography.displayTitleOf(
                        context,
                      ).copyWith(color: s.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'This copy of Templar was set up before storage encryption '
                      'was required, so the recovery phrase of $n $plural is '
                      'saved on this $place as readable text — any program '
                      'running as you can read it.\n\n'
                      'Setting an app password now encrypts them (Argon2id + '
                      'XChaCha20-Poly1305) and deletes the readable copy. '
                      'Nothing is lost and no wallet changes.',
                      style: AppTypography.body.copyWith(color: s.inkSecondary),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const WarningBanner(
                      message:
                          'A backup taken before today — Time Machine, a synced '
                          'folder, an old disk image — still holds the readable '
                          'file. Treat these phrases as exposed and move the '
                          'funds to a fresh wallet if they ever hold anything '
                          'you care about.',
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const WarningBanner(
                      message:
                          'If you lose this password, Templar cannot open these '
                          'wallets. Only your written recovery phrases can bring '
                          'them back.',
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _PasswordField(
                      controller: _passCtrl,
                      label: 'App password',
                      autofocus: true,
                      enabled: !_busy,
                      onChanged: () => setState(() => _error = null),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PassphraseStrengthMeter(
                      strength: passphraseStrength(_passCtrl.text),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _PasswordField(
                      controller: _confirmCtrl,
                      label: 'Confirm password',
                      enabled: !_busy,
                      errorText: _error,
                      onChanged: () => setState(() => _error = null),
                      onSubmitted: _submit,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    // Argon2id at 256 MiB takes a moment; the label says what
                    // is happening or it reads as a hang.
                    PrimaryButton(
                      label: _busy ? 'Encrypting…' : 'Encrypt and continue',
                      isFullWidth: true,
                      isLoading: _busy,
                      onPressed: _busy ? null : _submit,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'One password covers every wallet in Templar. You will be '
                      'asked for it each time the app starts.',
                      style: AppTypography.caption.copyWith(color: s.inkFaint),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A password field that can be switched off while encryption runs — the
/// kit's field has no `enabled`, and a second submit mid-Argon2 must not
/// reach the engine. Label above as an eyebrow, show/hide at its end, the
/// theme's neutral focus and danger error.
class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.autofocus = false,
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;
  final bool autofocus;
  final String? errorText;
  final VoidCallback onChanged;
  final VoidCallback? onSubmitted;

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final submit = widget.onSubmitted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(
          label: widget.label,
          child: TextField(
            controller: widget.controller,
            obscureText: _obscure,
            autofocus: widget.autofocus,
            enabled: widget.enabled,
            keyboardType: TextInputType.visiblePassword,
            style: AppTypography.bodyOf(context).copyWith(color: s.ink),
            onChanged: (_) => widget.onChanged(),
            onSubmitted: submit == null ? null : (_) => submit(),
            decoration: InputDecoration(
              errorText: widget.errorText,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: phone ? 20 : AppSpacing.icon,
                  color: s.inkSecondary,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
                tooltip: _obscure ? 'Show' : 'Hide',
              ),
            ),
          ),
        ),
      ],
    );
  }
}
