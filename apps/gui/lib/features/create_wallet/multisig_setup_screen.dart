import 'dart:math';

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../features/wallet_picker/models/wallet_summary.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hex_text.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/scan_button.dart';
import '../../shared/widgets/step_flow_scaffold.dart';
import '../../shared/widgets/step_header.dart';
import '../../shared/widgets/wallet_created_view.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../services/udev_installer.dart';
import '../hardware/device_permission_card.dart';
import '../hardware/hw_error.dart';
import '../hardware/hwi_install_card.dart';
import 'models/hw_device.dart';
import '../../services/cosigner_label_store.dart';
import '../../shared/models/cosigner_label.dart';
import '../../shared/widgets/cosigner_label_editor.dart';
import 'models/new_wallet_draft.dart';

/// Ordered stages of the wizard. Coordinator paths (watch-only and hardware)
/// skip the seed/backup/verify steps — no key is generated on this computer.
enum _Stage {
  threshold,
  seedLength,
  backup,
  verify,
  importKeys,
  review,
  success,
}

/// Where a co-signer key comes from. The creator's own key (co-signer role)
/// is generated in-flow and is never one of these.
///
/// [newKey] and [seedPhrase] both produce a *private* key this wallet holds:
/// several local keys can live in one multisig, and a single sign action signs
/// with all of them.
enum _ImportSource { paste, appWallet, hardware, newKey, seedPhrase }

class _ImportSlot {
  _ImportSource source = _ImportSource.paste;
  final TextEditingController pasteCtrl = TextEditingController();

  /// The co-signer's BIP87 key, typed in when the source is a paste. Liquid
  /// lives on a different account than Bitcoin (m/87'/1'/0' vs
  /// m/48'/1'/0'/2'), so a remote co-signer sends two keys — neither can be
  /// computed from the other.
  final TextEditingController liquidPasteCtrl = TextEditingController();

  /// 12/24 words typed by the user ([_ImportSource.seedPhrase]).
  final TextEditingController seedCtrl = TextEditingController();

  /// Resolved keyorigin xpub for every non-paste source. Paste uses
  /// [pasteCtrl].
  String? xpub;

  /// Resolved BIP87 key for every non-paste source: derived locally for keys
  /// whose seed is here, read from the device for a Jade.
  String? liquidXpub;

  /// Registry ID when the key comes from a software wallet in the app.
  String? walletId;

  /// Sign with this key from the app. Always true for keys whose seed lives
  /// here ([newKey] / [seedPhrase]); opt-in for an app wallet's key.
  bool signsLocally = true;

  /// Device model when the key was read from USB.
  String? hwModel;

  /// Seed of a private key held by this wallet (generated or imported).
  /// It is passed to the backend as a local signing key.
  List<String>? mnemonic;

  /// What the engine made of the pasted/scanned Bitcoin key, and of the
  /// Liquid one. Null while the field is empty or still being checked.
  CosignerKeyInfo? keyInfo;
  CosignerKeyInfo? liquidKeyInfo;

  /// Why the engine cannot use what is in the field. A wallet built on a key
  /// like this saves and then never opens again, so the wizard refuses to
  /// carry it forward.
  String? keyError;
  String? liquidKeyError;

  /// A check is in flight for this slot.
  bool checking = false;

  /// What this co-signer will be called. Held here until the wallet exists —
  /// labels are keyed by fingerprint, and the creator's own key has no
  /// fingerprint to key on until the backend answers.
  CosignerLabel label = const CosignerLabel(id: '');

  /// Drop every verdict about the pasted keys — call whenever the text or the
  /// source changes, so a stale tick can never stand next to a new key.
  void clearKeyChecks() {
    keyInfo = null;
    liquidKeyInfo = null;
    keyError = null;
    liquidKeyError = null;
  }

  /// The user confirmed they wrote the generated words down.
  bool backedUp = false;

  void dispose() {
    pasteCtrl.dispose();
    liquidPasteCtrl.dispose();
    seedCtrl.dispose();
  }

  /// True when this slot holds a private key the app will sign with.
  bool get isLocalKey =>
      (source == _ImportSource.newKey || source == _ImportSource.seedPhrase)
      ? mnemonic != null
      : source == _ImportSource.appWallet && walletId != null && signsLocally;

  /// A generated key must be written down before the flow can continue.
  bool get isReady =>
      source == _ImportSource.newKey ? (mnemonic != null && backedUp) : true;

  /// The key this slot contributes. A checked paste contributes the engine's
  /// normalized form — a scanned air-gap export is a whole descriptor as it
  /// arrives, and only the reduced key can go in a multisig descriptor.
  String get resolvedXpub => source == _ImportSource.paste
      ? (keyInfo?.normalized ?? pasteCtrl.text.trim())
      : (xpub ?? '');

  String get resolvedLiquidXpub => source == _ImportSource.paste
      ? (liquidKeyInfo?.normalized ?? liquidPasteCtrl.text.trim())
      : (liquidXpub ?? '');

  /// True when a pasted key has been checked and refused. Such a slot blocks
  /// the step: the failure it causes is otherwise invisible until the finished
  /// wallet fails to open.
  bool get hasKeyProblem =>
      source == _ImportSource.paste &&
      (keyError != null || liquidKeyError != null);

  /// True when the key was read from a device that is not a Jade.
  ///
  /// Such a key rules Liquid out for the whole wallet: those devices cannot
  /// sign an Elements transaction, and they have no BIP87 Liquid key worth
  /// putting in the descriptor either.
  bool get isBitcoinOnlyDevice =>
      source == _ImportSource.hardware &&
      !(hwModel ?? '').toLowerCase().contains('jade');

  /// Whether this key can be expected to sign on Liquid. A pasted key is
  /// unknowable — its owner may hold a Jade or a software wallet — so it
  /// counts as capable and the review step says so plainly.
  bool get liquidCapable => !isBitcoinOnlyDevice;
}

class MultisigSetupScreen extends StatefulWidget {
  const MultisigSetupScreen({
    super.key,
    this.baseStep = 0,
    this.onBackToWizard,
    this.bridge,
  });

  /// Questions already answered by the wizard hosting this setup —
  /// the step counter continues from here instead of restarting at 1.
  final int baseStep;

  /// Back from the first step: return to the wizard's last question.
  /// Null (standalone route) falls back to navigating there.
  final VoidCallback? onBackToWizard;

  /// Test seam: the engine this setup talks to. Null in the app, which then
  /// uses the process-wide [walletBridge] (same shape as WalletInfoScreen).
  final WalletBridge? bridge;

  @override
  State<MultisigSetupScreen> createState() => _MultisigSetupScreenState();
}

