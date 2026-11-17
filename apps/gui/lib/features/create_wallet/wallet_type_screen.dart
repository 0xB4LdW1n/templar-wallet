import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/choice_list.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/step_flow_scaffold.dart';
import '../../shared/widgets/step_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../hardware/hw_platform.dart';
import '../vault/vault_passphrase_step.dart';
import 'airgap_setup_screen.dart';
import 'create_wallet_screen.dart';
import 'hardware_setup_screen.dart';
import 'models/new_wallet_draft.dart';
import 'multisig_setup_screen.dart';
import 'watch_only_setup_screen.dart';

/// The whole new-wallet flow, start to finish, on one route: the guided
/// questions (structure, keys, coins, and — for a hardware wallet — USB vs
/// air-gap), followed by the matching setup, which is hosted *inside* this
/// screen rather than pushed as a new page.
///
/// Steps are numbered continuously ("Step 5 of 9") and Back always walks
/// backwards through the same flow: from the first setup step it returns to
/// the last question with every answer intact.
///
/// See [NewWalletDraft] for why the questions are in this order.
class WalletTypeScreen extends StatefulWidget {
  const WalletTypeScreen({super.key, this.bridge});

  /// Test seam — the wizard probes the vault and the USB stack on entry.
  /// Null uses the app's real bridge.
  final WalletBridge? bridge;

  @override
  State<WalletTypeScreen> createState() => _WalletTypeScreenState();
}

class _WalletTypeScreenState extends State<WalletTypeScreen> {
  int _step = 1;

  /// True once the questions are answered and the setup takes over the flow.
  bool _inSetup = false;

  /// A watch-only wallet being built from cosigner keys rather than from a
  /// pasted descriptor — chosen on the watch-only setup screen, which then
  /// hands the rest of the flow to the multisig coordinator screens.
  bool _cosignerSetup = false;

  /// Whether this build can drive a hardware wallet over USB. False on
  /// Android, whose engine ships without the USB stack: the cable option
  /// goes away and a hardware wallet is set up air-gapped, by QR.
  bool _usbHardwareSupported = true;

  // ── App-password step state ───────────────────────────────────────────────
  final _vaultPassCtrl = TextEditingController();
  final _vaultConfirmCtrl = TextEditingController();
  bool _vaultDeclined = false;
  bool _vaultDone = false;
  bool _vaultBusy = false;
  String? _vaultError;

  late final WalletBridge _bridge = widget.bridge ?? walletBridge;

  NewWalletDraft get _draft => newWalletDraft;

  /// The opt-out, as it actually applies: a wallet whose recovery phrase is
  /// stored on this computer cannot skip encryption (A2), whatever the flag
  /// says from an earlier pass through the wizard with a different answer.
  bool get _declined => _vaultDeclined && !_draft.seedOnDisk;

  int get _wizardSteps => _draft.wizardSteps;
  int get _totalSteps => _draft.totalSteps;

  /// The question on screen. Answers change how many questions there are, so
  /// the index is clamped rather than trusted.
  WizardQuestion get _question {
    final qs = _draft.questions;
    return qs[(_step - 1).clamp(0, qs.length - 1)];
  }

  @override
  void initState() {
    super.initState();
    _checkVault();
    _checkUsbHardware();
  }

  @override
  void dispose() {
    _vaultPassCtrl.dispose();
    _vaultConfirmCtrl.dispose();
    super.dispose();
  }

  /// Show the password step only while wallet storage isn't encrypted yet.
  /// The draft persists across wizard entries, so refresh the flag every time.
  Future<void> _checkVault() async {
    var show = false;
    try {
      show = !(await _bridge.vaultStatus()).initialized;
    } catch (_) {
      // Bridge unavailable — don't block wallet creation on the vault.
    }
    if (mounted) setState(() => _draft.includeVaultStep = show);
  }

  /// One probe, on Android only: does the engine carry the USB hardware
  /// stack? A failed probe keeps USB on offer — the setup screen reports
  /// the real error, which beats hiding a working option on a guess.
  Future<void> _checkUsbHardware() async {
    if (!Platform.isAndroid) return;
    bool supported;
    try {
      supported = (await _bridge.hwiStatus()).hardwareSupported;
    } catch (_) {
      return;
    }
    if (!mounted || supported) return;
    setState(() {
      _usbHardwareSupported = false;
      // Air-gap is the only way a device can connect here, so the connection
      // question is answered up front; its step still shows the answer.
      _draft.hwConnection = HwConnection.airgap;
    });
  }

