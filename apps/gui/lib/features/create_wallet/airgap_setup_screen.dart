import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/scan_button.dart';
import '../../shared/widgets/step_flow_scaffold.dart';
import '../../shared/widgets/step_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../hardware/pairing_recap.dart';
import '../wallet_picker/models/wallet_summary.dart';
import 'models/new_wallet_draft.dart';

enum _AirgapDevice { seedSigner, jade }

class AirgapSetupScreen extends StatefulWidget {
  const AirgapSetupScreen({super.key, this.baseStep = 0, this.onBackToWizard});

  /// Questions already answered by the wizard hosting this setup —
  /// the step counter continues from here instead of restarting at 1.
  final int baseStep;

  /// Back from the first step: return to the wizard's last question.
  /// Null (standalone route) falls back to navigating there.
  final VoidCallback? onBackToWizard;

  @override
  State<AirgapSetupScreen> createState() => _AirgapSetupScreenState();
}

class _AirgapSetupScreenState extends State<AirgapSetupScreen> {
  final _bridge = walletBridge;
  final _nameController = TextEditingController(text: 'My Air-gap Wallet');
  final _recvController = TextEditingController();
  final _changeController = TextEditingController();

  // The wizard's networks step asked for Liquid, but a QR-only device cannot
  // provide it: Jade's QR mode is Bitcoin-only — no master blinding key
  // export, no Liquid PSET transport. So this flow builds a Bitcoin wallet and
  // says so, instead of asking for a CT descriptor no device here can hand over.
  final bool _liquidWanted = newWalletDraft.liquidActive;

  int _step = 1;
  static const int _totalSteps = 4;

  _AirgapDevice? _device;
  bool _creating = false;
  String? _error;

  /// The created wallet, which is what the recap step reports on. Held so the
  /// summary shows what was actually stored — the descriptor the backend
  /// normalized and the key identity it parsed out of it — rather than what was
  /// typed into the field.
  WalletSummary? _created;