class _MultisigSetupScreenState extends State<MultisigSetupScreen> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;
  // Named for what it is: a watch-only coordinator arrives here from the
  // watch-only setup, and "My Multisig Wallet" is not what that user is making.
  late final _nameController = TextEditingController(
    text: newWalletDraft.path == WalletPath.watchOnly
        ? 'Watch-only Multisig'
        : 'My Multisig Wallet',
  );

  int _stageIndex = 0;

  int _m = 2; // required signatures
  int _n = 3; // total keys

  /// A watch-only wallet imports every xpub and can never sign. The wizard
  /// answers this one; everything else about where the keys live is answered
  /// per key on the import step.
  bool get _isWatchOnly => newWalletDraft.path == WalletPath.watchOnly;

  /// Whether one of the N keys is generated here, in-flow, before the others
  /// are imported — asked on the threshold step, not by the wizard, because
  /// it is a fact about *this* wallet's keys and not about the app.
  ///
  /// Off does not mean "no key here": any import slot can still be set to
  /// "New key" or "Seed phrase" and hold a private key. It only decides
  /// whether the guided create-and-back-up-a-key steps come first.
  bool _holdsKey = false;

  /// The coins answer from the wizard: Bitcoin only, or Bitcoin + Liquid.
  final bool _liquidWanted = newWalletDraft.liquidActive;

  /// True when no key is generated in-flow: all N keys are imported. Slots
  /// can still hold private keys unless this is a watch-only wallet.
  bool get _isCoordinator => _isWatchOnly || !_holdsKey;

  // ── Creator key (co-signer role only — generated like a software wallet) ────
  int _seedLength = 24;
  List<String>? _creatorMnemonic;
  String? _creatorXpub;

  /// The creator key's BIP87 counterpart, derived alongside it.
  String? _creatorLiquidXpub;
  bool _generatingKey = false;
  List<int> _challengeIndexes = [];
  final _challengeAnswers = <int, String>{};

  // ── Imported keys (N-1 for co-signer, N for watch-only) ─────────────────────
  List<_ImportSlot> _importSlots = [];
  List<WalletSummary> _appWallets = [];

  bool _busy = false;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    for (final s in _importSlots) {
      s.dispose();
    }
    super.dispose();
  }

  // ── Stage model ─────────────────────────────────────────────────────────────

  /// Stages for the active role. Coordinators drop the three seed-key steps.
  List<_Stage> get _stages => _isCoordinator
      ? const [
          _Stage.threshold,
          _Stage.importKeys,
          _Stage.review,
          _Stage.success,
        ]
      : const [
          _Stage.threshold,
          _Stage.seedLength,
          _Stage.backup,
          _Stage.verify,
          _Stage.importKeys,
          _Stage.review,
          _Stage.success,
        ];

  _Stage get _stage => _stages[_stageIndex];

  /// Which import slot is open. The keys used to be a scroll of N fully
  /// expanded cards — every source picker, every field, all at once, for a
  /// step where the user works on exactly one key at a time. One card is open,
  /// the others collapse to a line saying whether they are filled, so the list
  /// still answers "how far am I" at a glance.
  int _expandedSlot = 0;

  void _goTo(_Stage s) => setState(() => _stageIndex = _stages.indexOf(s));
  void _back() => setState(() {
    if (_stageIndex > 0) _stageIndex--;
  });

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

  // ── Flow logic ────────────────────────────────────────────────────────────

  List<int> _pickChallengeIndexes(int length) {
    final rng = Random.secure();
    final third = length ~/ 3;
    return [
      rng.nextInt(third),
      third + rng.nextInt(third),
      2 * third + rng.nextInt(length - 2 * third),
    ];
  }

  /// Leaving the threshold step: branch on the role.
  Future<void> _advanceFromThreshold() async {
    if (_isCoordinator) {
      if (await _prepareImports(_n)) _goTo(_Stage.importKeys);
    } else {
      _goTo(_Stage.seedLength);
    }
  }

  /// Generate the creator's key (co-signer role) and move to the back-up step.
  Future<void> _generateCreatorKey() async {
    setState(() {
      _generatingKey = true;
      _error = null;
    });
    try {
      final words = await _bridge.generateMnemonic(_seedLength);
      final xpub = await _bridge.deriveCosignerXpub(words);
      // Both accounts come from this one seed, so the Liquid key costs the
      // user nothing to provide — only a remote co-signer is ever asked twice.
      final liquidXpub = _liquidWanted
          ? await _bridge.deriveLiquidCosignerXpub(words)
          : null;
      final idxs = _pickChallengeIndexes(words.length);
      if (mounted) {
        setState(() {
          _creatorMnemonic = words;
          _creatorXpub = xpub;
          _creatorLiquidXpub = liquidXpub;
          _challengeIndexes = idxs;
          _challengeAnswers.clear();
          _generatingKey = false;
        });
        _goTo(_Stage.backup);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generatingKey = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Check the back-up challenge, then prepare the N-1 import slots.
  Future<void> _verifyAndContinue() async {
    final mnemonic = _creatorMnemonic!;
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
    if (await _prepareImports(_n - 1)) _goTo(_Stage.importKeys);
  }

  /// Build [count] import slots and load app wallets that can lend a key.
  /// Returns false (and sets [_error]) on failure.
  Future<bool> _prepareImports(int count) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final wallets = await _bridge.listWallets();
      _appWallets = wallets
          .where(
            (w) =>
                w.type == WalletType.singlesig &&
                !w.isWatchOnly &&
                !w.isHardwareWallet &&
                !w.isAirgapWallet,
          )
          .toList();
      // Keep typed values if the count is unchanged; otherwise rebuild.
      if (_importSlots.length != count) {
        for (final s in _importSlots) {
          s.dispose();
        }
        _importSlots = List.generate(count, (_) => _ImportSlot());
      }
      if (mounted) setState(() => _busy = false);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
      return false;
    }
  }

  Future<void> _pickAppWallet(_ImportSlot slot, String walletId) async {
    setState(() => _busy = true);
    try {
      final xpub = await _bridge.getCosignerXpub(walletId);
      final liquidXpub = _liquidWanted
          ? await _bridge.getLiquidCosignerXpub(walletId)
          : null;
      slot.walletId = walletId;
      slot.xpub = xpub;
      slot.liquidXpub = liquidXpub;
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Read a BIP48 cosigner xpub from a USB device: enumerate, let the user
  /// pick if several are connected, then fetch. A missing HWI toolkit opens
  /// the installer instead of a raw error.
  Future<void> _fetchHwXpub(_ImportSlot slot) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final devices = await _bridge.enumerateHwDevices();
      if (!mounted) return;
      if (devices.isEmpty) {
        setState(() {
          _busy = false;
          _error =
              'No USB device found. Connect it, unlock it, and open the '
              'Bitcoin Testnet app (Ledger).';
        });
        return;
      }
      HwDevice? device = devices.length == 1 ? devices.first : null;
      device ??= await showDialog<HwDevice>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Choose a device'),
          children: [
            for (final d in devices)
              SimpleDialogOption(
                onPressed: () => Navigator.of(ctx).pop(d),
                child: Text('${d.model} (${d.fingerprint})'),
              ),
          ],
        ),
      );
      if (device == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final xpub = await _bridge.getHwCosignerXpub(device.fingerprint);
      // A Jade also holds a Liquid key; every other device is Bitcoin-only in
      // firmware, so there is nothing to ask it for. The read is fenced off on
      // its own: a Liquid key that cannot be read turns Liquid off for the
      // wallet, it does not throw away the Bitcoin key already in hand.
      String? liquidXpub;
      String? liquidError;
      final isJade = device.model.toLowerCase().contains('jade');
      if (_liquidWanted && isJade) {
        try {
          liquidXpub = await _bridge.getJadeLiquidCosignerXpub(
            expectFingerprint: device.fingerprint,
          );
        } catch (e) {
          liquidError =
              'Bitcoin key read, but the Jade did not return its '
              'Liquid key: ${classifyHwError(e).message}';
        }
      }
      if (mounted) {
        setState(() {
          slot.xpub = xpub;
          slot.liquidXpub = liquidXpub;
          slot.hwModel = device!.model;
          slot.walletId = null;
          // Read over USB, so it signs over USB: the co-signing sheet offers
          // the device for this key.
          slot.label = slot.label.copyWith(hardware: true);
          // A Jade is a shield, anything else on USB is a USB stick — until
          // the user says otherwise.
          if (slot.label.iconId == null || slot.label.iconId == 'usb') {
            slot.label = slot.label.copyWith(
              iconId: suggestedIconFor(
                fromDevice: true,
                fromAppWallet: false,
                isLocalSeed: false,
                deviceModel: device.model,
              ),
            );
          }
          // And it names itself, if nothing else has.
          if ((slot.label.name?.trim().isEmpty ?? true) &&
              device.model.isNotEmpty) {
            slot.label = slot.label.copyWith(name: device.model);
          }
          _busy = false;
          _error = liquidError;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final failure = classifyHwError(e);
      if (failure.isHwiMissing) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('HWI toolkit required'),
            content: SizedBox(
              width: 460,
              child: HwiInstallCard(
                onInstalled: () {
                  Navigator.of(ctx).pop();
                  _fetchHwXpub(slot);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      } else if (failure.isPermission && UdevInstaller.supported) {
        // Linux: enrolling a device key hits the same udev wall as every
        // other device call, and deserves the same one-click fix.
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Device access blocked'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: DevicePermissionCard(
                  detail: failure.message,
                  onFixed: () {
                    Navigator.of(ctx).pop();
                    _fetchHwXpub(slot);
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      } else {
        setState(() => _error = failure.message);
      }
    }
  }

  /// Generate a brand-new private key for this slot: the seed is kept by the
  /// wallet (it becomes another local signing key) and must be written down.
  Future<void> _generateSlotKey(_ImportSlot slot) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final words = await _bridge.generateMnemonic(24);
      final xpub = await _bridge.deriveCosignerXpub(words);
      final liquidXpub = _liquidWanted
          ? await _bridge.deriveLiquidCosignerXpub(words)
          : null;
      if (mounted) {
        setState(() {
          slot.mnemonic = words;
          slot.xpub = xpub;
          slot.liquidXpub = liquidXpub;
          slot.backedUp = false;
          slot.signsLocally = true;
          slot.walletId = null;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Adopt an existing 12/24-word seed as another private key of this wallet.
  Future<void> _useSlotSeed(_ImportSlot slot) async {
    final words = slot.seedCtrl.text
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.length != 12 && words.length != 24) {
      setState(
        () =>
            _error = 'A seed phrase has 12 or 24 words (got ${words.length}).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The backend validates the checksum while deriving.
      final xpub = await _bridge.deriveCosignerXpub(words);
      final liquidXpub = _liquidWanted
          ? await _bridge.deriveLiquidCosignerXpub(words)
          : null;
      if (mounted) {
        setState(() {
          slot.mnemonic = words;
          slot.xpub = xpub;
          slot.liquidXpub = liquidXpub;
          slot.signsLocally = true;
          slot.walletId = null;
          _busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: wallet-ffi: ', '');
        });
      }
    }
  }

  /// All N keys. Co-signer role puts its generated key first.
  List<String> get _allXpubs => _isCoordinator
      ? _importSlots.map((s) => s.resolvedXpub).toList()
      : [_creatorXpub ?? '', ..._importSlots.map((s) => s.resolvedXpub)];

  /// The same N co-signers' Liquid (BIP87) keys, in the same order — the
  /// descriptor's key order is part of the wallet, so the two lists must line
  /// up index for index.
  List<String> get _allLiquidXpubs => _isCoordinator
      ? _importSlots.map((s) => s.resolvedLiquidXpub).toList()
      : [
          _creatorLiquidXpub ?? '',
          ..._importSlots.map((s) => s.resolvedLiquidXpub),
        ];

  /// Keys that can be expected to sign on Liquid. The creator's own key always
  /// can; a key read from a Bitcoin-only device never can.
  int get _liquidCapableKeys =>
      (_isCoordinator ? 0 : 1) +
      _importSlots.where((s) => s.liquidCapable).length;

  /// A key that rules Liquid out no matter what else is filled in.
  _ImportSlot? get _bitcoinOnlyDeviceSlot {
    for (final s in _importSlots) {
      if (s.isBitcoinOnlyDevice) return s;
    }
    return null;
  }

  /// Why Liquid cannot be part of this wallet, or null when it can.
  ///
  /// Only reasons the user can act on — a missing key is not one of them, that
  /// is just an unfinished form.
  String? get _liquidBlockedReason {
    if (!_liquidWanted) return null;
    final device = _bitcoinOnlyDeviceSlot;
    if (device != null) {
      return 'Key from ${device.hwModel ?? 'this device'} is Bitcoin-only. '
          'Ledger, Trezor, Coldcard and KeepKey cannot sign Liquid '
          'transactions, and hold no Liquid key to enrol — so this wallet '
          'will be Bitcoin-only. Use a Blockstream Jade, or a key held in '
          'this app, for a wallet that also holds Liquid.';
    }
    if (_liquidCapableKeys < _m) {
      return 'Only $_liquidCapableKeys of the $_n keys could sign on Liquid, '
          'but $_m signatures are required. Liquid funds would be '
          'unspendable, so this wallet will be Bitcoin-only.';
    }
    return null;
  }

  /// Whether a Liquid side is still on the table for this wallet.
  bool get _liquidPossible => _liquidWanted && _liquidBlockedReason == null;

  /// Whether the Liquid side is fully specified and will actually be built.
  bool get _liquidReady {
    if (!_liquidPossible) return false;
    final keys = _allLiquidXpubs;
    if (keys.length != _n || keys.any((k) => k.isEmpty)) return false;
    return keys.toSet().length == keys.length;
  }

  /// Every key resolved, no duplicates, and every generated key backed up.
  /// With Liquid in play the same holds for the BIP87 keys — a half-filled
  /// Liquid column would silently create a Bitcoin-only wallet.
  bool get _importsComplete {
    final all = _allXpubs;
    if (all.length != _n || all.any((x) => x.isEmpty)) return false;
    if (_importSlots.any((s) => !s.isReady)) return false;
    if (all.toSet().length != all.length) return false;
    if (_liquidPossible && !_liquidReady) return false;
    return true;
  }

  /// Keys this app will sign with: the creator key plus every slot holding a
  /// private key (generated, imported seed, or an opted-in app wallet).
  int get _localKeyCount =>
      (_isCoordinator ? 0 : 1) + _importSlots.where((s) => s.isLocalKey).length;

  /// The creator's own generated key (co-signer role only) — key 1, which has
  /// no import slot to hold its label.
  var _creatorLabel = const CosignerLabel(id: '');

  /// Writes the labels once the wallet exists and its keys have fingerprints
  /// to key on. Nothing here can fail the creation: a wallet without names is
  /// a wallet, a name without a wallet is nothing.
  Future<void> _saveLabels(String walletId, List<String> cosignerKeys) async {
    final labels = <String, CosignerLabel>{};
    final ordered = _isCoordinator
        ? [for (final s in _importSlots) s.label]
        : [_creatorLabel, for (final s in _importSlots) s.label];
    for (var i = 0; i < cosignerKeys.length && i < ordered.length; i++) {
      final id = cosignerId(cosignerKeys, i);
      final label = ordered[i].copyWith();
      if (!label.isEmpty) {
        labels[id] = CosignerLabel(
          id: id,
          name: label.name,
          iconId: label.iconId,
          colorValue: label.colorValue,
          hardware: label.hardware,
        );
      }
    }
    if (labels.isEmpty) return;
    try {
      await CosignerLabelStore.instance.save(walletId, labels);
    } catch (_) {
      // Names are a convenience; losing them must never look like a failed
      // wallet creation.
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      // Collect every local signing key: the generated creator key, keys whose
      // seed lives in this wallet, and app wallets the user opted in — one
      // sign pass covers them all.
      final localMnemonics = <String>[];
      if (!_isCoordinator && _creatorMnemonic != null) {
        localMnemonics.add(_creatorMnemonic!.join(' '));
      }
      // A watch-only wallet never signs from this computer — keep the local
      // key list empty so the backend creates a watch-only coordinator.
      if (!_isWatchOnly) {
        for (final s in _importSlots) {
          if (!s.isLocalKey) continue;
          if (s.mnemonic != null) {
            localMnemonics.add(s.mnemonic!.join(' '));
          } else if (s.walletId != null) {
            final words = await _bridge.getMnemonic(s.walletId!);
            localMnemonics.add(words.join(' '));
          }
        }
      }

      final wallet = await _bridge.createMultisigWallet(
        name: _nameController.text.trim(),
        requiredSigs: _m,
        totalSigners: _n,
        cosignerXpubs: _allXpubs,
        localMnemonics: localMnemonics.isEmpty ? null : localMnemonics,
        // Empty unless every co-signer's Liquid key is in hand: the backend
        // treats a short list as an error rather than quietly building a
        // weaker wallet.
        liquidXpubs: _liquidReady ? _allLiquidXpubs : const [],
        liquidCapableKeys: _liquidReady ? _liquidCapableKeys : null,
      );
      await _saveLabels(wallet.id, _allXpubs);
      if (mounted) {
        context.read<AppState>().setActiveWallet(
          wallet.id,
          name: wallet.name,
          type: 'Multisig',
          // From the summary the backend returned, not from what was asked
          // for: a Liquid side the backend declined to build must not leave
          // the app showing Liquid screens with nothing behind them.
          liquid: wallet.liquidEnabled,
        );
        setState(() => _creating = false);
        _goTo(_Stage.success);
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

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StepFlowScaffold(
      currentStep: widget.baseStep + _stageIndex + 1,
      totalSteps: widget.baseStep + _stages.length,
      title: _stageTitle,
      subtitle: _stageSubtitle,
      onBack: _stage == _Stage.success
          ? null
          : (_stageIndex > 0 ? _back : _exitToWizard),
      onCancel: _stage != _Stage.success
          ? () => context.go(AppRoutes.walletPicker)
          : null,
      // No Liquid banner here any more: the wizard's coins question is asked
      // *after* the structure question and states outright that multisig is
      // Bitcoin-only, so by this point it has already been answered rather
      // than contradicted.
      banner: null,
      headerVariants: [
        for (final stage in _Stage.values)
          StepHeaderVariant(_titleOfStage(stage), _subtitleOfStage(stage)),
        // Both wordings of the import step, for the reason on [_importSubtitle].
        StepHeaderVariant(
          _titleOfStage(_Stage.importKeys),
          _importSubtitle(true),
        ),
        StepHeaderVariant(
          _titleOfStage(_Stage.importKeys),
          _importSubtitle(false),
        ),
      ],
      body: _stageBody(),
      actions: _stageActions,
    );
  }

  String get _stageTitle => _titleOfStage(_stage);

  String _titleOfStage(_Stage stage) => switch (stage) {
    _Stage.threshold => 'Choose your threshold',
    _Stage.seedLength => 'Create your key',
    _Stage.backup => 'Back up your key',
    _Stage.verify => 'Verify your backup',
    _Stage.importKeys => 'Import the keys',
    _Stage.review => 'Review and create',
    _Stage.success => 'Multisig wallet created',
  };

  String get _stageSubtitle => _subtitleOfStage(_stage);

  String _subtitleOfStage(_Stage stage) => switch (stage) {
    _Stage.threshold => "You'll need $_m keys out of $_n to sign a transaction",
    _Stage.seedLength =>
      'This key stays on this device so you can sign — choose its seed length',
    _Stage.backup =>
      'Write these words on paper. They are your key. Shown only once.',
    _Stage.verify => 'Enter the requested words to prove you saved them',
    _Stage.importKeys => _importSubtitle(_isCoordinator),
    _Stage.review => 'Check everything before the wallet is created',
    _Stage.success => '',
  };

  /// The import step's subtitle. Takes the role rather than reading it, so
  /// the header can reserve room for either wording — the toggle that picks
  /// between them sits on the step before, and flipping it must not move the
  /// header under the finger that flipped it.
  String _importSubtitle(bool coordinator) => _isWatchOnly
      ? 'Provide all $_n cosigner keys — paste/scan an xpub, or read one from a USB device'
      : coordinator
      ? 'Provide all $_n keys — an xpub, a USB device, or a private key held here'
      : 'Provide the other ${_n - 1} keys — an xpub, a USB device, or another private key of yours';

  Widget _stageBody() {
    if (_generatingKey) return const _Spinner(label: 'Generating secure key…');
    if (_creating) return const _Spinner(label: 'Creating wallet…');
    return switch (_stage) {
      _Stage.threshold => _thresholdBody(),
      _Stage.seedLength => _seedLengthBody(),
      _Stage.backup => _backupBody(),
      _Stage.verify => _verifyBody(),
      _Stage.importKeys => _importBody(),
      _Stage.review => _summaryBody(),
      _Stage.success => _successBody(),
    };
  }

  Widget get _stageActions {
    if (_generatingKey || _creating) return const SizedBox.shrink();
    if (_stage == _Stage.success) {
      return _StepActions(
        label: 'Open wallet',
        onPressed: () => context.go(AppRoutes.dashboard),
      );
    }
    final (label, enabled, onNext) = switch (_stage) {
      _Stage.threshold => (
        'Continue',
        _nameController.text.trim().isNotEmpty,
        _advanceFromThreshold,
      ),
      _Stage.seedLength => ('Continue', !_generatingKey, _generateCreatorKey),
      _Stage.backup => ('Continue', true, () async => _goTo(_Stage.verify)),
      _Stage.verify => ('Continue', !_busy, _verifyAndContinue),
      _Stage.importKeys => (
        'Continue',
        _importsComplete && !_busy,
        () async => _goTo(_Stage.review),
      ),
      _Stage.review => (
        _creating ? 'Creating…' : 'Create wallet',
        !_creating,
        _create,
      ),
      _Stage.success => ('', false, () async {}),
    };
    return _StepActions(
      label: label,
      onPressed: enabled ? () => onNext() : null,
      // Always in the row, so nothing beside it moves between steps.
      onBack: _stageIndex > 0 ? _back : _exitToWizard,
      reason: enabled ? null : _blockedReason,
    );
  }

  /// Why Continue is off, said beside it — a dimmed button alone leaves the
  /// user hunting for what the step still wants.
  String? get _blockedReason => switch (_stage) {
    _Stage.threshold => 'Name the wallet to continue',
    _Stage.importKeys => _importBlockedReason,
    _ => null,
  };

  /// The first thing [_importsComplete] is still waiting for, in its order.
  String? get _importBlockedReason {
    if (_busy) return null;
    final all = _allXpubs;
    if (all.any((x) => x.isEmpty)) return 'Import every key to continue';
    if (_importSlots.any((s) => !s.isReady)) {
      return 'Confirm the new key is written down to continue';
    }
    if (all.toSet().length != all.length) {
      return 'The same key is in two slots';
    }
    if (_liquidPossible && !_liquidReady) {
      return 'Add every Liquid key to continue';
    }
    return null;
  }

  // ── Threshold — name + M-of-N ─────────────────────────────────────────────

  Widget _thresholdBody() {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The label sits above the field rather than floating inside it: a
        // floating label rides up over the field's top edge, and at the top
        // of the step's scroll view that edge is where it was clipped.
        const _FieldLabel('Wallet name'),
        TextField(
          controller: _nameController,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.xl),
        // One card, two rows, each a stepper. Stacked rather than side by
        // side, so a phone and a desktop read it the same way and nothing
        // here needs a flexed child in the scroll view's unbounded axis.
        _ThresholdCard(
          m: _m,
          n: _n,
          onM: (v) => setState(() => _m = v),
          onN: (v) => setState(() {
            _n = v;
            if (_m > _n) _m = _n;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        _PolicyPreview(m: _m, n: _n),
        const SizedBox(height: AppSpacing.sm),
        // Neutral information, so it is drawn as such: a quiet line, not a
        // bordered box that reads as an alert.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 20,
              child: Icon(
                Icons.info_outlined,
                size: AppSpacing.iconSmall,
                color: s.inkSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This will be a $_m-of-$_n wallet: $_n keys exist in total, '
                'and any $_m of them must sign before bitcoin can move',
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        // Where the keys come from is chosen key by key on the import step.
        // The one thing worth settling first is whether this wallet holds one
        // of them itself, because that key is created and backed up before
        // the others are collected.
        _RoleRow(
          n: _n,
          watchOnly: _isWatchOnly,
          holdsKey: _holdsKey,
          onHoldsKeyChanged: (v) => setState(() => _holdsKey = v),
        ),
      ],
    );
  }

  // ── Seed length for the creator's key ────────────────────────────────────

  Widget _seedLengthBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableOptionCard(
          title: '12 words',
          description:
              '128 bits of entropy. Standard for most wallets. Easier to back up.',
          isSelected: _seedLength == 12,
          icon: Icons.lock_outlined,
          onTap: () => setState(() => _seedLength = 12),
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableOptionCard(
          title: '24 words',
          description:
              '256 bits of entropy. Maximum security. Recommended for large holdings.',
          isSelected: _seedLength == 24,
          icon: Icons.security_outlined,
          onTap: () => setState(() => _seedLength = 24),
        ),
        const SizedBox(height: AppSpacing.xl),
        const InfoBanner(
          message:
              'This is your personal key in the multisig. It works exactly '
              'like a software wallet seed — keep it offline and safe.',
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          DangerBanner(title: 'Key generation failed', message: _error!),
        ],
      ],
    );
  }

  // ── Back up the creator's seed ───────────────────────────────────────────

  Widget _backupBody() {
    final mnemonic = _creatorMnemonic ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WarningBanner(
          title: 'Write these words down on paper',
          message:
              'Never type or photograph your seed phrase. Anyone who sees it can steal your funds. This is shown only once.',
        ),
        const SizedBox(height: AppSpacing.xl),
        _WordGrid(words: mnemonic),
      ],
    );
  }

  // ── Verify the back-up ───────────────────────────────────────────────────

  Widget _verifyBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const InfoBanner(
          message:
              'Enter the words at the requested positions to confirm you have them saved.',
        ),
        const SizedBox(height: AppSpacing.xl),
        for (final i in _challengeIndexes)
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
                  style: AppTypography.mono.copyWith(
                    color: AppScheme.of(context).ink,
                  ),
                  onChanged: (v) => setState(() => _challengeAnswers[i] = v),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Import keys ──────────────────────────────────────────────────────────

  /// A slot counts as provided once it has resolved to a key the engine
  /// accepts. A pasted key that has not been checked yet does not count —
  /// "provided" has to mean "will build a wallet that opens".
  bool _slotFilled(_ImportSlot slot) {
    if (slot.resolvedXpub.isEmpty || !slot.isReady) return false;
    if (slot.source != _ImportSource.paste) return true;
    if (slot.keyInfo == null || slot.keyError != null) return false;
    if (_liquidWanted && slot.liquidPasteCtrl.text.trim().isNotEmpty) {
      return slot.liquidKeyInfo != null && slot.liquidKeyError == null;
    }
    return true;
  }

  /// Runs the engine's own key check over a slot's pasted fields.
  ///
  /// The same rules wallet creation applies, run while the user is still
  /// looking at the field: a key that only fails at creation costs the whole
  /// wizard, and one that fails at *open* costs a wallet entry that cannot be
  /// removed from the sidebar.
  Future<void> _checkSlotKeys(_ImportSlot slot) async {
    final btc = slot.pasteCtrl.text.trim();
    final liquid = slot.liquidPasteCtrl.text.trim();
    setState(() {
      slot.checking = true;
      slot.clearKeyChecks();
    });
    try {
      if (btc.isNotEmpty) {
        try {
          slot.keyInfo = await _bridge.validateCosignerKey(btc);
        } catch (e) {
          slot.keyError = _plainError(e);
        }
      }
      if (_liquidWanted && liquid.isNotEmpty) {
        try {
          slot.liquidKeyInfo = await _bridge.validateCosignerKey(
            liquid,
            liquid: true,
          );
        } catch (e) {
          slot.liquidKeyError = _plainError(e);
        }
      }
    } finally {
      if (mounted) setState(() => slot.checking = false);
    }
  }

  /// Check the slot's keys and, if they hold up, move on to the next one.
  /// The wizard's "Done" for a key placed by hand — every other source
  /// advances on its own once the device or the app has answered.
  Future<void> _confirmSlot(int i) async {
    final slot = _importSlots[i];
    await _checkSlotKeys(slot);
    if (!mounted) return;
    if (_slotFilled(slot)) _advanceFromSlot(i);
  }

  static String _plainError(Object e) =>
      e.toString().replaceFirst('Exception: wallet-ffi: ', '');

  /// After a key lands, open the next one still missing — the step reads as a
  /// queue of keys to collect rather than a wall of identical cards.
  void _advanceFromSlot(int i) {
    for (var j = i + 1; j < _importSlots.length; j++) {
      if (!_slotFilled(_importSlots[j])) {
        setState(() => _expandedSlot = j);
        return;
      }
    }
    setState(() => _expandedSlot = i);
  }

  /// What a slot's right-hand state says.
  _KeyStatus _statusOf(_ImportSlot slot) {
    if (slot.checking) return _KeyStatus.checking;
    if (slot.hasKeyProblem) return _KeyStatus.refused;
    if (slot.source == _ImportSource.newKey &&
        slot.mnemonic != null &&
        !slot.backedUp) {
      return _KeyStatus.backup;
    }
    if (!_slotFilled(slot)) return _KeyStatus.empty;
    return slot.source == _ImportSource.newKey
        ? _KeyStatus.created
        : _KeyStatus.imported;
  }

  /// The fingerprint a slot's key is known by, when there is one to show.
  static String? _fingerprintOf(_ImportSlot slot) =>
      slot.keyInfo?.fingerprint ?? _KeyOrigin.of(slot.resolvedXpub).fingerprint;

  Widget _importBody() {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    // Co-signer role: Key 1 is the generated key, imports start at Key 2.
    final firstKeyNumber = _isCoordinator ? 1 : 2;
    final filled = _importSlots.where(_slotFilled).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$filled of ${_importSlots.length} keys imported',
          style: AppTypography.label.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        // One card, one row per key. The row being worked on opens in place;
        // the others stay one line saying whether they are filled, so the
        // list still answers "how far am I" at a glance.
        ListCard(
          children: [
            // Key 1 belongs to this device and never appears as an import
            // slot, so it would otherwise be the one key that could not be
            // named.
            if (!_isCoordinator) _creatorRow(),
            for (var i = 0; i < _importSlots.length; i++)
              _slotRow(i, firstKeyNumber + i, phone),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        InfoBanner(
          message: _isWatchOnly
              ? 'Ask each co-signer for their xpub — paste or scan it, read it '
                    'from a USB device, or reuse a software wallet already in '
                    'this app. No key is stored here.'
              : _isCoordinator
              ? 'Every key is chosen on its own: read over USB, pasted or '
                    'scanned from an air-gapped signer, borrowed from another '
                    'wallet in this app, or created here as "New key" / '
                    '"Seed phrase" — a slot set to either of those is a '
                    'private key this wallet signs with.'
              : 'Key 1 is the one you just created on this device. Any slot set '
                    'to "New key", "Seed phrase", or an app wallet marked "signs '
                    'from this app" is another private key of this wallet — one '
                    'sign action signs with all of them.',
        ),
        if (_liquidWanted) ...[
          const SizedBox(height: AppSpacing.md),
          if (_liquidBlockedReason != null)
            WarningBanner(
              title: 'Liquid is not available for this wallet',
              message: _liquidBlockedReason!,
            )
          else
            const InfoBanner(
              title: 'Bitcoin + Liquid',
              message:
                  'Each co-signer contributes two keys: a Bitcoin one '
                  "(m/48'/1'/0'/2') and a Liquid one (m/87'/1'/0'). Keys "
                  'whose seed is in this app, and keys read from a Jade, '
                  'provide both without extra work — only a key pasted from '
                  'someone else has to be sent twice.',
            ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          DangerBanner(message: _error!),
        ],
      ],
    );
  }

  /// Key 1 in the co-signer role: generated here, so there is nothing to
  /// import — only a name to give it.
  Widget _creatorRow() {
    final open = _expandedSlot == -1;
    final key = _creatorXpub ?? '';
    return _SlotRow(
      keyNumber: 1,
      label: _creatorLabel,
      subtitle: 'Your key, created here',
      localKey: true,
      state: _KeyState(
        status: key.isEmpty ? _KeyStatus.empty : _KeyStatus.created,
        fingerprint: _KeyOrigin.of(key).fingerprint,
      ),
      onTap: open ? null : () => setState(() => _expandedSlot = -1),
      child: open
          ? _CosignerNameField(
              label: _creatorLabel,
              keyNumber: 1,
              subtitle: 'Generated here, in this wallet',
              onChanged: (l) => setState(() => _creatorLabel = l),
            )
          : null,
    );
  }

  Widget _slotRow(int i, int keyNumber, bool phone) {
    final slot = _importSlots[i];
    final open = i == _expandedSlot;
    return _SlotRow(
      keyNumber: keyNumber,
      label: slot.label,
      subtitle: _slotSummary(slot, phone: phone),
      localKey: slot.isLocalKey,
      state: _KeyState(
        status: _statusOf(slot),
        fingerprint: _fingerprintOf(slot),
      ),
      onTap: open ? null : () => setState(() => _expandedSlot = i),
      child: !open
          ? null
          : _ImportSlotBody(
              keyNumber: keyNumber,
              slot: slot,
              appWallets: _appWallets,
              allowLocalSigning: !_isWatchOnly,
              liquidWanted: _liquidWanted,
              busy: _busy,
              onSourceChanged: (src) => setState(() {
                final s = _importSlots[i];
                s.source = src;
                s.xpub = null;
                s.liquidXpub = null;
                s.walletId = null;
                s.hwModel = null;
                s.mnemonic = null;
                s.backedUp = false;
                s.clearKeyChecks();
                // Start the icon off at something the source suggests. Only
                // when the user has not picked one — their choice outranks
                // the guess.
                if (s.label.iconId == null) {
                  s.label = s.label.copyWith(
                    iconId: suggestedIconFor(
                      fromDevice: src == _ImportSource.hardware,
                      fromAppWallet: src == _ImportSource.appWallet,
                      isLocalSeed:
                          src == _ImportSource.newKey ||
                          src == _ImportSource.seedPhrase,
                    ),
                  );
                }
                // The source says where the key signs; a hardware slot is
                // flagged outright, any other source drops a stale flag.
                s.label = s.label.copyWith(
                  hardware: src == _ImportSource.hardware ? true : null,
                );
                // A watch-only wallet stays watch-only on this computer,
                // even when an app wallet lends its xpub.
                s.signsLocally = !_isWatchOnly;
              }),
              onAppWalletPicked: (id) async {
                await _pickAppWallet(_importSlots[i], id);
                if (mounted && _slotFilled(_importSlots[i])) {
                  _advanceFromSlot(i);
                }
              },
              onFetchHw: () async {
                await _fetchHwXpub(_importSlots[i]);
                if (mounted && _slotFilled(_importSlots[i])) {
                  _advanceFromSlot(i);
                }
              },
              onConfirm: () => _confirmSlot(i),
              onLabelChanged: (label) =>
                  setState(() => _importSlots[i].label = label),
              onGenerateKey: () => _generateSlotKey(_importSlots[i]),
              onUseSeed: () async {
                await _useSlotSeed(_importSlots[i]);
                if (mounted && _slotFilled(_importSlots[i])) {
                  _advanceFromSlot(i);
                }
              },
              // Any edit invalidates the verdict shown next to it: a tick
              // beside a key that has since been retyped is worse than none.
              onChanged: () => setState(() => _importSlots[i].clearKeyChecks()),
            ),
    );
  }

  // ── Summary ──────────────────────────────────────────────────────────────

  Widget _summaryBody() {
    final s = AppScheme.of(context);
    final xpubs = _allXpubs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FactsCard(
          facts: [
            ('Wallet name', _nameController.text.trim()),
            ('Policy', '$_m of $_n signatures'),
            (
              'Keys held here',
              _localKeyCount == 0
                  ? 'None'
                  : '$_localKeyCount signing key${_localKeyCount == 1 ? '' : 's'}',
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'Keys',
            style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
          ),
        ),
        ListCard(
          children: [
            for (var i = 0; i < xpubs.length; i++) _reviewRow(i, xpubs[i]),
          ],
        ),
        if (_liquidReady) ...[
          const SizedBox(height: AppSpacing.lg),
          InfoBanner(
            title: 'Bitcoin + Liquid',
            message:
                'One wallet on both chains: a $_m-of-$_n Bitcoin '
                'multisig and a $_m-of-$_n Liquid multisig with a shared '
                'blinding key.'
                '${_hasPastedKey ? ' Pasted keys cannot be checked from here — only software wallets and a Blockstream Jade can sign on Liquid, so confirm with those co-signers that they can.' : ''}',
          ),
        ] else if (_liquidWanted) ...[
          const SizedBox(height: AppSpacing.lg),
          WarningBanner(
            title: 'Bitcoin only',
            message:
                _liquidBlockedReason ??
                'The Liquid keys are incomplete, so this wallet will hold '
                    'Bitcoin only.',
          ),
        ],
        if (!_isWatchOnly && _localKeyCount == 0) ...[
          const SizedBox(height: AppSpacing.lg),
          const InfoBanner(
            title: 'Coordinator — no key on this device',
            message:
                'None of the keys you provided is held here, so this '
                'wallet cannot sign on its own. Transactions are signed with '
                'your devices — via USB or air-gap QR — in the co-sign flow.',
          ),
        ] else if (_isWatchOnly) ...[
          const SizedBox(height: AppSpacing.lg),
          const WarningBanner(
            title: 'Watch-only',
            message:
                'No key is stored here — this app cannot sign. You can build '
                'transactions and pass them to co-signers.',
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          DangerBanner(title: 'Creation failed', message: _error!),
        ],
      ],
    );
  }

  /// One key of the policy: its name, where it came from and the account it
  /// sits at, and the fingerprint a signing device knows it by.
  Widget _reviewRow(int i, String xpub) {
    final s = AppScheme.of(context);
    final creator = !_isCoordinator && i == 0;
    final slot = creator ? null : _importSlots[_isCoordinator ? i : i - 1];
    final label = slot?.label ?? _creatorLabel;
    final origin = _KeyOrigin.of(xpub);
    final fingerprint = slot?.keyInfo?.fingerprint ?? origin.fingerprint;
    final path = slot?.keyInfo != null
        ? 'm/${slot!.keyInfo!.path}'
        : origin.path;
    return ListRow(
      icon: label.icon,
      title: label.displayName(i),
      subtitle: path == null ? _originLabel(i) : '${_originLabel(i)} · $path',
      trailing: fingerprint != null
          ? Text(
              fingerprint,
              style: AppTypography.mono.copyWith(color: s.inkSecondary),
            )
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: HexText(xpub, truncate: true),
            ),
    );
  }

  /// One line describing a slot: where its key came from, and the account
  /// it sits at once there is one to show. The fingerprint sits in the row's
  /// state on a desktop; a phone has no room for it there, so it rides here.
  String _slotSummary(_ImportSlot slot, {required bool phone}) {
    final source = switch (slot.source) {
      _ImportSource.paste => 'Pasted or scanned',
      _ImportSource.appWallet => 'App wallet',
      _ImportSource.hardware => 'USB device (${slot.hwModel ?? 'hardware'})',
      _ImportSource.newKey => 'New private key',
      _ImportSource.seedPhrase => 'Seed phrase',
    };
    final key = slot.resolvedXpub;
    if (key.isEmpty) return source;
    if (slot.source == _ImportSource.newKey && !slot.backedUp) {
      return '$source · write the words down to continue';
    }
    // A checked key is named by what identifies it to a signing device — the
    // fingerprint and the account — not by the tail of its base58.
    final info = slot.keyInfo;
    if (info != null) {
      return phone
          ? '$source · ${info.fingerprint} · m/${info.path}'
          : '$source · m/${info.path}';
    }
    final origin = _KeyOrigin.of(key);
    if (origin.path != null) {
      return phone && origin.fingerprint != null
          ? '$source · ${origin.fingerprint} · ${origin.path}'
          : '$source · ${origin.path}';
    }
    final tail = key.length > 12 ? key.substring(key.length - 12) : key;
    return '$source · …$tail';
  }

  /// Whether any key came in as a pasted xpub — the one source whose ability
  /// to sign on Liquid this app cannot verify.
  bool get _hasPastedKey =>
      _importSlots.any((s) => s.source == _ImportSource.paste);

  String _originLabel(int i) {
    if (!_isCoordinator && i == 0) return 'Your key, on this device';
    final slot = _importSlots[_isCoordinator ? i : i - 1];
    return switch (slot.source) {
      _ImportSource.paste => 'Imported key',
      _ImportSource.appWallet =>
        slot.signsLocally
            ? 'App wallet, signs from this app'
            : 'App wallet, xpub only',
      _ImportSource.hardware => 'USB device (${slot.hwModel ?? 'hardware'})',
      _ImportSource.newKey => 'New private key, on this device',
      _ImportSource.seedPhrase => 'Imported seed, on this device',
    };
  }

  // ── Success ──────────────────────────────────────────────────────────────

  Widget _successBody() {
    return WalletCreatedView(
      walletName: _nameController.text.trim(),
      subtitle: _localKeyCount == 0
          ? '$_m-of-$_n multisig — no key here; sign with your devices via USB or air-gap QR'
          : '$_m-of-$_n multisig — $_m keys required to spend',
      details: [
        WalletCreatedDetail('Type', '$_m-of-$_n multisig'),
        WalletCreatedDetail(
          'Local keys',
          _localKeyCount == 0
              ? (_isWatchOnly
                    ? 'none (watch-only coordinator)'
                    : 'none — your devices sign (USB or air-gap QR)')
              : '$_localKeyCount signing key${_localKeyCount == 1 ? '' : 's'} on this device',
        ),
        for (var i = 0; i < _allXpubs.length; i++)
          WalletCreatedDetail('Key ${i + 1}', _allXpubs[i], mono: true),
      ],
    );
  }
}

// ── Shared pieces of the step ────────────────────────────────────────────────

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
  });

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onBack;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final why = reason;
    final back = onBack;
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
        PrimaryButton(label: label, onPressed: onPressed),
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

/// The fingerprint and account a key carries in its origin,
/// `[f0b68896/48'/1'/0'/2']tpub…`. Read for display only — the engine's own
/// check ([CosignerKeyInfo]) is what decides whether a key is usable.
class _KeyOrigin {
  const _KeyOrigin(this.fingerprint, this.path);

  final String? fingerprint;

  /// `m/48'/1'/0'/2'`, or null when the key carries no origin.
  final String? path;

  static final _pattern = RegExp(r'^\[([0-9a-fA-F]{8})(/[^\]]*)?\]');

  static _KeyOrigin of(String key) {
    final match = _pattern.firstMatch(key.trim());
    if (match == null) return const _KeyOrigin(null, null);
    final rest = match.group(2);
    return _KeyOrigin(
      match.group(1)!.toLowerCase(),
      rest == null || rest.length < 2 ? null : 'm$rest',
    );
  }
}

// ── Threshold pieces ─────────────────────────────────────────────────────────

/// "Signatures required" and "Total keys" as two rows of one card, each a
/// stepper.
class _ThresholdCard extends StatelessWidget {
  const _ThresholdCard({
    required this.m,
    required this.n,
    required this.onM,
    required this.onN,
  });

  final int m;
  final int n;
  final ValueChanged<int> onM;
  final ValueChanged<int> onN;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        children: [
          _StepperRow(
            label: 'Signatures required',
            value: m,
            min: 1,
            max: n,
            onChanged: onM,
          ),
          Divider(height: 1, thickness: 1, color: s.edge, indent: kListPad),
          _StepperRow(
            label: 'Total keys',
            value: n,
            min: 2,
            max: 9,
            onChanged: onN,
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      label: label,
      value: '$value',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: kListPad,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.bodyOf(context).copyWith(color: s.ink),
              ),
            ),
            _StepButton(
              icon: Icons.remove_outlined,
              tooltip: 'Fewer',
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            SizedBox(
              width: AppSpacing.xxxl,
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: AppTypography.balanceMediumOf(
                  context,
                ).copyWith(color: s.ink),
              ),
            ),
            _StepButton(
              icon: Icons.add_outlined,
              tooltip: 'More',
              onPressed: value < max ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// A 32 px outlined icon button (48 dp on a phone) — the `−` and `+` of a
/// stepper. Built like the kit's buttons: hover is a state layer, keyboard
/// focus a ring.
class _StepButton extends StatefulWidget {
  const _StepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final enabled = widget.onPressed != null;
    final side = phone ? AppLayout.minTouchTarget : AppSpacing.xxl;
    final radius = phone ? AppSpacing.radiusPhoneControl : AppSpacing.radiusMd;
    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled && _hover ? s.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: enabled ? s.edgeStrong : s.edge),
      ),
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Icon(
        widget.icon,
        size: phone ? 20 : AppSpacing.iconSmall,
        color: !enabled ? s.inkFaint : (_hover ? s.ink : s.inkSecondary),
      ),
    );
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.tooltip,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: body,
        ),
      ),
    );
    return phone ? button : Tooltip(message: widget.tooltip, child: button);
  }
}

/// The policy at a glance: n key glyphs, the first m in the primary ink —
/// keys, not seals, because nothing has been signed.
class _PolicyPreview extends StatelessWidget {
  const _PolicyPreview({required this.m, required this.n});

  final int m;
  final int n;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      label: '$m of $n keys must sign',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < n; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Icon(
                Icons.key_outlined,
                size: AppSpacing.icon,
                color: i < m ? s.ink : s.inkFaint,
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '$m of $n',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// Whether one of the keys is held here — or, for a watch-only coordinator,
/// the fact that none is.
class _RoleRow extends StatelessWidget {
  const _RoleRow({
    required this.n,
    required this.watchOnly,
    required this.holdsKey,
    required this.onHoldsKeyChanged,
  });

  final int n;

  /// A watch-only wallet has no choice to make: it holds nothing.
  final bool watchOnly;

  final bool holdsKey;
  final ValueChanged<bool> onHoldsKeyChanged;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final (icon, title, description) = watchOnly
        ? (
            Icons.visibility_outlined,
            'Watch-only coordinator',
            'You import all $n public keys. This app builds and inspects '
                'transactions but never signs.',
          )
        : holdsKey
        ? (
            Icons.phonelink_lock_outlined,
            'I hold one of these keys here',
            'Key 1 is generated on this device in the next step and backed '
                'up before you collect the other ${n - 1}.',
          )
        : (
            Icons.group_outlined,
            'I hold one of these keys here',
            'Off: all $n keys are imported. You can still keep a key here '
                '— set any slot to "New key" or "Seed phrase" while '
                'importing, or read one from a USB device.',
          );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Row(
        children: [
          ListIconTile(icon: icon),
          const SizedBox(width: kListGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                ),
                Text(
                  description,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ),
          ),
          if (!watchOnly) ...[
            const SizedBox(width: AppSpacing.md),
            ListSwitch(
              value: holdsKey,
              onChanged: onHoldsKeyChanged,
              semanticLabel: 'I hold one of these keys on this device',
            ),
          ],
        ],
      ),
    );
  }
}