  /// An answer that adds or drops later questions can leave the cursor past
  /// the end of the flow. Keep it inside it.
  void _clampStep() {
    if (_step > _wizardSteps) _step = _wizardSteps;
  }

  void _next() {
    if (_step < _wizardSteps) {
      setState(() => _step++);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_step > 1) setState(() => _step--);
  }

  /// Questions answered — hand the flow to the setup phase in place.
  void _finish() {
    if (_draft.path == WalletPath.customPolicy) {
      // Unreachable while the option is disabled; kept as a guard.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom policy wallets coming soon')),
      );
      return;
    }
    setState(() => _inSetup = true);
  }

  /// Continue from the password step: create the vault first (unless declined
  /// or already done on this pass), then advance.
  Future<void> _continuePressed() async {
    if (_question != WizardQuestion.vault || _vaultDone || _declined) {
      _next();
      return;
    }
    final p = _vaultPassCtrl.text;
    if (p.length < 8) {
      setState(() => _vaultError = 'Use at least 8 characters');
      return;
    }
    if (p != _vaultConfirmCtrl.text) {
      setState(() => _vaultError = 'Passwords do not match');
      return;
    }
    setState(() {
      _vaultBusy = true;
      _vaultError = null;
    });
    try {
      await _bridge.setupVault(p);
      if (!mounted) return;
      setState(() {
        _vaultBusy = false;
        _vaultDone = true;
      });
      _next();
    } catch (e) {
      if (mounted) {
        setState(() {
          _vaultBusy = false;
          _vaultError = 'Encryption setup failed: $e';
        });
      }
    }
  }

  /// Back from the setup's first step: return to the last question — or, in
  /// the watch-only cosigner flow, to the watch-only screen that started it.
  void _backToWizard() {
    if (_cosignerSetup) {
      setState(() => _cosignerSetup = false);
      return;
    }
    setState(() {
      _inSetup = false;
      _step = _wizardSteps;
    });
  }

  void _cancel() => context.go(AppRoutes.walletPicker);

  @override
  Widget build(BuildContext context) {
    if (_inSetup) return _setupScreen();

    _clampStep();
    return StepFlowScaffold(
      currentStep: _step,
      totalSteps: _totalSteps,
      title: _stepTitle,
      subtitle: _stepSubtitle,
      headerVariants: _headerVariants,
      onBack: _step > 1 ? _back : null,
      onCancel: _cancel,
      body: _stepBody,
      actions: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Rendered on step 1 too, inert: a button that appears on step 2
          // moves the one next to it, and this row is where the thumb lives.
          GhostButton(
            label: 'Back',
            icon: Icons.arrow_back,
            onPressed: _step > 1 && !_vaultBusy ? _back : null,
          ),
          const SizedBox(width: AppSpacing.md),
          PrimaryButton(
            label: _step < _wizardSteps ? 'Continue' : 'Start setup',
            isLoading: _vaultBusy,
            onPressed: _canContinue && !_vaultBusy ? _continuePressed : null,
          ),
        ],
      ),
    );
  }

  /// The setup phase renders its own [StepFlowScaffold], offset by the
  /// questions already answered — so the counter keeps running.
  Widget _setupScreen() {
    final base = _wizardSteps;
    if (_draft.path == WalletPath.watchOnly) {
      return _cosignerSetup
          ? MultisigSetupScreen(baseStep: base, onBackToWizard: _backToWizard)
          : WatchOnlySetupScreen(
              baseStep: base,
              onBackToWizard: _backToWizard,
              onUseCosignerKeys: () => setState(() => _cosignerSetup = true),
            );
    }
    if (_draft.structure == WalletStructure.multisig) {
      return MultisigSetupScreen(baseStep: base, onBackToWizard: _backToWizard);
    }
    return switch (_draft.kind) {
      WalletKind.hardware =>
        _draft.hwConnection == HwConnection.airgap
            ? AirgapSetupScreen(baseStep: base, onBackToWizard: _backToWizard)
            : HardwareSetupScreen(
                baseStep: base,
                onBackToWizard: _backToWizard,
              ),
      _ => CreateWalletScreen(baseStep: base, onBackToWizard: _backToWizard),
    };
  }

  /// The connection question needs an answer, and the password step needs
  /// either both fields filled or an explicit opt-out, before continuing.
  bool get _canContinue {
    if (_question == WizardQuestion.connection && _draft.hwConnection == null) {
      return false;
    }
    if (_question == WizardQuestion.vault && !_declined && !_vaultDone) {
      return _vaultPassCtrl.text.isNotEmpty &&
          _vaultConfirmCtrl.text.isNotEmpty;
    }
    return true;
  }

  String _titleOf(WizardQuestion q) => switch (q) {
    WizardQuestion.structure => 'What kind of wallet?',
    WizardQuestion.kind => 'Where do your keys live?',
    WizardQuestion.coins => 'Which coins?',
    WizardQuestion.connection => 'How does your device connect?',
    WizardQuestion.vault => 'Protect this app with a password',
  };

  String _subtitleOf(WizardQuestion q) => switch (q) {
    WizardQuestion.structure =>
      'One key, several keys that must agree, or no keys at all',
    WizardQuestion.kind => 'This decides how you approve every payment',
    WizardQuestion.coins => 'Both run on the same recovery phrase',
    WizardQuestion.connection =>
      _usbHardwareSupported
          ? 'Cable or camera — either way the key stays on the device'
          : 'By camera — the key never leaves the device',
    WizardQuestion.vault =>
      AppLayout.isPhone(context) || Platform.isAndroid
          ? 'Encrypts wallet storage on this device'
          : 'Encrypts wallet storage on this computer',
  };

  String get _stepTitle => _titleOf(_question);
  String get _stepSubtitle => _subtitleOf(_question);

  /// Every header this wizard can show, so it reserves one height for the
  /// lot: a two-line subtitle on one question must not shift the cards — or
  /// the Back arrow above them — on the way to the next.
  List<StepHeaderVariant> get _headerVariants => [
    for (final q in WizardQuestion.values)
      StepHeaderVariant(_titleOf(q), _subtitleOf(q)),
  ];

  Widget get _stepBody => switch (_question) {
    WizardQuestion.structure => _StructureStep(
      selected: _draft.path,
      onSelect: (v) => setState(() {
        _draft.path = v;
        _clampStep();
      }),
    ),
    WizardQuestion.kind => _KindStep(
      selected: _draft.keyKind,
      usbAvailable: _usbHardwareSupported,
      onSelect: (v) => setState(() {
        _draft.keyKind = v;
        _clampStep();
      }),
    ),
    WizardQuestion.coins => _CoinsStep(
      liquidEnabled: _draft.liquidEnabled,
      liquidSupported: _draft.liquidSupported,
      kind: _draft.kind,
      onSelect: (v) => setState(() => _draft.liquidEnabled = v),
    ),
    WizardQuestion.connection => _ConnectionStep(
      selected: _draft.hwConnection,
      liquidWanted: _draft.liquidActive,
      usbAvailable: _usbHardwareSupported,
      onSelect: (v) => setState(() => _draft.hwConnection = v),
    ),
    WizardQuestion.vault => VaultPassphraseStep(
      passCtrl: _vaultPassCtrl,
      confirmCtrl: _vaultConfirmCtrl,
      declined: _declined,
      done: _vaultDone,
      error: _vaultError,
      seedOnDisk: _draft.seedOnDisk,
      onChanged: () => setState(() => _vaultError = null),
      onDeclinedChanged: (v) => setState(() {
        _vaultDeclined = v;
        _vaultError = null;
      }),
      onSubmitted: _continuePressed,
    ),
  };
}

