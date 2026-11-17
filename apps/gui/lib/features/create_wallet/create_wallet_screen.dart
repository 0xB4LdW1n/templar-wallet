import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/step_flow_scaffold.dart';
import '../../shared/widgets/step_header.dart';
import '../../shared/widgets/wallet_created_view.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../services/screen_security.dart';
import '../../theme/app_typography.dart';
import 'models/new_wallet_draft.dart';

class CreateWalletScreen extends StatefulWidget {
  const CreateWalletScreen({super.key, this.baseStep = 0, this.onBackToWizard});

  /// Questions already answered by the wizard hosting this setup —
  /// the step counter continues from here instead of restarting at 1.
  final int baseStep;

  /// Back from the first step: return to the wizard's last question.
  /// Null (standalone route) falls back to navigating there.
  final VoidCallback? onBackToWizard;

  @override
  State<CreateWalletScreen> createState() => _CreateWalletScreenState();
}

class _CreateWalletScreenState extends State<CreateWalletScreen> {
  final _bridge = walletBridge;

  // 1 = name + seed length (one screen), 2 = backup, 3 = verify, 4 = done.
  int _step = 1;
  static const int _totalSteps = 4;

  final _nameController = TextEditingController(text: 'My Wallet');

  /// Networks and blockchain were chosen in the wizard ([WalletTypeScreen]).
  final bool _liquidEnabled = newWalletDraft.liquidActive;
  int _seedLength = 24;

  List<String>? _mnemonic;
  bool _generatingMnemonic = false;
  bool _creatingWallet = false;

  List<int> _challengeIndexes = [];
  final _challengeAnswers = <int, String>{};

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// Back out of the setup: to the hosting wizard when embedded, otherwise
  /// to the wizard route (standalone entry).
  void _exitToWizard() {
    final cb = widget.onBackToWizard;
    if (cb != null) {
      cb();
    } else {
      context.go(AppRoutes.walletType);
    }
  }

  List<int> _pickChallengeIndexes(int length) {
    final rng = Random.secure();
    final third = length ~/ 3;
    return [
      rng.nextInt(third),
      third + rng.nextInt(third),
      2 * third + rng.nextInt(length - 2 * third),
    ];
  }

  Future<void> _generateMnemonic() async {
    setState(() => _generatingMnemonic = true);
    try {
      final words = await _bridge.generateMnemonic(_seedLength);
      final idxs = _pickChallengeIndexes(words.length);
      if (mounted) {
        setState(() {
          _mnemonic = words;
          _challengeIndexes = idxs;
          _challengeAnswers.clear();
          _generatingMnemonic = false;
          _step = 2;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _generatingMnemonic = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate mnemonic: $e')),
        );
      }
    }
  }

  Future<void> _next() async {
    if (_step == 1) {
      // Leaving the combined name+seed step generates the mnemonic.
      await _generateMnemonic();
    } else if (_step < _totalSteps) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 1) setState(() => _step--);
  }

  Future<void> _verifyAndFinish() async {
    final mnemonic = _mnemonic!;
    final correct = _challengeIndexes.every(
      (i) => (_challengeAnswers[i] ?? '').toLowerCase().trim() == mnemonic[i],
    );
    if (!correct) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'One or more words are incorrect. Check your backup and try again.',
          ),
        ),
      );
      return;
    }

    setState(() => _creatingWallet = true);
    try {
      final walletId = await _bridge.createWallet(
        _nameController.text,
        mnemonic,
        liquid: _liquidEnabled,
      );
      if (mounted) {
        context.read<AppState>().setActiveWallet(
          walletId,
          name: _nameController.text,
          type: 'Software',
          liquid: _liquidEnabled,
        );
        setState(() {
          _creatingWallet = false;
          _step = 4;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creatingWallet = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create wallet: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StepFlowScaffold(
      currentStep: widget.baseStep + _step,
      totalSteps: widget.baseStep + _totalSteps,
      title: _stepTitle,
      subtitle: _stepSubtitle,
      // Step 1 backs out into the wizard that led here.
      onBack: _step < 4 ? (_step > 1 ? _back : _exitToWizard) : null,
      onCancel: _step < 4 ? () => context.go(AppRoutes.walletPicker) : null,
      body: _stepBody,
      actions: _stepActions,
    );
  }

  String get _stepTitle => switch (_step) {
    1 => 'Name and seed length',
    2 => 'Back up your seed',
    3 => 'Verify your backup',
    _ => 'Wallet created',
  };

  String get _stepSubtitle => switch (_step) {
    1 => 'Give your wallet a name and choose its recovery-phrase length',
    2 => 'Write these words down on paper and keep them offline',
    3 => 'Enter the requested words to prove you saved them',
    _ => '',
  };

  Widget get _stepBody {
    if (_generatingMnemonic) {
      return const _Working('Generating the recovery phrase…');
    }
    if (_creatingWallet) return const _Working('Creating wallet…');
    return switch (_step) {
      1 => _NameAndSeedBody(
        controller: _nameController,
        seedLength: _seedLength,
        onSelectLength: (v) => setState(() => _seedLength = v),
      ),
      2 => _BackupBody(mnemonic: _mnemonic ?? []),
      3 => _VerifyBody(
        mnemonic: _mnemonic ?? [],
        indexes: _challengeIndexes,
        answers: _challengeAnswers,
        onAnswer: (i, v) => setState(() => _challengeAnswers[i] = v),
      ),
      _ => WalletCreatedView(
        walletName: _nameController.text,
        subtitle:
            'Your wallet has been created and secured. '
            'You can now receive and send funds.',
        details: [
          WalletCreatedDetail('Type', 'Software · Single-sig'),
          WalletCreatedDetail('Coins', newWalletDraft.networksLabel),
          WalletCreatedDetail('Network', newWalletDraft.networkLabel),
          WalletCreatedDetail('Seed', '$_seedLength words (backed up)'),
        ],
      ),
    };
  }

  Widget get _stepActions {
    if (_generatingMnemonic || _creatingWallet) return const SizedBox.shrink();
    return switch (_step) {
      4 => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SecondaryButton(
            label: 'Get receive address',
            onPressed: () => context.go(AppRoutes.receive),
          ),
          const SizedBox(width: AppSpacing.md),
          PrimaryButton(
            label: 'Open wallet',
            onPressed: () => context.go(AppRoutes.dashboard),
          ),
        ],
      ),
      3 => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          GhostButton(label: 'Back', icon: Icons.arrow_back, onPressed: _back),
          const SizedBox(width: AppSpacing.md),
          PrimaryButton(
            label: 'Confirm and finish',
            onPressed: _verifyAndFinish,
          ),
        ],
      ),
      _ => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_step > 1)
            GhostButton(
              label: 'Back',
              icon: Icons.arrow_back,
              onPressed: _back,
            ),
          const SizedBox(width: AppSpacing.md),
          PrimaryButton(
            label: 'Continue',
            onPressed: _nameController.text.trim().isEmpty ? null : _next,
          ),
        ],
      ),
    };
  }
}