/// Key/value facts on one card: the key in the secondary ink, the value in
/// the primary.
class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < facts.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: s.edge, indent: kListPad),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kListPad,
                vertical: AppSpacing.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      facts[i].$1,
                      style: AppTypography.label.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      facts[i].$2,
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
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: Padding(
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
              label,
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Word grid (seed back-up) ─────────────────────────────────────────────────

class _WordGrid extends StatelessWidget {
  const _WordGrid({required this.words});
  final List<String> words;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 40,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: words.length,
      itemBuilder: (context, i) => _WordTile(index: i + 1, word: words[i]),
    );
  }
}

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
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: s.edge),
      ),
      child: Row(
        children: [
          SizedBox(
            width: AppSpacing.xl,
            child: Text(
              '$index',
              style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            ),
          ),
          Expanded(
            child: Text(
              word,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.mono.copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
  }
}

// ── One key of the import list ───────────────────────────────────────────────

enum _KeyStatus { empty, checking, imported, created, refused, backup }

/// The right-hand state of a key row: what this slot holds, in a word.
class _KeyState extends StatelessWidget {
  const _KeyState({required this.status, this.fingerprint});

  final _KeyStatus status;
  final String? fingerprint;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final caption = AppTypography.caption;
    final fp = fingerprint;
    // A phone carries the fingerprint in the row's subtitle instead.
    final showFp = fp != null && !AppLayout.isPhone(context);
    Widget word(Color dot, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(dot),
        const SizedBox(width: AppSpacing.sm),
        Text(text, style: caption.copyWith(color: s.ink)),
      ],
    );
    switch (status) {
      case _KeyStatus.empty:
        return Text('Not imported', style: caption.copyWith(color: s.inkFaint));
      case _KeyStatus.checking:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: AppSpacing.md,
              height: AppSpacing.md,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('Checking', style: caption.copyWith(color: s.inkSecondary)),
          ],
        );
      case _KeyStatus.refused:
        return Text('Not accepted', style: caption.copyWith(color: s.danger));
      case _KeyStatus.backup:
        return word(s.warning, 'Back up the words');
      case _KeyStatus.imported:
      case _KeyStatus.created:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showFp) ...[
              Text(
                fp,
                style: AppTypography.mono.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            word(
              s.success,
              status == _KeyStatus.created ? 'Created' : 'Imported',
            ),
          ],
        );
    }
  }
}