// ── Structure — the first question ────────────────────────────────────────────

/// One key, several keys, or none. Asked first because it decides which of the
/// later questions exist at all — and because it is the only one of them a
/// person arrives already knowing the answer to.
class _StructureStep extends StatelessWidget {
  const _StructureStep({required this.selected, required this.onSelect});

  final WalletPath selected;
  final void Function(WalletPath) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableOptionCard(
          title: 'One key',
          description:
              'A single key signs every payment. Simplest to use and to back '
              'up — one recovery phrase and you are done.',
          isSelected: selected == WalletPath.singleSig,
          icon: Icons.vpn_key_outlined,
          onTap: () => onSelect(WalletPath.singleSig),
        ),
        const SizedBox(height: AppSpacing.lg),
        SelectableOptionCard(
          title: 'Several keys must agree (multisig)',
          description:
              'M-of-N: e.g. any 2 of 3 keys must approve. Losing one key does '
              'not lose the coins, and no single key can spend alone.',
          isSelected: selected == WalletPath.multisig,
          icon: Icons.group_outlined,
          onTap: () => onSelect(WalletPath.multisig),
        ),
        const SizedBox(height: AppSpacing.lg),
        // Drawn at half ink by the card itself (no onTap): shown, not offered.
        const SelectableOptionCard(
          title: 'Custom rules (policy)',
          description:
              'Timelocks, inheritance and recovery paths via Miniscript',
          isSelected: false,
          icon: Icons.account_tree_outlined,
          badge: 'Coming soon',
          onTap: null,
        ),
        if (selected == WalletPath.multisig) ...[
          const SizedBox(height: AppSpacing.xl),
          const InfoBanner(
            message:
                'Each of the keys is chosen separately while you import them: '
                'a USB device, an xpub pasted or scanned from an air-gapped '
                'signer, another wallet in this app, or a private key held '
                'right here.',
          ),
        ],
        // Watch-only is not a third spending structure — it is a wallet with
        // no keys at all — so it sits under its own label rather than in the
        // list with them.
        const SizedBox(height: AppSpacing.xl),
        const ListSectionLabel(label: 'Without keys'),
        SelectableOptionCard(
          title: 'Somewhere else — just watch it',
          description:
              'Follow a wallet you already have, from its public key, its '
              'descriptor, or its cosigners\' keys. Shows balances and '
              'history; cannot spend',
          isSelected: selected == WalletPath.watchOnly,
          icon: Icons.visibility_outlined,
          onTap: () => onSelect(WalletPath.watchOnly),
        ),
      ],
    );
  }
}