/// A spinner and one line, while the engine works.
class _Working extends StatelessWidget {
  const _Working(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            message,
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
        ],
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

/// Step 1 — wallet name and 12/24-word choice on one screen.
class _NameAndSeedBody extends StatelessWidget {
  const _NameAndSeedBody({
    required this.controller,
    required this.seedLength,
    required this.onSelectLength,
  });

  final TextEditingController controller;
  final int seedLength;
  final void Function(int) onSelectLength;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final d = newWalletDraft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _FieldLabel('Wallet name'),
            TextField(controller: controller, autofocus: true),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${d.networksLabel} · ${d.networkLabel} · Software · Single-sig',
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const ListSectionLabel(label: 'Recovery phrase'),
        SelectableOptionCard(
          title: '12 words',
          description:
              '128 bits of entropy. Standard for most wallets. Easier to back up.',
          isSelected: seedLength == 12,
          onTap: () => onSelectLength(12),
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableOptionCard(
          title: '24 words',
          description:
              '256 bits of entropy. Maximum security. Recommended for large holdings.',
          isSelected: seedLength == 24,
          onTap: () => onSelectLength(24),
        ),
      ],
    );
  }
}

class _BackupBody extends StatelessWidget {
  const _BackupBody({required this.mnemonic});
  final List<String> mnemonic;

  @override
  Widget build(BuildContext context) {
    return SecureScreen(child: _buildBody(context));
  }

  Widget _buildBody(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WarningBanner(
          title: 'Write these words down on paper',
          message:
              'Never type or photograph your seed phrase. Anyone who sees it can steal your funds. This is shown only once.',
        ),
        const SizedBox(height: AppSpacing.xl),
        // Three columns on a phone too: at 379 dp each well still holds an
        // eight-letter word (the longest in the BIP39 list) beside "24."
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisExtent: 40,
            crossAxisSpacing: AppSpacing.sm,
            mainAxisSpacing: AppSpacing.sm,
          ),
          itemCount: mnemonic.length,
          itemBuilder: (context, i) =>
              _WordTile(index: i + 1, word: mnemonic[i]),
        ),
      ],
    );
  }
}

/// One word in its well: the position in a fixed right-aligned column, so
/// "1." and "24." line up, then the word in mono.
class _WordTile extends StatelessWidget {
  const _WordTile({required this.index, required this.word});
  final int index;
  final String word;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
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
              '$index.',
              textAlign: TextAlign.right,
              style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              word,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: AppTypography.mono.copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// The requested positions, one field each, labelled "Word 7". Whether the
/// words match is said once, on Confirm, for the set as a whole: marking
/// each field right or wrong as it is typed would let anyone without the
/// backup find the words by trial.
class _VerifyBody extends StatelessWidget {
  const _VerifyBody({
    required this.mnemonic,
    required this.indexes,
    required this.answers,
    required this.onAnswer,
  });

  final List<String> mnemonic;
  final List<int> indexes;
  final Map<int, String> answers;
  final void Function(int, String) onAnswer;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in indexes)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FieldLabel('Word ${i + 1}'),
                TextField(
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.next,
                  style: AppTypography.mono.copyWith(color: s.ink),
                  onChanged: (v) => onAnswer(i, v),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