/// 6 px status dot.
class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
  );
}

/// One key of the import list: a one-line row, and — for the key being worked
/// on — its controls opened in place under it.
class _SlotRow extends StatefulWidget {
  const _SlotRow({
    required this.keyNumber,
    required this.label,
    required this.subtitle,
    required this.localKey,
    required this.state,
    this.onTap,
    this.child,
  });

  final int keyNumber;

  /// What this key has been called, if anything. A named key is listed by
  /// its name — "Key 3" is only what an unnamed one falls back to.
  final CosignerLabel label;
  final String subtitle;

  /// The app holds this key's seed and signs with it.
  final bool localKey;
  final Widget state;

  /// Opens the row; null while it is the open one.
  final VoidCallback? onTap;

  /// The open row's controls.
  final Widget? child;

  @override
  State<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends State<_SlotRow> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final label = widget.label;
    final named = label.name?.trim().isNotEmpty ?? false;
    final onTap = widget.onTap;
    final child = widget.child;

    final header = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: onTap != null && _hover ? s.hover : Colors.transparent,
      foregroundDecoration: _focus && onTap != null
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: const BoxConstraints(minHeight: AppSpacing.rowHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          // The key's own glyph — and its colour, when the user gave it one:
          // that colour is how they tell their keys apart on every screen.
          Container(
            width: kListTile,
            height: kListTile,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.panelInset,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              label.icon,
              size: AppSpacing.icon,
              color: label.color ?? s.inkSecondary,
            ),
          ),
          const SizedBox(width: kListGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label.displayName(widget.keyNumber - 1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.bodyOf(
                          context,
                        ).copyWith(color: s.ink),
                      ),
                    ),
                    if (named) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'key ${widget.keyNumber}',
                        style: AppTypography.caption.copyWith(
                          color: s.inkFaint,
                        ),
                      ),
                    ],
                    if (widget.localKey && !phone) ...[
                      const SizedBox(width: AppSpacing.sm),
                      const QuietTag(label: 'Signs here'),
                    ],
                  ],
                ),
                Text(
                  widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          widget.state,
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.expand_more_outlined,
              size: AppSpacing.icon,
              color: s.inkFaint,
            ),
          ],
        ],
      ),
    );

    final tappable = onTap == null
        ? header
        : Semantics(
            button: true,
            child: MergeSemantics(
              child: FocusableActionDetector(
                mouseCursor: SystemMouseCursors.click,
                onShowHoverHighlight: (v) => setState(() => _hover = v),
                onShowFocusHighlight: (v) => setState(() => _focus = v),
                actions: <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) {
                      onTap();
                      return null;
                    },
                  ),
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: header,
                ),
              ),
            ),
          );

    if (child == null) return tappable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tappable,
        Padding(
          // Under the row's text on a desktop; the full card width on a
          // phone, where a 60 dp indent would cost a fifth of the column.
          padding: EdgeInsets.fromLTRB(
            phone ? kListPad : kListTextInset,
            AppSpacing.xs,
            kListPad,
            AppSpacing.lg,
          ),
          child: child,
        ),
      ],
    );
  }
}