// ── Key storage — single-sig only ─────────────────────────────────────────────

class _KindStep extends StatelessWidget {
  const _KindStep({
    required this.selected,
    required this.onSelect,
    this.usbAvailable = true,
  });

  /// Software or hardware. Watch-only is answered on the previous step.
  final WalletKind selected;
  final void Function(WalletKind) onSelect;

  /// False where the build has no USB stack (Android): the hardware option
  /// is offered as air-gapped, the only way a device connects there.
  final bool usbAvailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableOptionCard(
          // Never "this computer" on a phone (design.md, "Copy").
          title: AppLayout.isPhone(context)
              ? 'On this phone'
              : Platform.isAndroid
              ? 'On this device'
              : 'On this computer',
          description:
              'Templar creates a recovery phrase and keeps it here, encrypted. '
              'Quickest to set up, and the right choice for trying things out.',
          isSelected: selected == WalletKind.software,
          icon: Icons.memory_outlined,
          onTap: () => onSelect(WalletKind.software),
        ),
        const SizedBox(height: AppSpacing.lg),
        SelectableOptionCard(
          title: 'On a hardware wallet',
          description: usbAvailable
              ? 'Ledger, Trezor, Jade, Coldcard or SeedSigner. The key never '
                    'leaves the device — Templar prepares the payment, the '
                    'device approves it.'
              : 'Jade, Coldcard, SeedSigner or any signer that reads QR '
                    'codes. The key never leaves the device — Templar shows the '
                    'payment as a QR code, the device signs it offline.',
          isSelected: selected == WalletKind.hardware,
          icon: usbAvailable
              ? Icons.usb_outlined
              : Icons.qr_code_scanner_outlined,
          onTap: () => onSelect(WalletKind.hardware),
        ),
      ],
    );
  }
}