  @override
  void initState() {
    super.initState();
    // The Create button's enabled state lives in this parent — rebuild when
    // any gating field changes.
    for (final c in [_nameController, _recvController]) {
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
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

  @override
  void dispose() {
    _nameController.dispose();
    _recvController.dispose();
    _changeController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final wallet = await _bridge.createWatchOnlyWallet(
        _nameController.text.trim(),
        _recvController.text.trim(),
        _changeController.text.trim(),
        airgap: true,
      );
      if (mounted) {
        context.read<AppState>().setActiveWallet(
          wallet.id,
          name: wallet.name,
          // The backend's own label ("Air-gap watch-only"), so the wallet is
          // recognised as QR-signing everywhere: a bare 'Air-gap' would not
          // match the checks that keep Send available for this kind.
          type: wallet.typeLabel.isNotEmpty ? wallet.typeLabel : 'Air-gap',
          liquid: false,
        );
        setState(() {
          _creating = false;
          _created = wallet;
          _step = 4;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = e.toString();
        });
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
      onBack: _step < 4
          ? (_step > 1 ? () => setState(() => _step--) : _exitToWizard)
          : null,
      onCancel: _step < 4 ? () => context.go(AppRoutes.walletPicker) : null,
      body: _stepBody(),
      actions: _stepActions,
    );
  }

  String get _stepTitle => switch (_step) {
    1 => 'Choose your device',
    2 => 'Export descriptor',
    3 => 'Paste descriptor and name',
    _ => 'Pairing summary',
  };

  String get _stepSubtitle => switch (_step) {
    1 => 'Select the air-gap device you are using',
    2 => 'Follow the on-device steps to export the wallet descriptor',
    3 => 'Paste the descriptor shown on your device',
    _ => 'What was created, and where it came from',
  };

  Widget _stepBody() => switch (_step) {
    1 => _Step1Body(
      selected: _device,
      onSelect: (d) => setState(() => _device = d),
      liquidWanted: _liquidWanted,
    ),
    2 => _Step2Body(device: _device!),
    3 => _Step3Body(
      nameController: _nameController,
      recvController: _recvController,
      changeController: _changeController,
      creating: _creating,
      error: _error,
    ),
    _ => _RecapBody(
      wallet: _created!,
      device: _device!,
      liquidWanted: _liquidWanted,
    ),
  };

  Widget get _stepActions {
    if (_step == 4) {
      return _StepActions(
        label: 'Open wallet',
        onPressed: () => context.go(AppRoutes.dashboard),
        secondaryLabel: 'Get receive address',
        onSecondary: () => context.go(AppRoutes.receive),
      );
    }
    if (_step == 3) {
      final hasDescriptor = _recvController.text.trim().isNotEmpty;
      final named = _nameController.text.trim().isNotEmpty;
      return _StepActions(
        label: _creating ? 'Creating…' : 'Create wallet',
        onPressed: (hasDescriptor && named && !_creating) ? _create : null,
        onBack: _creating ? null : () => setState(() => _step--),
        reason: _creating
            ? null
            : !hasDescriptor
            ? 'Paste the receive descriptor to continue'
            : !named
            ? 'Name the wallet to continue'
            : null,
      );
    }
    final chosen = !(_step == 1 && _device == null);
    return _StepActions(
      label: 'Continue',
      onPressed: chosen ? () => setState(() => _step++) : null,
      onBack: _step > 1 ? () => setState(() => _step--) : _exitToWizard,
      reason: chosen ? null : 'Choose a device to continue',
    );
  }
}

String _deviceName(_AirgapDevice d) => switch (d) {
  _AirgapDevice.seedSigner => 'SeedSigner',
  _AirgapDevice.jade => 'Jade',
};

// ── Step 1: device choice ─────────────────────────────────────────────────────

class _Step1Body extends StatelessWidget {
  const _Step1Body({
    required this.selected,
    required this.onSelect,
    required this.liquidWanted,
  });
  final _AirgapDevice? selected;
  final void Function(_AirgapDevice) onSelect;

  /// Liquid was asked for in the wizard but cannot be delivered over QR —
  /// said here, before the user exports anything from the device, rather than
  /// discovered as a missing Liquid wallet after setup.
  final bool liquidWanted;

  @override
  Widget build(BuildContext context) {
    // One column of option cards, the same on a phone and a desktop: the
    // choice is two rows, and a radio says which one is taken.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (liquidWanted) ...[
          const WarningBanner(
            title: 'This wallet will be Bitcoin-only',
            message:
                'Liquid does not travel over QR: a Jade in QR mode signs '
                'Bitcoin only, and never hands out the blinding key a Liquid '
                'wallet needs. To use Liquid, go back and connect the Jade by '
                'USB cable instead — everything else about this setup stays '
                'the same.',
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        SelectableOptionCard(
          title: 'SeedSigner',
          description: 'Open-source DIY device',
          icon: Icons.developer_board_outlined,
          isSelected: selected == _AirgapDevice.seedSigner,
          onTap: () => onSelect(_AirgapDevice.seedSigner),
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableOptionCard(
          title: 'Jade',
          description: 'Blockstream hardware wallet, in QR mode',
          icon: Icons.memory_outlined,
          isSelected: selected == _AirgapDevice.jade,
          onTap: () => onSelect(_AirgapDevice.jade),
        ),
      ],
    );
  }
}

// ── Step 2: on-device instructions ───────────────────────────────────────────

class _Step2Body extends StatelessWidget {
  const _Step2Body({required this.device});
  final _AirgapDevice device;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final steps = device == _AirgapDevice.seedSigner
        ? [
            'Seeds → select your seed → Export Xpub',
            'Choose Native Segwit (P2WPKH) → Testnet',
            'The receive descriptor QR will be shown',
            'Scan or copy the descriptor on the next screen',
          ]
        : [
            // The unlock is where Jade QR setups stall: the animated QR the
            // device shows after the PIN is a pinserver handshake that needs
            // an online relay (the Blockstream app). Temporary Signer skips
            // the PIN entirely and stays offline.
            'Unlock the Jade: QR PIN unlock needs the Blockstream app to relay '
                'the animated QR — or use Options → Temporary Signer to enter '
                'your recovery phrase on the device instead',
            'Start a QR session, then Options → Wallet → Export Xpub',
            'Choose Native Segwit and the Testnet network',
            'Scan the animated QR on the next screen (or copy the descriptor)',
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'On your ${_deviceName(device)}',
            style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: s.panel,
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: s.edge),
            boxShadow: s.panelShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: s.edge,
                    indent: AppSpacing.lg + AppSpacing.xl + AppSpacing.md,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // The step's number in the faint ink: an order, not a
                      // badge.
                      SizedBox(
                        width: AppSpacing.xl,
                        child: Text(
                          '${i + 1}',
                          style: AppTypography.numeric.copyWith(
                            color: s.inkFaint,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: AppTypography.bodyOf(
                            context,
                          ).copyWith(color: s.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Step 3: paste descriptor + name ──────────────────────────────────────────

class _Step3Body extends StatefulWidget {
  const _Step3Body({
    required this.nameController,
    required this.recvController,
    required this.changeController,
    required this.creating,
    this.error,
  });
  final TextEditingController nameController;
  final TextEditingController recvController;
  final TextEditingController changeController;
  final bool creating;
  final String? error;

  @override
  State<_Step3Body> createState() => _Step3BodyState();
}

class _Step3BodyState extends State<_Step3Body> {
  bool _showChange = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    if (widget.creating) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: AppSpacing.xl,
              height: AppSpacing.xl,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Creating wallet…',
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
      );
    }

    // A plain Column: the step scaffold already scrolls its body.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('Wallet name'),
        TextField(controller: widget.nameController),
        const SizedBox(height: AppSpacing.xl),
        const _FieldLabel('Receive descriptor'),
        _DescriptorField(
          controller: widget.recvController,
          hint: "wpkh([fingerprint/84'/1'/0']tpub…/0/*)",
          // Shared widget rather than a bespoke IconButton: it hides itself
          // where no camera plugin exists, so Windows/Linux see Paste alone
          // instead of a button that only apologises.
          scanTitle: 'Scan wallet QR (Jade: QR mode → Xpub export)',
          scanTooltip: 'Scan QR (Jade: QR mode → Xpub export)',
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            label: _showChange
                ? 'Hide change descriptor'
                : 'Add change descriptor (optional)',
            icon: _showChange ? Icons.remove_outlined : Icons.add_outlined,
            onPressed: () => setState(() => _showChange = !_showChange),
          ),
        ),
        if (_showChange) ...[
          const SizedBox(height: AppSpacing.md),
          const _FieldLabel('Change descriptor (optional)'),
          _DescriptorField(
            controller: widget.changeController,
            hint: "wpkh([fingerprint/84'/1'/0']tpub…/1/*)",
            scanTitle: 'Scan change descriptor',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Change addresses live on a second descriptor chain (…/1/*), '
            'derived automatically from the receive descriptor. Leave this '
            'empty unless your device exports a separate change descriptor '
            'that cannot be derived (different key or account).',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
        if (widget.error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          DangerBanner(title: 'Creation failed', message: widget.error!),
        ],
      ],
    );
  }
}

/// A field's label: an `eyebrow` 8 above the field, never floating inside it.
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

/// A descriptor field in `mono`, with Paste and — where a camera exists —
/// Scan beside it.
class _DescriptorField extends StatelessWidget {
  const _DescriptorField({
    required this.controller,
    required this.hint,
    required this.scanTitle,
    this.scanTooltip = 'Scan QR',
  });

  final TextEditingController controller;
  final String hint;
  final String scanTitle;
  final String scanTooltip;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: hint),
            style: AppTypography.mono.copyWith(color: s.ink),
            maxLines: 3,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Paste from clipboard',
              iconSize: AppLayout.isPhone(context) ? 22 : AppSpacing.icon,
              icon: const Icon(Icons.content_paste_outlined),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) controller.text = data!.text!.trim();
              },
            ),
            ScanIconButton(
              controller: controller,
              title: scanTitle,
              tooltip: scanTooltip,
            ),
          ],
        ),
      ],
    );
  }
}

/// The step's action row (design.md, "Steps"): Back as a ghost with its
/// arrow, the step's one primary on the right. A disabled primary says why
/// beside it. On a phone the primary takes the width and the reason sits
/// above the row.
class _StepActions extends StatelessWidget {
  const _StepActions({
    required this.label,
    required this.onPressed,
    this.onBack,
    this.reason,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onBack;
  final String? reason;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final why = reason;
    final back = onBack;
    final second = secondaryLabel;
    final reasonStyle = AppTypography.caption.copyWith(color: s.inkFaint);
    if (AppLayout.isPhone(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (why != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(why, textAlign: TextAlign.center, style: reasonStyle),
            ),
          if (second != null) ...[
            SecondaryButton(
              label: second,
              onPressed: onSecondary,
              isFullWidth: true,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              if (back != null) ...[
                GhostButton(
                  label: 'Back',
                  icon: Icons.arrow_back_outlined,
                  onPressed: back,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: PrimaryButton(
                  label: label,
                  onPressed: onPressed,
                  isFullWidth: true,
                ),
              ),
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: why == null
              ? const SizedBox.shrink()
              : Text(why, textAlign: TextAlign.end, style: reasonStyle),
        ),
        const SizedBox(width: AppSpacing.lg),
        if (back != null) ...[
          GhostButton(
            label: 'Back',
            icon: Icons.arrow_back_outlined,
            onPressed: back,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (second != null) ...[
          SecondaryButton(label: second, onPressed: onSecondary),
          const SizedBox(width: AppSpacing.sm),
        ],
        PrimaryButton(label: label, onPressed: onPressed),
      ],
    );
  }
}

// ── Step 4: recap ─────────────────────────────────────────────────────────────
//
// The same summary shape the USB pairing ends on: what exists, per network, and
// which checks passed. An air-gap wallet is built from a descriptor the user
// carried across by QR or clipboard, so the checks that matter here are about
// that descriptor — was a key identity actually parsed out of it, and is the
// change chain separate from the receive chain.

class _RecapBody extends StatelessWidget {
  const _RecapBody({
    required this.wallet,
    required this.device,
    required this.liquidWanted,
  });

  final WalletSummary wallet;
  final _AirgapDevice device;

  /// Liquid was asked for in the wizard and cannot be delivered over QR. Said
  /// again here, because this is the screen the user leaves the flow from.
  final bool liquidWanted;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final fingerprint = wallet.masterFingerprint ?? '';

    return PairingRecapView(
      walletName: wallet.name,
      deviceLabel: '${_deviceName(device)} (air-gap, QR)',
      fingerprint: fingerprint,
      networks: [
        PairingNetwork(
          name: 'Bitcoin',
          icon: Icons.currency_bitcoin_outlined,
          color: s.bitcoin,
          ok: true,
          detail: 'Watch-only here · your device signs the PSBT offline',
          descriptor: wallet.xpub,
        ),
        if (liquidWanted)
          PairingNetwork(
            name: 'Liquid Network',
            icon: Icons.water_drop_outlined,
            color: s.liquid,
            ok: false,
            // Not a missing feature: Jade's QR mode never exports the blinding
            // key a Liquid wallet needs, so no QR flow can produce one.
            detail:
                'Not possible over QR — connect the Jade by USB to pair '
                'Liquid. Everything else about the setup is the same.',
          ),
      ],
      checks: [
        PairingCheck(
          label: 'Descriptor accepted and stored',
          passed: true,
          detail: wallet.typeLabel,
        ),
        PairingCheck(
          // A descriptor with no readable key origin still opens, but the
          // wallet then has no identity to match a signing device against.
          label: 'Key identity read from the descriptor',
          passed: fingerprint.isNotEmpty,
          detail: fingerprint.isNotEmpty ? fingerprint : 'none found',
        ),
        const PairingCheck(
          label: 'No private key stored in this app',
          passed: true,
        ),
      ],
      footnote:
          'Sending builds an unsigned PSBT here, shows it as a QR code '
          'for your device to sign offline, and takes the signed one back by '
          'QR, file or paste. Nothing but public keys ever leaves the device.',
    );
  }
}