// ── Import slot controls — paste/scan xpub, app wallet, USB device, … ────────

/// What the engine made of the key in the field above it.
///
/// Three states worth showing and one worth hiding: nothing before a key has
/// been checked, a spinner while it is, the fingerprint and path it resolved
/// to when it holds up, and the reason when it does not. The path matters as
/// much as the tick — a key at the wrong account builds a wallet that nobody
/// can ever sign for, and it is the one mistake neither end can detect later.
class _KeyVerdict extends StatelessWidget {
  const _KeyVerdict({
    required this.info,
    required this.error,
    required this.checking,
  });

  final CosignerKeyInfo? info;
  final String? error;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    if (checking) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          children: [
            const SizedBox(
              width: AppSpacing.md,
              height: AppSpacing.md,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Checking the key…',
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
      );
    }
    if (error != null) {
      return _line(
        context,
        Icon(Icons.error_outline, size: AppSpacing.iconSmall, color: s.danger),
        error!,
        s.danger,
      );
    }
    final info = this.info;
    if (info == null) return const SizedBox.shrink();
    if (info.warning != null) {
      return _line(
        context,
        Icon(
          Icons.warning_amber_outlined,
          size: AppSpacing.iconSmall,
          color: s.warning,
        ),
        '${info.fingerprint} · ${info.warning}',
        s.ink,
      );
    }
    return _line(
      context,
      _Dot(s.success),
      'Key ${info.fingerprint} at m/${info.path}',
      s.inkSecondary,
    );
  }

  Widget _line(BuildContext context, Widget mark, String text, Color ink) =>
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: AppSpacing.iconSmall,
              height: 20,
              child: Center(child: mark),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: AppTypography.caption.copyWith(color: ink),
              ),
            ),
          ],
        ),
      );
}