/// The network, stated under the coins question. Only testnet can be picked,
/// but the other two are shown rather than described in a banner: seeing
/// mainnet sitting there, greyed and labelled, answers "does this wallet ever
/// touch real money?" and "is mainnet planned?" in one look — and makes it
/// unmistakable which network the wallet being created is on.
///
/// It sat at the foot of the structure step until 2026-09-08, under four
/// cards and a divider, which on a laptop put it below the fold: the one
/// screen about chains is the coins step, and it had room.
class _NetworkSection extends StatelessWidget {
  const _NetworkSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: AppSpacing.xxl),
        ListSectionLabel(label: 'Network'),
        _NetworkChoice(),
      ],
    );
  }
}

/// The network row: the network the wallet will open on is the live
/// option — Testnet, or Regtest while a test server is joined (the engine
/// decides; the switch is in Settings) — and mainnet is shown, disabled and
/// labelled "Coming soon".
class _NetworkChoice extends StatelessWidget {
  const _NetworkChoice();

  @override
  Widget build(BuildContext context) {
    final st = maybeAppState(context);
    final regtest =
        (st?.isBitcoinRegtest ?? false) || (st?.isLiquidRegtest ?? false);
    final lab = st?.testServerName;
    final cards = <Widget>[
      _NetworkCard(
        label: 'Testnet',
        detail: regtest
            ? 'Public test networks; switch back in Settings › Network'
            : 'Coins have no value; mistakes cost nothing',
        icon: Icons.science_outlined,
        current: !regtest,
      ),
      const _NetworkCard(
        label: 'Mainnet',
        detail: 'Real bitcoin',
        icon: Icons.public_outlined,
        current: false,
        soon: true,
      ),
      _NetworkCard(
        label: 'Regtest',
        detail: regtest
            ? (lab != null
                  ? 'The Bitcoin and Liquid regtest of test server $lab'
                  : 'A local Liquid regtest')
            : 'Join a test server in Settings › Network',
        icon: Icons.dns_outlined,
        current: regtest,
      ),
    ];
    if (AppLayout.isPhone(context)) {
      // Three side-by-side cards are 86 dp inside at 379 dp and wrap
      // "Testnet" mid-word; stacked, each card gets the whole column.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            cards[i],
          ],
        ],
      );
    }
    // One height for the three cards, whichever detail wraps.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.label,
    required this.detail,
    required this.icon,
    required this.current,
    this.soon = false,
  });

  final String label;
  final String detail;
  final IconData icon;

  /// The network the wallet will open on (the engine's, now).
  final bool current;

  /// Not built yet (mainnet).
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // The network this wallet is on is drawn as a chosen option (the
    // selected surface, a firmer edge, its radio); the other two at half ink.
    final available = current;
    return Opacity(
      opacity: available ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: available ? s.selected : s.panel,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: available ? s.edgeStrong : s.edge),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: AppSpacing.iconSmall, color: s.inkSecondary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.label.copyWith(color: s.ink),
                  ),
                ),
                if (available) const OptionRadio(selected: true),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              soon ? 'Coming soon · $detail' : detail,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Coins ─────────────────────────────────────────────────────────────────────

class _CoinsStep extends StatelessWidget {
  const _CoinsStep({
    required this.liquidEnabled,
    required this.liquidSupported,
    required this.kind,
    required this.onSelect,
  });

  final bool liquidEnabled;

  /// False for a Miniscript policy wallet, which has no Liquid form here.
  final bool liquidSupported;
  final WalletKind kind;
  final void Function(bool) onSelect;

