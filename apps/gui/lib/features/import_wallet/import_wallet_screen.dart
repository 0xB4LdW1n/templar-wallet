import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/choice_list.dart';
import '../../shared/widgets/page_header.dart';
import '../vault/vault_setup_sheet.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../shared/widgets/app_dialog.dart';

class ImportWalletScreen extends StatefulWidget {
  const ImportWalletScreen({super.key});

  @override
  State<ImportWalletScreen> createState() => _ImportWalletScreenState();
}

class _ImportWalletScreenState extends State<ImportWalletScreen> {
  final _bridge = walletBridge;
  final _mnemonicController = TextEditingController();
  final _nameController = TextEditingController(text: 'Restored Wallet');
  bool _importing = false;
  String? _error;

  /// Restore used to hard-code Bitcoin-only, which left the recovered wallet
  /// with no Liquid descriptor: no Liquid section, no LBTC address in
  /// Receive, no CT descriptor in Wallet info. The same seed derives both
  /// chains, so the question is asked here exactly as the creation wizard
  /// asks it — and defaults the same way.
  bool _liquidEnabled = true;

  List<String> get _words => _mnemonicController.text
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  bool get _validWordCount => _words.length == 12 || _words.length == 24;

  bool get _canImport =>
      _validWordCount && _nameController.text.trim().isNotEmpty && !_importing;

  @override
  void dispose() {
    _mnemonicController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  /// A2 — a restored phrase is written to wallet storage, so encryption has to
  /// exist before the import, not as an afterthought. This screen is outside
  /// the new-wallet wizard (which has its own mandatory password step), so it
  /// asks here; the backend refuses the import either way, and a refusal after
  /// the user typed 24 words is a worse way to learn it. Returns false when the
  /// user backs out of the dialog.
  Future<bool> _ensureEncryption() async {
    try {
      if ((await _bridge.vaultStatus()).initialized) return true;
    } catch (_) {
      // Bridge unavailable — let the import itself surface the real error.
      return true;
    }
    if (!mounted) return false;
    final created = await showAppDialog<bool>(
      context,
      barrierDismissible: false,
      builder: (_) => const VaultSetupSheet(),
    );
    return created == true;
  }

  Future<void> _import() async {
    final words = _words;
    final name = _nameController.text.trim();
    setState(() {
      _importing = true;
      _error = null;
    });
    if (!await _ensureEncryption()) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error =
              'Set an app password first — Templar will not store a '
              'recovery phrase on this device unencrypted.';
        });
      }
      return;
    }
    if (!mounted) return;
    try {
      final walletId = await _bridge.createWallet(
        name,
        words,
        liquid: _liquidEnabled,
      );
      if (mounted) {
        context.read<AppState>().setActiveWallet(
          walletId,
          name: name,
          type: 'Software',
          liquid: _liquidEnabled,
        );
        context.go(AppRoutes.dashboard);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _error = e.toString().replaceFirst('Exception: wallet-ffi: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final wordCount = _words.length;

    // Android back: leave to the picker like the on-screen Cancel does,
    // instead of exiting the app with the typed words lost.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go(AppRoutes.walletPicker);
      },
      child: Scaffold(
        backgroundColor: s.canvas,
        // Edge-to-edge on mobile: the title must clear the status bar.
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth:
                    AppSpacing.formMaxWidth +
                    2 * AppSpacing.pagePadding(context),
              ),
              child: ListView(
                padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
                children: [
                  PageHeader(
                    title: 'Restore wallet',
                    actions: [
                      GhostButton(
                        label: 'Cancel',
                        onPressed: () => context.go(AppRoutes.walletPicker),
                      ),
                    ],
                  ),
                  const WarningBanner(
                    title: 'Keep your seed phrase private',
                    message:
                        'Never enter your seed phrase on an untrusted device or '
                        'application. Templar stores it encrypted with your app '
                        'password — it is never written to disk in the clear.',
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Recovery phrase ──────────────────────────────────
                  const _FieldLabel('Recovery phrase'),
                  TextField(
                    controller: _mnemonicController,
                    minLines: 4,
                    maxLines: 6,
                    // Seed words must never reach the keyboard's
                    // autocorrect or personal dictionary.
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    style: AppTypography.mono.copyWith(color: s.ink),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    '12 or 24 words, separated by spaces',
                    style: AppTypography.caption.copyWith(color: s.inkFaint),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _WordCount(count: wordCount, valid: _validWordCount),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Name ─────────────────────────────────────────────
                  const _FieldLabel('Wallet name'),
                  TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Coins ────────────────────────────────────────────
                  const _FieldLabel('Coins'),
                  ChoiceList<bool>(
                    options: const [
                      ChoiceListOption(
                        value: false,
                        label: 'Bitcoin only',
                        icon: Icons.currency_bitcoin,
                      ),
                      ChoiceListOption(
                        value: true,
                        label: 'Bitcoin + Liquid',
                        icon: Icons.water_drop_outlined,
                      ),
                    ],
                    selected: _liquidEnabled,
                    onChanged: (v) => setState(() => _liquidEnabled = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Both chains come from the same phrase. With Bitcoin only '
                    'the Liquid section stays hidden; you can turn it on later '
                    'from Wallet info.',
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    DangerBanner(message: _error!),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (_importing)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Restoring wallet…',
                            style: AppTypography.body.copyWith(
                              color: s.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    // The screen's one action. Cancel is in the header (and
                    // Android back goes to the same place), so it is not
                    // repeated down here.
                    Align(
                      alignment: Alignment.centerRight,
                      child: PrimaryButton(
                        label: 'Restore wallet',
                        isFullWidth: phone,
                        onPressed: _canImport ? _import : null,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A field's label: an eyebrow above it, never floating inside.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
      ),
    );
  }
}

/// The phrase's word count as it is typed: a 6 px dot and a few words. A
/// count of 12 or 24 is only a count — whether the words are a valid phrase
/// is the engine's answer, on Restore.
class _WordCount extends StatelessWidget {
  const _WordCount({required this.count, required this.valid});

  final int count;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final words = '$count word${count == 1 ? '' : 's'}';
    final (Color dot, String text) = count == 0
        ? (s.inkFaint, 'No words yet')
        : valid
        ? (s.success, words)
        : (s.warning, '$words — a phrase has 12 or 24');
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dot,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          text,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );
  }
}