/// Name and glyph for one co-signer, inline in its row.
///
/// The field is the whole control: typing names the key, and the tile beside
/// it opens the icon and colour picker. Optional everywhere — an unnamed key
/// stays "Key N", which is what it was before any of this existed.
class _CosignerNameField extends StatefulWidget {
  const _CosignerNameField({
    required this.label,
    required this.keyNumber,
    required this.onChanged,
    this.subtitle,
  });

  final CosignerLabel label;
  final int keyNumber;
  final String? subtitle;
  final void Function(CosignerLabel) onChanged;

  @override
  State<_CosignerNameField> createState() => _CosignerNameFieldState();
}

class _CosignerNameFieldState extends State<_CosignerNameField> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.label.name ?? '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_CosignerNameField old) {
    super.didUpdateWidget(old);
    // The picker can set a name too; keep the field in step without stealing
    // the cursor from someone mid-word.
    final name = widget.label.name ?? '';
    if (name != _ctrl.text && !name.startsWith(_ctrl.text)) {
      _ctrl.text = name;
    }
  }

  Future<void> _editLook() async {
    final edited = await showCosignerLabelEditor(
      context,
      label: widget.label,
      index: widget.keyNumber - 1,
      subtitle: widget.subtitle,
    );
    if (edited == null) return;
    _ctrl.text = edited.name ?? '';
    widget.onChanged(edited);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone ? AppSpacing.phoneFieldHeight : AppSpacing.controlHeight;
    return Row(
      children: [
        Tooltip(
          message: 'Icon and colour',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _editLook,
              borderRadius: BorderRadius.circular(
                phone ? AppSpacing.radiusPhoneControl : AppSpacing.radiusMd,
              ),
              child: Container(
                width: side,
                height: side,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.panelInset,
                  borderRadius: BorderRadius.circular(
                    phone ? AppSpacing.radiusPhoneControl : AppSpacing.radiusMd,
                  ),
                  border: Border.all(color: s.edge),
                ),
                child: Icon(
                  widget.label.icon,
                  size: AppSpacing.icon,
                  color: widget.label.color ?? s.inkSecondary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            controller: _ctrl,
            maxLength: 40,
            decoration: const InputDecoration(
              hintText: 'Name this key (optional)',
              counterText: '',
            ),
            onChanged: (v) => widget.onChanged(
              widget.label.copyWith(name: v.trim().isEmpty ? null : v),
            ),
          ),
        ),
      ],
    );
  }
}