  @override
  Widget build(BuildContext context) {
    // Asked after the structure question — the first one — precisely so this
    // case can be stated as a fact here, instead of accepting "Bitcoin +
    // Liquid" and revealing four screens later that it was quietly dropped.
    if (!liquidSupported) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableOptionCard(
            title: 'Bitcoin',
            description:
                'This wallet holds bitcoin on the Bitcoin '
                '${maybeAppState(context)?.bitcoinNetworkName ?? 'testnet'} '
                'chain',
            isSelected: true,
            icon: Icons.currency_bitcoin,
            onTap: null,
          ),
          const SizedBox(height: AppSpacing.xl),
          const InfoBanner(
            title: 'Bitcoin only, because of the spending policy you chose',
            message:
                'Liquid wallets are limited to single-key and M-of-N '
                'multisig here — timelocks, hashlocks and the other policy '
                'building blocks have no confidential-descriptor form. '
                'Choose one key or multisig on the first step if you '
                'want the Liquid side as well.',
          ),
          const _NetworkSection(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableOptionCard(
          title: 'Bitcoin + Liquid',
          description:
              'Adds a paired Liquid wallet for confidential LBTC and other '
              'Liquid assets. Same recovery phrase, nothing extra to back up.',
          isSelected: liquidEnabled,
          icon: Icons.water_drop_outlined,
          onTap: () => onSelect(true),
        ),
        const SizedBox(height: AppSpacing.lg),
        SelectableOptionCard(
          title: 'Bitcoin only',
          description:
              'Just the Bitcoin network. The Liquid section stays hidden.',
          isSelected: !liquidEnabled,
          icon: Icons.currency_bitcoin,
          onTap: () => onSelect(false),
        ),
        // Said before a device is chosen, because it decides which device the
        // user should reach for — not something to discover two screens later
        // with a Ledger already plugged in.
        if (kind == WalletKind.hardware && liquidEnabled) ...[
          const SizedBox(height: AppSpacing.xl),
          const InfoBanner(
            title: 'For Liquid, the device must be a Blockstream Jade',
            message:
                'Jade is the only hardware wallet with Liquid in its '
                'firmware. With a Ledger, Trezor, Coldcard or KeepKey this '
                'wallet is created Bitcoin-only — that is a limit of those '
                'devices, not a missing feature here.',
          ),
        ],
        const _NetworkSection(),
      ],
    );
  }
}

// ── Hardware connection (USB vs air-gap) ──────────────────────────────────────

class _ConnectionStep extends StatelessWidget {
  const _ConnectionStep({
    required this.selected,
    required this.liquidWanted,
    required this.onSelect,
    this.usbAvailable = true,
  });

  final HwConnection? selected;
  final bool liquidWanted;
  final void Function(HwConnection) onSelect;

  /// False where the build has no USB stack (Android): only the camera
  /// route is shown, and it is already the answer.
  final bool usbAvailable;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (usbAvailable) ...[
          SelectableOptionCard(
            title: 'By cable (USB)',
            description:
                'Plug the device in and Templar talks to it directly. The '
                'device still shows and approves every payment on its own '
                'screen.',
            isSelected: selected == HwConnection.usb,
            icon: Icons.usb_outlined,
            onTap: () => onSelect(HwConnection.usb),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        SelectableOptionCard(
          title: 'By camera (air-gapped QR)',
          description:
              'No cable ever touches the device. Templar shows a payment as a QR '
              'code, the device signs it offline, and you scan the result back.',
          isSelected: selected == HwConnection.airgap,
          icon: Icons.qr_code_scanner_outlined,
          onTap: () => onSelect(HwConnection.airgap),
        ),
        // Liquid decides this answer, so it is said here rather than left for
        // the setup screen: Jade is the only device with Liquid in firmware,
        // and even a Jade does Liquid over the cable only — its QR mode
        // carries Bitcoin alone (no blinding key, no Liquid PSET).
        if (liquidWanted && !usbAvailable) ...[
          const SizedBox(height: AppSpacing.xl),
          const WarningBanner(
            title: 'Liquid needs the cable, and this build has no USB',
            message:
                'A Jade signs Liquid over USB only, and USB devices are '
                'not supported here — this wallet is created Bitcoin-only. '
                'Open the same device from the desktop app for its Liquid '
                'side.',
          ),
        ],
        if (liquidWanted && usbAvailable) ...[
          const SizedBox(height: AppSpacing.xl),
          const WarningBanner(
            title: 'For Liquid, choose the cable',
            message:
                'A Jade in QR mode signs Bitcoin only — pick the camera '
                'and this wallet is created Bitcoin-only. Over USB a Jade '
                'gives you both. (Ledger, Trezor, Coldcard and KeepKey are '
                'Bitcoin-only on either route: no Liquid in their firmware.)',
          ),
        ],
        // Only where a family is genuinely out of reach — a partial limit, not
        // a wall, and it names both the devices that do work and the way round
        // it for the ones that don't.
        if (usbAvailable && !allFamiliesSupported) ...[
          const SizedBox(height: AppSpacing.xl),
          WarningBanner(
            title: 'Not every device works over USB here',
            message: usbPartialSupportReason,
          ),
        ],
      ],
    );
  }
}