/// Paste the clipboard into a key field — the same as ⌘V / Ctrl+V, offered
/// as a control because the scan button beside it is absent where no camera
/// exists.
class _PasteButton extends StatelessWidget {
  const _PasteButton({required this.controller, required this.onPasted});

  final TextEditingController controller;
  final VoidCallback onPasted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Paste',
      iconSize: AppLayout.isPhone(context) ? 22 : AppSpacing.icon,
      icon: const Icon(Icons.content_paste_outlined),
      onPressed: () async {
        final data = await Clipboard.getData('text/plain');
        final text = data?.text?.trim();
        if (text == null || text.isEmpty) return;
        controller.text = text;
        onPasted();
      },
    );
  }
}

class _ImportSlotBody extends StatelessWidget {
  const _ImportSlotBody({
    required this.keyNumber,
    required this.slot,
    required this.appWallets,
    required this.allowLocalSigning,
    required this.liquidWanted,
    required this.busy,
    required this.onSourceChanged,
    required this.onAppWalletPicked,
    required this.onFetchHw,
    required this.onGenerateKey,
    required this.onUseSeed,
    required this.onChanged,
    required this.onConfirm,
    required this.onLabelChanged,
  });

  /// 1-based key number shown to the user.
  final int keyNumber;
  final _ImportSlot slot;
  final List<WalletSummary> appWallets;

  /// Whether this wallet may hold private keys at all (false = watch-only
  /// coordinator: only public keys can be imported).
  final bool allowLocalSigning;

  /// The wizard's coins answer. When true each key needs a Liquid (BIP87)
  /// counterpart, so the row asks for one — or explains why it cannot.
  final bool liquidWanted;
  final bool busy;
  final void Function(_ImportSource) onSourceChanged;
  final void Function(String walletId) onAppWalletPicked;
  final VoidCallback onFetchHw;
  final VoidCallback onGenerateKey;
  final VoidCallback onUseSeed;
  final VoidCallback onChanged;

  /// "Done" on a key typed or scanned by hand: check it, then move to the
  /// next key. Sources that talk to a device or the app advance themselves.
  final VoidCallback onConfirm;

  /// The user named this key, or picked an icon or colour for it.
  final void Function(CosignerLabel) onLabelChanged;

  /// Which key the naming dialog is about, in whatever terms are known yet:
  /// the checked fingerprint, else the device or wallet it came from.
  String? _labelSubtitle() {
    final info = slot.keyInfo;
    if (info != null) return '${info.fingerprint} · m/${info.path}';
    if (slot.hwModel case final model?) return model;
    return switch (slot.source) {
      _ImportSource.newKey => 'A new private key, generated on this device',
      _ImportSource.seedPhrase => 'A key restored from seed words',
      _ImportSource.appWallet => 'A key borrowed from a wallet in this app',
      _ImportSource.hardware => 'A key read from a USB device',
      _ImportSource.paste => 'A key pasted or scanned in',
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    Widget chip(_ImportSource source, String label) => ChoiceTile(
      label: label,
      selected: slot.source == source,
      onSelected: () => onSourceChanged(source),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Naming the key comes first: it is the only part of a co-signer a
        // person can hold in their head, and by the time the xpub is pasted
        // nobody wants to go back for it.
        _CosignerNameField(
          label: slot.label,
          keyNumber: keyNumber,
          subtitle: _labelSubtitle(),
          onChanged: onLabelChanged,
        ),
        const SizedBox(height: AppSpacing.lg),
        // Public sources first, then the private ones (a key this wallet
        // holds and signs with) — which a watch-only coordinator never sees.
        const _FieldLabel('Source'),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            chip(_ImportSource.paste, 'Paste or scan'),
            // Kept in place when no wallet can lend a key, with the reason on
            // it, so the row is the same shape every time.
            ChoiceTile(
              label: 'App wallet',
              selected: slot.source == _ImportSource.appWallet,
              onSelected: appWallets.isEmpty
                  ? null
                  : () => onSourceChanged(_ImportSource.appWallet),
              tooltip: appWallets.isEmpty
                  ? 'No software wallet in this app to lend a key'
                  : null,
            ),
            // USB only where a USB stack exists (not Android).
            if (!Platform.isAndroid) chip(_ImportSource.hardware, 'USB device'),
            if (allowLocalSigning) ...[
              chip(_ImportSource.newKey, 'New key'),
              chip(_ImportSource.seedPhrase, 'Seed phrase'),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        switch (slot.source) {
          _ImportSource.paste => _pasteSource(context),
          _ImportSource.appWallet => _appWalletSource(context),
          _ImportSource.hardware => _hardwareSource(context),
          _ImportSource.newKey => _newKeySource(context),
          _ImportSource.seedPhrase => _seedSource(context),
        },
        if (liquidWanted) ...[
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, thickness: 1, color: s.edge),
          const SizedBox(height: AppSpacing.lg),
          _liquidKeySection(context),
        ],
      ],
    );
  }

  Widget _pasteSource(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: slot.pasteCtrl,
                decoration: const InputDecoration(hintText: 'Cosigner xpub'),
                style: AppTypography.mono.copyWith(color: s.ink),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            _PasteButton(controller: slot.pasteCtrl, onPasted: onChanged),
            ScanIconButton(
              controller: slot.pasteCtrl,
              expectsKey: true,
              title: "Scan a cosigner xpub or an air-gapped device's QR",
              // A scanned key checks itself, the way a key read over USB
              // does — nobody scans a QR and then wonders whether to press
              // anything.
              onScanned: (_) => onConfirm(),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          "[fingerprint/48'/1'/0'/2']tpub…",
          style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
        ),
        _KeyVerdict(
          info: slot.keyInfo,
          error: slot.keyError,
          checking: slot.checking,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Wherever the key already is: another Templar wallet '
          '(this computer or your phone — Wallet info → "Use this '
          'wallet as a cosigner"), a key a co-signer sent you, or an '
          "air-gapped device's QR (SeedSigner, or a Jade in QR "
          'mode — unlock it first, a locked Jade only shows its '
          'PIN-unlock QR).',
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryButton(
            label: slot.checking ? 'Checking…' : 'Done with this key',
            icon: Icons.check_outlined,
            isLoading: slot.checking,
            onPressed: slot.checking || slot.pasteCtrl.text.trim().isEmpty
                ? null
                : onConfirm,
          ),
        ),
      ],
    );
  }

  Widget _appWalletSource(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: slot.walletId,
          items: appWallets
              .map((w) => DropdownMenuItem(value: w.id, child: Text(w.name)))
              .toList(),
          onChanged: (id) {
            if (id != null) onAppWalletPicked(id);
          },
          decoration: const InputDecoration(
            hintText: 'Choose a software wallet',
          ),
        ),
        if (allowLocalSigning && slot.walletId != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: slot.signsLocally,
            onChanged: (v) {
              slot.signsLocally = v ?? false;
              onChanged();
            },
            title: Text(
              'Sign with this key from this app',
              style: AppTypography.body.copyWith(color: s.ink),
            ),
            subtitle: Text(
              'One sign action will sign with every local key',
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ),
      ],
    );
  }

  Widget _hardwareSource(BuildContext context) {
    final s = AppScheme.of(context);
    final xpub = slot.xpub;
    if (xpub == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SecondaryButton(
          label: busy ? 'Reading…' : 'Read xpub from device',
          icon: Icons.usb_outlined,
          isLoading: busy,
          onPressed: busy ? null : onFetchHw,
        ),
      );
    }
    return Row(
      children: [
        Icon(Icons.usb_outlined, size: AppSpacing.icon, color: s.inkSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            slot.hwModel ?? 'Device',
            style: AppTypography.body.copyWith(color: s.ink),
          ),
        ),
        HexText(xpub, truncate: true),
        IconButton(
          tooltip: 'Read again',
          iconSize: AppSpacing.icon,
          icon: const Icon(Icons.refresh_outlined),
          onPressed: busy ? null : onFetchHw,
        ),
      ],
    );
  }

  // ── New private key: generated here, written down here ──────────────────
  Widget _newKeySource(BuildContext context) {
    final s = AppScheme.of(context);
    final words = slot.mnemonic;
    if (words == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SecondaryButton(
          label: busy ? 'Generating…' : 'Generate a new 24-word key',
          icon: Icons.add_moderator_outlined,
          isLoading: busy,
          onPressed: busy ? null : onGenerateKey,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const WarningBanner(
          title: 'Write these words down on paper',
          message:
              'This is a second private key of this wallet. Anyone who '
              'sees it can sign with it. Shown only once.',
        ),
        const SizedBox(height: AppSpacing.md),
        _WordGrid(words: words),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: slot.backedUp,
          onChanged: (v) {
            slot.backedUp = v ?? false;
            onChanged();
          },
          title: Text(
            'I wrote these words down',
            style: AppTypography.body.copyWith(color: s.ink),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: HexText(slot.xpub!, truncate: true),
        ),
      ],
    );
  }

  // ── Existing seed adopted as another private key ────────────────────────
  Widget _seedSource(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FieldLabel('Seed phrase (12 or 24 words)'),
        TextField(
          controller: slot.seedCtrl,
          maxLines: 3,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            hintText: 'abandon abandon … about',
          ),
          style: AppTypography.mono.copyWith(color: s.ink),
          onChanged: (_) => onChanged(),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            SecondaryButton(
              label: slot.xpub == null ? 'Use this seed' : 'Check again',
              icon: Icons.check_outlined,
              isLoading: busy,
              onPressed: busy ? null : onUseSeed,
            ),
            const SizedBox(width: AppSpacing.md),
            if (slot.xpub != null)
              Expanded(child: HexText(slot.xpub!, truncate: true)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'The seed is stored in this wallet and signs alongside your '
          'other keys. Keep the paper backup safe.',
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );
  }

  /// This co-signer's Liquid key.
  ///
  /// Derived without asking whenever the seed is reachable from here, read
  /// from a Jade over USB, and typed in only for a remote co-signer — the one
  /// case where the app has neither the seed nor the device.
  Widget _liquidKeySection(BuildContext context) {
    final s = AppScheme.of(context);
    Widget note(Widget mark, String text) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 20, child: Center(child: mark)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ),
      ],
    );

    if (slot.isBitcoinOnlyDevice) {
      return note(
        Icon(
          Icons.block_outlined,
          size: AppSpacing.iconSmall,
          color: s.warning,
        ),
        '${slot.hwModel ?? 'This device'} is Bitcoin-only — it cannot '
        'sign Liquid transactions. Including this key makes the whole '
        'wallet Bitcoin-only.',
      );
    }

    if (slot.source == _ImportSource.paste) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: slot.liquidPasteCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Cosigner Liquid key (BIP87)',
                  ),
                  style: AppTypography.mono.copyWith(color: s.ink),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _PasteButton(
                controller: slot.liquidPasteCtrl,
                onPasted: onChanged,
              ),
              ScanIconButton(
                controller: slot.liquidPasteCtrl,
                expectsKey: true,
                title: 'Scan cosigner Liquid key',
                onScanned: (_) => onConfirm(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            "[fingerprint/87'/1'/0']tpub…",
            style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
          ),
          _KeyVerdict(
            info: slot.liquidKeyInfo,
            error: slot.liquidKeyError,
            checking: slot.checking,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A second key from the same co-signer: Liquid uses account '
            "m/87'/1'/0', Bitcoin uses m/48'/1'/0'/2'. Neither can be "
            'computed from the other, so ask for both.',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
      );
    }

    final key = slot.liquidXpub;
    if (key == null) {
      return note(
        _Dot(s.inkFaint),
        slot.source == _ImportSource.hardware
            ? 'Liquid key is read from the Jade together with the Bitcoin one'
            : 'Liquid key is derived from this seed automatically',
      );
    }
    return Row(
      children: [
        _Dot(s.liquid),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Liquid key ready',
            style: AppTypography.body.copyWith(color: s.ink),
          ),
        ),
        HexText(key, truncate: true),
      ],
    );
  }
}
