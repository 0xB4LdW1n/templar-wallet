import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../app/back_handler.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../features/dashboard/models/dashboard_data.dart';
import '../../features/send/models/tx_preview.dart';
import '../../shared/amount_units.dart';
import '../../shared/payment_uri.dart';
import '../../shared/widgets/unit_chip.dart';
import '../hardware/hw_error.dart';
import '../hardware/ledger_connect_dialog.dart';
import '../hardware/ledger_signing_dialog.dart';
import '../psbt/cosign_handoff.dart';
import '../psbt/cosign_view.dart';
import 'own_address_dialog.dart';
import '../utxos/models/utxo.dart';
import '../../services/asset_registry_service.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/chain_switch.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/live_edge.dart';
import '../../shared/widgets/app_password_gate.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/psbt_sign_flow.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/tx_confirm_view.dart';
import '../../shared/widgets/tx_flow.dart';
import '../../shared/widgets/tx_success_view.dart';
import '../../shared/widgets/ur_qr.dart';
import '../../shared/widgets/utxo_views.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// What kind of send this is: build a new transaction from scratch, or load a
/// PSBT someone else started and add this wallet's signature to it.
enum _TxKind { standard, cosign }

/// The two moments of a standard send: everything that describes the
/// transaction on one page, then the built transaction to check and sign.
///
/// They replace a six-step wizard (Type, Network, Inputs, Outputs, Fee,
/// Review) whose middle steps were mostly one default choice each. The
/// checks those steps made before Review are all in [_SendScreenState
/// ._canReview]; the bridge calls and their order are unchanged.
enum _Stage { compose, review }

/// One recipient being edited on Compose.
class _OutputDraft {
  final addressCtrl = TextEditingController();
  final amountCtrl = TextEditingController();

  /// Per-output Liquid asset; null = LBTC (or plain Bitcoin on BTC sends).
  /// One Liquid transaction can carry different assets per output.
  AssetBalance? asset;

  /// Backend drain flag: "spend everything that is left, after the fee".
  /// Only BTC/LBTC can be drained, because the fee comes out of the same
  /// asset — the exact amount is not known until the preview builds.
  bool sendMax = false;

  /// MAX is engaged on this row. Distinct from [sendMax]: a token MAX is a
  /// concrete number (its whole balance, since the fee is paid in LBTC), so
  /// it never sets the drain flag but must still light up and toggle off.
  bool maxEngaged = false;

  /// Whatever was typed before MAX took the field over, restored on toggle-off
  /// so engaging MAX by accident costs nothing.
  String? amountBeforeMax;

  /// The amount field holds the selected fiat currency rather than coin.
  /// BTC / LBTC rows only — a token has no price to convert at. The wallet
  /// never sees fiat: [_SendScreenState._amountSatsOf] resolves it to sats
  /// at the spot price the moment it is read.
  bool fiatInput = false;

  /// The exact amount behind the text the last ⇅ flip wrote, and that text.
  /// Fiat has two decimals, so "0.0025 BTC" flips to "199.25" and would come
  /// back as 0.00250003; as long as the field still reads what the flip
  /// wrote, the amount is these sats, not a re-parse of the rounded text.
  int? flipSats;
  String? flipText;

  void dispose() {
    addressCtrl.dispose();
    amountCtrl.dispose();
  }
}

class SendScreen extends StatefulWidget {
  const SendScreen({super.key, this.startInCosign = false, this.bridge});

  /// Open directly in co-sign mode (used by the legacy /cosign deep link).
  final bool startInCosign;

  /// Test seam. Null in the app, where the global engine is used; a widget
  /// test hands in a stub so the wizard can be pumped without the native
  /// library or the user's wallet directory.
  final WalletBridge? bridge;

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;

  late _TxKind _kind = widget.startInCosign ? _TxKind.cosign : _TxKind.standard;
  _Stage _stage = _Stage.compose;

  /// Cosign was opened from Compose's link (not the deep link), so back
  /// returns to Compose instead of leaving the screen.
  bool _cosignFromCompose = false;

  /// Android back and the phone header's arrow: Review → Compose → leave.
  late final BackHandlerCallback _systemBack = _handleSystemBack;

  // Network (the chain switch)
  List<AssetBalance> _assets = [];
  AssetBalance? _selectedAsset;
  bool _loadingAssets = true;

  // Coins
  bool _manualInputs = false;
  List<Utxo> _utxos = [];
  bool _loadingUtxos = false;

  // Recipients
  final List<_OutputDraft> _outputs = [_OutputDraft()];

  // Fee
  String _feePreset = 'normal';
  final _customFeeCtrl = TextEditingController();
  static const _feeRates = {'slow': 1.0, 'normal': 3.0, 'fast': 8.0};

  // Review
  TxPreview? _preview;
  bool _previewing = false;
  bool _sending = false;
  String? _error;

  /// A device-signed PSBT whose broadcast has not succeeded yet. Held so a
  /// broadcast-only failure can be retried without a second on-device
  /// approval. Cleared the moment the transaction reaches the network.
  String? _pendingSignedPsbt;

  /// The transaction the retained PSBT was signed for. Reuse is allowed only
  /// when the user is still sending exactly that — edit the amount, the
  /// recipient, the fee or the coin selection and the retained signature is
  /// for a different transaction, which must never be the one broadcast.
  String? _pendingSignedKey;

  /// A fully-signed transaction whose broadcast failed, retained as
  /// (walletId, signed PSBT base64) so the user can retry the broadcast or
  /// copy the artifact out instead of losing the collected signatures.
  (String, String)? _failedBroadcast;

  @override
  void initState() {
    super.initState();
    BackHandler.instance.push(_systemBack);
    _loadAssets();
    // The amount field can be typed in fiat; make sure a price is there by
    // the time the user reaches it, and follow it while the screen is up.
    PriceService.instance
      ..addListener(_onPriceChanged)
      ..fetch();
  }

  @override
  void dispose() {
    BackHandler.instance.remove(_systemBack);
    PriceService.instance.removeListener(_onPriceChanged);
    for (final o in _outputs) {
      o.dispose();
    }
    _customFeeCtrl.dispose();
    super.dispose();
  }

  // ── data loading ────────────────────────────────────────────────────────────

  String get _walletId => context.read<AppState>().activeWalletId ?? 'wallet-1';

  Future<void> _loadAssets() async {
    try {
      final data = await _bridge.getWalletSummary(_walletId);
      if (mounted) {
        setState(() {
          // Air-gap wallets sign by QR, and there is no Liquid PSET QR flow,
          // so their Liquid assets are not offered at all — showing them let
          // the user reach the review step before anything objected.
          //
          // USB wallets are *not* filtered here: a Jade's Liquid wallet is a
          // hardware wallet whose only assets are Liquid ones, and a
          // Bitcoin-only device never has a Liquid side to show in the first
          // place, because pairing one is refused at creation.
          _assets = _signsBitcoinOnly
              ? data.assets.where((a) => a.ticker == 'BTC').toList()
              : data.assets;
          _selectedAsset ??= _assets.isNotEmpty ? _assets.first : null;
          _loadingAssets = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  /// Air-gap wallets sign a PSBT carried by QR, and no Liquid PSET QR flow
  /// exists — on either side of the glass. So Liquid is off the table for
  /// them regardless of which device it is, Jade included.
  ///
  /// USB is deliberately *not* included: a Jade signs Liquid over serial.
  bool get _signsBitcoinOnly => _isAirgapWallet;

  Future<void> _loadUtxos() async {
    setState(() => _loadingUtxos = true);
    try {
      final all = await _bridge.listUtxos(_walletId, 'BTC');
      // Spendable coins are pickable as inputs. Frozen ones are listed too,
      // locked with their chip, so the coins on screen still add up to the
      // balance; the engine would refuse them anyway.
      final spendable = all
          .where(
            (u) =>
                u.state == UtxoState.available ||
                u.state == UtxoState.dusty ||
                u.state == UtxoState.frozen,
          )
          .toList();
      if (mounted) {
        setState(() {
          _utxos = spendable;
          _loadingUtxos = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingUtxos = false);
    }
  }

  // ── derived state ───────────────────────────────────────────────────────────

  bool get _isBtc => _selectedAsset?.ticker == 'BTC';
  bool get _isBtcLike =>
      _selectedAsset?.ticker == 'BTC' || _selectedAsset?.ticker == 'LBTC';

  /// Assets spendable per-output on Liquid: LBTC first, then every token
  /// with a balance (reissuance tokens included — they are outputs too).
  List<AssetBalance> get _liquidSpendable => [
    ..._assets.where((a) => a.ticker == 'LBTC'),
    ..._assets.where(
      (a) => a.ticker != 'BTC' && a.ticker != 'LBTC' && a.amount > 0,
    ),
  ];

  /// The asset a given output row pays (LBTC when none picked).
  AssetBalance? _rowAsset(_OutputDraft o) =>
      _isBtc ? _selectedAsset : (o.asset ?? _selectedAsset);

  bool _rowIsBtcLike(_OutputDraft o) {
    final t = _rowAsset(o)?.ticker ?? 'BTC';
    return t == 'BTC' || t == 'LBTC';
  }

  String _rowTicker(_OutputDraft o) {
    final a = _rowAsset(o);
    if (a == null) return 'BTC';
    return a.ticker == 'LBTC' || a.ticker == 'BTC'
        ? a.ticker
        : AssetRegistryService.instance.displayTicker(a);
  }

  bool get _isHardwareWallet {
    final t = context.read<AppState>().activeWalletType ?? '';
    return t.startsWith('Hardware (') || t.toLowerCase().contains('hardware');
  }

  bool get _isAirgapWallet {
    final t = context.read<AppState>().activeWalletType ?? '';
    return t.toLowerCase().contains('air-gap') ||
        t.toLowerCase().contains('airgap');
  }

  bool get _isMultisigWallet {
    final t = context.read<AppState>().activeWalletType ?? '';
    return t.toLowerCase().contains('multisig');
  }

  double get _feeRate {
    if (_feePreset == 'custom') {
      final v = double.tryParse(_customFeeCtrl.text.trim());
      // Clamp to sane testnet bounds; fall back to normal when unparsable.
      if (v != null && v > 0) return v.clamp(0.1, 500.0);
      return 3.0;
    }
    return _feeRates[_feePreset] ?? 3.0;
  }

  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  /// Parses one output row's amount into sats/base units for the row's asset.
  int? _amountSatsOf(_OutputDraft o) {
    final text = o.amountCtrl.text;
    if (text.trim().isEmpty) return null;
    if (_rowIsBtcLike(o)) {
      // Untouched since a ⇅ flip: the flip's exact amount, not the rounded
      // text re-parsed.
      if (o.flipSats != null && text == o.flipText) return o.flipSats;
      // BTC / LBTC: typed in coin (8 decimals) or in the selected fiat and
      // converted at the spot price — the wallet only ever sees sats.
      return o.fiatInput
          ? AmountUnits.satsFromFiat(text, PriceService.instance.btcPrice)
          : AmountUnits.satsFromCoin(text);
    }
    // Other tokens: input directly in base units.
    final v = AmountUnits.parseDecimal(text);
    return v?.round();
  }

  /// Whether a row's ⇅ can flip between coin and fiat right now: a BTC-like
  /// row, a live price, and MAX not holding the field.
  bool _canToggleFiat(_OutputDraft o) =>
      _rowIsBtcLike(o) && PriceService.instance.hasPrice && !o.maxEngaged;

  /// Flip a row between coin and fiat, re-expressing whatever is typed so
  /// the amount itself does not change — the number in the box does.
  void _toggleFiat(int i) {
    final o = _outputs[i];
    if (!_canToggleFiat(o)) return;
    final price = PriceService.instance.btcPrice;
    final toFiat = !o.fiatInput;
    // Resolve the amount in the unit the field is in *now*, exact where a
    // previous flip left it untouched.
    final sats = _amountSatsOf(o);
    setState(() {
      o.fiatInput = toFiat;
      final String? converted;
      if (o.amountCtrl.text.trim().isEmpty) {
        converted = '';
      } else if (sats == null) {
        // Unparsable: the user is mid-edit and can see it — leave it alone.
        converted = null;
      } else {
        converted = toFiat
            ? AmountUnits.fiatText(sats, price)
            : AmountUnits.coinText(sats);
      }
      if (converted != null) {
        o.amountCtrl.value = TextEditingValue(
          text: converted,
          selection: TextSelection.collapsed(offset: converted.length),
        );
      }
      o.flipSats = converted == null || converted.isEmpty ? null : sats;
      o.flipText = converted == null || converted.isEmpty ? null : converted;
    });
  }

  /// "≈ €98.40" under a coin amount, "≈ 0.00123456 BTC" under a fiat one —
  /// the other reading of the same number, so a typo in either unit is
  /// caught before Review. Null when there is nothing to say.
  String? _equivalentText(_OutputDraft o) {
    if (!_rowIsBtcLike(o) || o.sendMax) return null;
    final price = PriceService.instance;
    if (!price.hasPrice) return null;
    final sats = _amountSatsOf(o);
    if (sats == null) return null;
    return o.fiatInput
        ? '≈ ${AmountUnits.coinText(sats)} ${_rowTicker(o)}'
        : '≈ ${price.symbol}${AmountUnits.fiatText(sats, price.btcPrice)}';
  }

  List<TxOutputSpec>? get _outputSpecs {
    final specs = <TxOutputSpec>[];
    for (final o in _outputs) {
      final addr = o.addressCtrl.text.trim();
      if (addr.isEmpty) return null;
      // Per-output asset only matters on Liquid; the backend falls back to
      // the transaction-level asset (LBTC) when omitted.
      final assetId = _isBtc ? null : _rowAsset(o)?.assetId;
      if (o.sendMax) {
        specs.add(
          TxOutputSpec(
            address: addr,
            amountSats: 0,
            assetId: assetId,
            sendMax: true,
          ),
        );
        continue;
      }
      final sats = _amountSatsOf(o);
      if (sats == null || sats <= 0) return null;
      specs.add(
        TxOutputSpec(address: addr, amountSats: sats, assetId: assetId),
      );
    }
    return specs.isEmpty ? null : specs;
  }

  /// BTC-like total of the fixed rows (MAX rows excluded — their amount is
  /// only known after the preview builds).
  int get _outputsTotal => _outputs
      .where((o) => !o.sendMax && _rowIsBtcLike(o))
      .fold(0, (s, o) => s + (_amountSatsOf(o) ?? 0));

  /// One "ticker → total" line per asset across the output rows.
  Map<String, int> get _totalsByTicker {
    final totals = <String, int>{};
    for (final o in _outputs.where((o) => !o.sendMax)) {
      final sats = _amountSatsOf(o);
      if (sats == null) continue;
      final t = _rowTicker(o);
      totals[t] = (totals[t] ?? 0) + sats;
    }
    return totals;
  }

  bool get _hasMaxOutput => _outputs.any((o) => o.sendMax);

  List<Utxo> get _selectedUtxos => _utxos.where((u) => u.isSelected).toList();
  int get _selectedInputTotal => _selectedUtxos.fold(0, (s, u) => s + u.amount);

  /// Outpoints to pass to the bridge — null means automatic selection.
  List<String>? get _spendOutpoints => _isBtc && _manualInputs
      ? _selectedUtxos.map((u) => u.outpoint).toList()
      : null;

  String _fmtAmount(int sats) {
    if (_isBtcLike) {
      return '${(sats / 1e8).toStringAsFixed(8)} ${_selectedAsset?.ticker ?? 'BTC'}';
    }
    return '$sats ${_selectedAsset != null ? AssetRegistryService.instance.displayTicker(_selectedAsset!) : ''}';
  }

  // ── navigation ──────────────────────────────────────────────────────────────

  /// Review opens exactly when the old wizard would have let the user reach
  /// it — every one of its per-step checks, in one place: a chain is chosen
  /// (Network), a manual coin selection is not empty (Inputs), every
  /// recipient has an address and a positive amount or Max (Outputs), and
  /// the fee rate is positive (Fee).
  bool get _canReview =>
      !_loadingAssets &&
      _selectedAsset != null &&
      (!_manualInputs || (_isBtc && _selectedUtxos.isNotEmpty)) &&
      _outputSpecs != null &&
      _feeRate > 0;

  /// The Review primary: a built preview, and nothing already in flight.
  bool get _canSign => _preview != null && !_previewing && !_sending;

  void _review() {
    if (!_canReview) return;
    setState(() {
      _stage = _Stage.review;
      _error = null;
    });
    _buildPreview();
  }

  void _backToCompose() {
    setState(() {
      _stage = _Stage.compose;
      _error = null;
    });
  }

  void _startCosign() => setState(() {
    _kind = _TxKind.cosign;
    _cosignFromCompose = true;
  });

  void _leaveCosign() => setState(() {
    _kind = _TxKind.standard;
    _cosignFromCompose = false;
  });

  /// The system back (and the phone header's arrow): Review steps back to
  /// Compose, exactly as the on-screen Back; a cosign opened from Compose
  /// returns to it. Consumed but ignored mid-send, when the on-screen Back is
  /// disabled too. On Compose the shell takes over and leaves the screen.
  bool _handleSystemBack() {
    // A departing Send stays mounted for the page transition; its handler
    // must not swallow a press meant for the page that replaced it.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    if (_kind == _TxKind.cosign) {
      if (!_cosignFromCompose) return false;
      _leaveCosign();
      return true;
    }
    if (_stage == _Stage.compose) return false;
    if (!_sending) _backToCompose();
    return true;
  }

  void _resetWizard() {
    setState(() {
      _stage = _Stage.compose;
      _manualInputs = false;
      for (final o in _outputs) {
        o.dispose();
      }
      _outputs
        ..clear()
        ..add(_OutputDraft());
      _preview = null;
      _error = null;
      _failedBroadcast = null;
      _utxos = [];
    });
  }

  // ── preview + send ──────────────────────────────────────────────────────────

  Future<void> _buildPreview() async {
    final specs = _outputSpecs;
    final asset = _selectedAsset;
    if (specs == null || asset == null) return;

    setState(() {
      _previewing = true;
      _preview = null;
      _error = null;
      // A new build supersedes any signed transaction kept from a failed
      // broadcast — the user chose to start over.
      _failedBroadcast = null;
    });
    try {
      final preview = await _bridge.previewTransaction(
        walletId: _walletId,
        outputs: specs,
        assetId: asset.assetId,
        feeRate: _isBtc ? _feeRate : 0.1,
        utxos: _spendOutpoints,
      );
      if (mounted) {
        setState(() {
          _preview = preview;
          _previewing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewing = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Text on the confirm dialog's primary button, and the line under it.
  (String, String) get _signCopy => _isHardwareWallet
      ? (
          'Sign on device',
          'Your hardware wallet will display the transaction and ask you to approve it',
        )
      : _isAirgapWallet
      ? (
          'Export PSBT',
          'A PSBT is generated for your air-gap device; you scan the signed one back',
        )
      : _isMultisigWallet
      ? (
          'Sign and continue',
          'Signed with this wallet\'s key(s). If the policy needs more '
              'signatures, you\'ll export the PSBT to your co-signers '
              'instead of broadcasting.',
        )
      // Only Liquid reaches this branch now: a Bitcoin software send
      // skips this dialog entirely for the two-phase review, and a
      // PSET has no QR form to review it with.
      : (
          'Sign and send',
          'Signed with this wallet\'s key — you re-enter your app '
              'password first — and broadcast immediately',
        );

  /// The Review primary opens a last summary of exactly what will happen.
  /// Nothing is signed until the user confirms there.
  Future<void> _confirm() async {
    final specs = _outputSpecs;
    final asset = _selectedAsset;
    final preview = _preview;
    if (specs == null || asset == null || preview == null) return;

    // The two-phase path opens with its own summary of the built PSBT — the
    // same numbers, plus the QR and the signature state. Showing the confirm
    // dialog first would summarise the transaction twice in a row.
    final twoPhase =
        _isBtc && !_isHardwareWallet && !_isAirgapWallet && !_isMultisigWallet;
    if (!twoPhase) {
      final (signLabel, signHint) = _signCopy;
      final confirmed = await showTxConfirmDialog(
        context,
        preview: preview,
        ticker: _isBtc ? 'BTC' : 'LBTC',
        signLabel: signLabel,
        signHint: signHint,
      );
      if (!confirmed || !mounted) return;
    }

    // Asset decides the route before wallet type does. A Jade's Liquid wallet
    // carries the same `Hardware (fp)` label as a Ledger's Bitcoin wallet, so
    // branching on type alone would hand an Elements transaction to the
    // Bitcoin/HWI path. Liquid always goes through `sendTransaction`, where
    // the backend picks the signer — software, or the Jade over serial — and
    // refuses any device that cannot sign Liquid at all.
    if (!_isBtc) {
      // A Liquid send from a hardware wallet still needs the device: the
      // backend connects to the Jade and asks it to sign the PSET. Gate on the
      // device being there first, so the prompt is "connect and unlock your
      // Jade" rather than a serial timeout several seconds later. Air-gap
      // wallets never reach here — Liquid is not offered for them at all.
      if (_isHardwareWallet && !_isAirgapWallet) {
        if (!await _ensureDeviceConnected()) return;
        if (!mounted) return;
      }
      await _doSend(specs, asset);
    } else if (_isHardwareWallet) {
      await _doSendHw(specs, asset);
    } else if (_isAirgapWallet) {
      await _doSendAirgap(specs);
    } else if (_isMultisigWallet) {
      // Multisig keeps the one-shot path: a partial signature has to reach the
      // co-signer hand-off dialog, which `sendTransaction` already returns.
      await _doSend(specs, asset);
    } else {
      await _doSendTwoPhase(specs);
    }
  }

  /// Label of Review's primary. A device or an air-gap signer is named, as
  /// before; a multisig key only adds its signature (the co-signers finish),
  /// so it says "Sign"; everything else signs behind the password gate and
  /// broadcasts. A confirmation (or the PSBT review) still opens first.
  String get _sendButtonLabel => _isHardwareWallet
      ? 'Sign on device'
      : _isAirgapWallet
      ? 'Export PSBT'
      : _isMultisigWallet
      ? 'Sign'
      : 'Sign and send';

  /// Software-key Bitcoin send, in two passes — the same flow the UTXO screen
  /// uses to consolidate.
  ///
  /// `send_transaction` builds, signs and broadcasts inside one FFI call: the
  /// user never sees what was signed, and a broadcast failure throws the
  /// signature away. Here the PSBT is built first, reviewed (with its QR),
  /// signed behind the app password, reviewed again as a signed transaction,
  /// and only then broadcast.
  Future<void> _doSendTwoPhase(List<TxOutputSpec> specs) async {
    final walletId = _walletId;
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final unsigned = await _bridge.buildUnsignedPsbt(
        walletId: walletId,
        outputs: specs,
        feeRate: _feeRate,
        utxos: _spendOutpoints,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      final txid = await showPsbtSignFlow(
        context,
        walletId: walletId,
        unsignedPsbt: unsigned,
        title: 'Review transaction',
        summary: specs.length == 1
            ? 'One recipient'
            : '${specs.length} recipients in one transaction',
      );
      // Backed out at the review or the password: nothing was signed, nothing
      // was sent, and the screen stays on Review.
      if (txid == null || !mounted) return;
      _showSuccess(txid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Software-key send. Known limitation: the FFI signs and broadcasts inside
  /// one call (`send_transaction`), so when only the broadcast leg fails the
  /// signed transaction never reaches Dart and cannot be retained for retry —
  /// unlike the air-gap/multisig flows, which broadcast a PSBT they hold.
  /// Re-running the send just re-signs the same coins, so nothing is lost.
  Future<void> _doSend(List<TxOutputSpec> specs, AssetBalance asset) async {
    final walletId = _walletId;
    // Same gate as the two-phase path: a key held on this computer is only
    // ever used behind the app password. A hardware wallet approves on the
    // device instead, so asking there would protect nothing.
    if (!_isHardwareWallet) {
      final ok = await showSpendPasswordGate(
        context,
        message:
            'Templar is about to sign this transaction with the key '
            'stored on this ${AppLayout.isMobilePlatform ? 'device' : 'computer'}.',
      );
      if (!ok || !mounted) return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final result = await _bridge.sendTransaction(
        walletId: walletId,
        outputs: specs,
        assetId: asset.assetId,
        feeRate: _isBtc ? _feeRate : 0.1,
        utxos: _spendOutpoints,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      // A multisig send needing external co-signatures returns a JSON object
      // instead of a txid (see FfiWalletBridge.sendTransaction).
      if (result.startsWith('{')) {
        final j = jsonDecode(result) as Map<String, dynamic>;
        final partial = j['partial_psbt'] as String?;
        if (partial != null) {
          _showPartialSignDialog(
            walletId,
            partial,
            j['sigs_have'] as int? ?? 0,
            j['sigs_needed'] as int?,
          );
          return;
        }
        // The Liquid form of the same outcome. Kept apart from the PSBT path
        // because the transports differ: a PSET has no BC-UR QR encoding, so
        // it travels as text or a file only.
        final partialPset = j['partial_pset'] as String?;
        if (partialPset != null) {
          _showLiquidCosignDialog(
            walletId,
            partialPset,
            j['sigs_have'] as int? ?? 0,
            j['sigs_needed'] as int? ?? 0,
          );
          return;
        }
      }
      _showSuccess(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  /// Make sure the wallet's own device is plugged in and unlocked before
  /// signing, on either chain. Shows the connect gate (no watch-only escape
  /// hatch here — we need to sign) and checks the device reports the
  /// fingerprint this wallet was created from, so a second device on the desk
  /// cannot be asked to sign for a wallet it has no key for.
  ///
  /// This is what makes "browse with the device unplugged, connect it to send"
  /// work: the wallet opens watch-only, and the device is only ever required
  /// here.
  Future<bool> _ensureDeviceConnected() async {
    final appState = context.read<AppState>();
    final result = await showLedgerConnectDialog(
      context,
      expectedFingerprint: fingerprintFromTypeLabel(appState.activeWalletType),
      allowWatchOnly: false,
      title: 'Connect your device to sign',
    );
    if (!mounted) return false;
    if (result == LedgerConnectResult.connected) {
      appState.setHwWatchOnly(false);
      return true;
    }
    return false;
  }

  /// Hardware-wallet send. Same limitation as [_doSend]: build, device
  /// signing, and broadcast happen inside one FFI call
  /// (`send_transaction_hw`), so a broadcast-only failure surfaces as an
  /// error string and the device-signed PSBT is not retained on the Dart
  /// side. The user re-approves on the device to try again.
  /// Identifies the exact transaction a retained signature belongs to.
  String _txKey(List<TxOutputSpec> specs, AssetBalance asset) => jsonEncode({
    'wallet': _walletId,
    'asset': asset.assetId,
    'fee': _feeRate,
    'utxos': _spendOutpoints,
    'outputs': specs.map((o) => o.toJson()).toList(),
  });

  Future<void> _doSendHw(List<TxOutputSpec> specs, AssetBalance asset) async {
    if (!_assertBitcoinOnly(asset)) return;
    // No platform gate here any more: Ledger and Jade are driven in-process
    // on every OS. A device that genuinely has no path on this platform is
    // refused by the backend with the reason and the way round it, which
    // arrives through the normal error banner.
    final key = _txKey(specs, asset);
    // Signing and broadcasting are two backend calls, not one. A PSBT the
    // device already signed is reused *only* for the identical transaction,
    // so a broadcast that failed on its own (no connectivity, a node hiccup)
    // is retried without a second on-device approval — while any edit to the
    // draft invalidates it and forces a fresh signature.
    final retry = _pendingSignedPsbt != null && _pendingSignedKey == key;
    if (!retry) {
      _pendingSignedPsbt = null;
      _pendingSignedKey = null;
      // Confirm the device is actually present before building/signing — gives
      // a clear "plug in your device" prompt instead of a deep driver error.
      if (!await _ensureDeviceConnected()) return;
      if (!mounted) return;
    }

    setState(() {
      _error = null;
      _sending = true;
    });

    final walletId = _walletId;
    final txid = await showLedgerSigningDialog(
      context,
      // Pre-sign guard: the device displays a wallet address, the dialog
      // shows the same one beside it, and the user confirms on the device
      // that they match — proving the connected device controls this wallet
      // before we build and sign. Skipped on a broadcast-only retry: nothing
      // is being signed, and the device may be unplugged again.
      verifyTask: retry ? null : () => _bridge.verifyHwAddress(walletId),
      // The address `verify_hw_address` puts on the device: the wallet's
      // current receive address (the engine reads the same one).
      verifyAddress: retry
          ? null
          : () async =>
                (await _bridge.generateReceiveAddress(walletId, 'BTC')).address,
      task: () async {
        if (_pendingSignedPsbt == null) {
          _pendingSignedPsbt = await _bridge.signTransactionHw(
            walletId: walletId,
            outputs: specs,
            assetId: asset.assetId,
            feeRate: _feeRate,
            utxos: _spendOutpoints,
          );
          _pendingSignedKey = key;
        }
        final id = await _bridge.broadcastSignedPsbt(
          walletId: walletId,
          psbtBase64: _pendingSignedPsbt!,
        );
        // Only drop the retained PSBT once it is irreversibly on the network.
        _pendingSignedPsbt = null;
        _pendingSignedKey = null;
        return id;
      },
      formatError: _friendlyHwError,
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (txid != null) {
      _showSuccess(txid);
    } else if (_pendingSignedPsbt != null) {
      // The device signed but the transaction never reached the network. Say
      // so plainly and keep the PSBT: the primary now retries the broadcast
      // alone.
      setState(
        () => _error =
            'The device signed, but broadcasting failed. Your transaction is '
            'not on the network. Press $_sendButtonLabel again to retry the '
            'broadcast — you will not have to approve on the device again.',
      );
    }
  }

  /// Translate raw FFI/Electrum errors into actionable guidance.
  String _friendlyHwError(String raw) {
    final lower = raw.toLowerCase();
    // Network-level rejection: not a hardware problem, so it is not part of
    // the shared hardware classifier.
    if (lower.contains('witness program') ||
        lower.contains('hash mismatch') ||
        lower.contains('stack size') ||
        lower.contains('script-verify')) {
      return 'The signed transaction was rejected by the network. Make sure '
          'the wallet was imported as native segwit and re-import if needed.';
    }
    return friendlyHwError(raw);
  }

  /// Air-gap signing is Bitcoin-only: it builds a BDK PSBT and moves it by QR,
  /// and there is no Liquid equivalent of that transport. The asset step
  /// already hides Liquid for air-gap wallets and the backend rejects it too;
  /// this is the middle guard, so no route can reach the QR flow with an
  /// asset it cannot carry.
  bool _assertBitcoinOnly(AssetBalance asset) {
    if (asset.ticker == 'BTC') return true;
    setState(() {
      _sending = false;
      _error =
          'Air-gap wallets can only send Bitcoin: signing happens over QR '
          'codes, and there is no Liquid equivalent of that flow. To spend '
          'Liquid from a hardware wallet, connect a Blockstream Jade over USB.';
    });
    return false;
  }

  Future<void> _doSendAirgap(List<TxOutputSpec> specs) async {
    final asset = _selectedAsset;
    if (asset != null && !_assertBitcoinOnly(asset)) return;
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final walletId = _walletId;
      final unsignedPsbt = await _bridge.buildUnsignedPsbt(
        walletId: walletId,
        outputs: specs,
        feeRate: _feeRate,
        assetId: asset?.assetId ?? 'BTC',
        utxos: _spendOutpoints,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      _showAirgapSignDialog(walletId, unsignedPsbt);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  void _showAirgapSignDialog(String walletId, String unsignedPsbt) {
    showAppDialog<void>(
      context,
      builder: (ctx) => PsbtHandoffSheet(
        unsignedPsbt: unsignedPsbt,
        onBroadcast: (signedPsbt) =>
            _broadcastFromDialog(ctx, walletId, signedPsbt),
      ),
    );
  }

  /// Multisig outcome: this wallet's key(s) signed, but the policy needs more
  /// signatures. Same export/import surface as the air-gap dialog, with the
  /// quorum charted at the top — nothing was broadcast.
  void _showPartialSignDialog(
    String walletId,
    String partialPsbt,
    int have,
    int? needed,
  ) {
    final quorum = needed != null ? '$have of $needed' : '$have';
    showAppDialog<void>(
      context,
      builder: (ctx) => PsbtHandoffSheet(
        unsignedPsbt: partialPsbt,
        title: 'Co-signatures needed',
        progressNote:
            'Partially signed — $quorum signatures collected. This '
            'wallet\'s key alone cannot satisfy the spending policy, so '
            'nothing was broadcast.',
        exportEyebrow: 'Hand it to your co-signers',
        intro:
            'Send them this PSBT — by QR, clipboard or file. Each one '
            'loads it under Send › Cosign a transaction, signs, and returns '
            'it.',
        returnEyebrow: 'Collect the signatures',
        returnLabel:
            'Paste each signed copy with the button above, or scan '
            'or load it here. Its signatures join the copy you hand out, and '
            'the chart follows.',
        quorumHave: have,
        quorumNeeded: needed,
        onBroadcast: (signedPsbt) =>
            _broadcastFromDialog(ctx, walletId, signedPsbt),
      ),
    );
  }

  /// Liquid multisig outcome: this wallet signed what it could, and the PSET
  /// now needs the other co-signers.
  void _showLiquidCosignDialog(
    String walletId,
    String pset,
    int have,
    int needed,
  ) {
    showAppDialog<void>(
      context,
      builder: (ctx) => PsetHandoffSheet(
        pset: pset,
        have: have,
        needed: needed,
        onBroadcast: (signed) =>
            _broadcastPsetFromDialog(ctx, walletId, signed),
      ),
    );
  }

  Future<void> _broadcastPsetFromDialog(
    BuildContext ctx,
    String walletId,
    String signedPset,
  ) async {
    Navigator.of(ctx).pop();
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final txid = await _bridge.broadcastPset(walletId, signedPset);
      if (!mounted) return;
      setState(() => _sending = false);
      _showSuccess(txid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _broadcastFromDialog(
    BuildContext ctx,
    String walletId,
    String signedPsbt,
  ) async {
    Navigator.of(ctx).pop();
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final txid = await _bridge.broadcastSignedPsbt(
        walletId: walletId,
        psbtBase64: signedPsbt,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failedBroadcast = null;
      });
      _showSuccess(txid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
          // The signatures are still valid — keep the signed PSBT so the
          // user can retry or export it instead of re-signing from scratch.
          _failedBroadcast = (walletId, signedPsbt);
        });
      }
    }
  }

  /// Retry broadcasting the signed transaction kept from a failed attempt.
  Future<void> _retryBroadcast() async {
    final failed = _failedBroadcast;
    if (failed == null) return;
    final (walletId, signedPsbt) = failed;
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final txid = await _bridge.broadcastSignedPsbt(
        walletId: walletId,
        psbtBase64: signedPsbt,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failedBroadcast = null;
      });
      _showSuccess(txid);
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _copyFailedBroadcastPsbt() async {
    final failed = _failedBroadcast;
    if (failed == null) return;
    await Clipboard.setData(ClipboardData(text: failed.$2));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed transaction copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showSuccess(String txid) {
    // The wallet is stale the instant a broadcast succeeds — balances read
    // wrong and the spent UTXOs could be re-selected on the next send. Kick
    // off a background sync on the shell's footer/bumpSync path; a failure is
    // tolerated (the footer shows the sync state).
    final appState = context.read<AppState>();
    final syncWalletId = appState.activeWalletId;
    if (syncWalletId != null) {
      appState.setSyncState(SyncState.syncing);
      unawaited(
        _bridge
            .syncWallet(syncWalletId)
            .then(appState.applySyncOutcomes)
            .catchError((Object e) {
              debugPrint('[send] post-broadcast sync failed: $e');
              appState.setSyncState(SyncState.error);
              appState.bumpSync();
            }),
      );
    }

    // Capture before the reset wipes it — the recap needs the preview data.
    final preview = _preview;
    if (preview != null) {
      showTxSuccessDialog(
        context,
        txid: txid,
        preview: preview,
        ticker: _isBtc ? 'BTC' : 'LBTC',
        // Activity opens this transaction's detail as soon as a sync lists
        // it (the one started just above).
        onViewInActivity: () {
          if (mounted) context.go('${AppRoutes.history}?tx=$txid');
        },
      );
    } else {
      // No preview available (should not happen) — minimal fallback.
      final phone = AppLayout.isPhone(context);
      showAppDialog<void>(
        context,
        builder: (ctx) => AppDialog(
          title: const Text('Sent'),
          content: SizedBox(
            width: phone ? double.infinity : 480,
            child: CodeBox(value: txid, label: 'TxID'),
          ),
          actions: [
            PrimaryButton(
              label: 'Done',
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    }
    _resetWizard();
  }

  // ── build ───────────────────────────────────────────────────────────────────

  /// One width for both stages, so the column never jumps between Compose
  /// and Review. Wider than a plain form because the manual coin picker and
  /// the review diagram both need room for two columns.
  static const double _columnMaxWidth = 720;

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final cosign = _kind == _TxKind.cosign;
    final pad = AppSpacing.pagePadding(context);
    final footer = cosign ? null : _footer(phone);
    // Phone: the primary is pinned under the scrolling column so it stays
    // reachable with the keyboard up; desktop keeps it at the column's foot.
    final pinFooter = phone && footer != null;
    final watchOnly =
        context.watch<AppState>().isActiveWalletHardware &&
        context.watch<AppState>().hwWatchOnly;

    final List<Widget> children;
    if (cosign) {
      // The same centred column as Compose and Review, so the page does not
      // shift sideways when the mode changes.
      children = [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _columnMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _cosignChildren(phone, watchOnly),
            ),
          ),
        ),
      ];
    } else {
      final stage = Column(
        key: ValueKey(_stage),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_stage == _Stage.compose)
            ..._composeChildren(phone, watchOnly)
          else
            ..._reviewChildren(phone),
          if (footer != null && !pinFooter) ...[
            const SizedBox(height: AppSpacing.xl),
            footer,
          ],
        ],
      );
      children = [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _columnMaxWidth),
            child: AnimatedSwitcher(
              duration: AppMotion.of(context, AppMotion.standard),
              switchInCurve: AppMotion.settle,
              child: stage,
            ),
          ),
        ),
      ];
    }

    final page = ListView(padding: EdgeInsets.all(pad), children: children);

    return Scaffold(
      body: PageBackground.flat(
        child: !pinFooter
            ? page
            : Column(
                children: [
                  Expanded(child: page),
                  // The pinned row has a ground and a rule of its own, or the
                  // column scrolls up until it touches the button.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppScheme.of(context).canvas,
                      border: Border(
                        top: BorderSide(color: AppScheme.of(context).edge),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pad,
                        AppSpacing.md,
                        pad,
                        AppSpacing.md,
                      ),
                      child: footer,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// "Watch-only mode": the device is not connected, so nothing can be
  /// signed until it is.
  Widget _watchOnlyBanner() => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
    child: WarningBanner(
      title: 'Watch-only mode',
      message:
          'This wallet was opened without its device. Browsing works '
          'offline; connect and unlock the device to sign and send.',
      action: SecondaryButton(
        label: 'Connect',
        icon: Icons.usb_outlined,
        onPressed: () => _ensureDeviceConnected(),
      ),
    ),
  );

  // ── Cosign ──────────────────────────────────────────────────────────────────

  /// What the co-sign mode is called. One name on every wallet and both
  /// chains: it takes a Bitcoin PSBT or a Liquid PSET alike, and asks which
  /// inside.
  String get _cosignTitle => 'Cosign a transaction';

  List<Widget> _cosignChildren(bool phone, bool watchOnly) => [
    // Desktop only: on a phone the shell header's arrow leaves the mode.
    if (!phone) ...[
      Align(
        alignment: Alignment.centerLeft,
        child: GhostButton(
          label: 'Back to send',
          icon: Icons.arrow_back_outlined,
          onPressed: _leaveCosign,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
    ],
    PageHeader(
      title: _cosignTitle,
      subtitle: phone ? null : 'Review and sign a partially signed transaction',
    ),
    if (watchOnly) _watchOnlyBanner(),
    // Keyed so leaving and re-entering the mode rebuilds the view rather
    // than carrying a loaded PSBT — and its Sign buttons — across the change.
    CosignView(key: ValueKey(_kind), bridge: _bridge),
  ];

  // ── Compose ─────────────────────────────────────────────────────────────────

  List<Widget> _composeChildren(bool phone, bool watchOnly) {
    final s = AppScheme.of(context);
    final btc = _assets.where((a) => a.ticker == 'BTC').firstOrNull;
    final lbtc = _assets.where((a) => a.ticker == 'LBTC').firstOrNull;
    // The chain switch replaces the old Network step. A wallet with one
    // chain has nothing to choose, so it gets no switch at all.
    final Widget? chainSwitch = btc != null && lbtc != null
        ? ChainSwitch<String>(
            selected: _isBtc ? 'BTC' : 'LBTC',
            bitcoin: 'BTC',
            liquid: 'LBTC',
            expand: phone,
            onChanged: (v) => _selectNetwork(v == 'BTC' ? btc : lbtc),
          )
        : null;
    final cosignLink = GhostButton(
      label: _cosignTitle,
      icon: Icons.draw_outlined,
      onPressed: _startCosign,
    );
    // A multisig wallet cannot finish a transaction alone: what it builds
    // here is the first half of a round trip with its co-signers.
    final multisigNote = _isMultisigWallet
        ? 'Builds a partial transaction for your co-signers'
        : null;

    return [
      if (phone) ...[
        // The shell's header already names the page; the phone column opens
        // on its controls instead of a second "Send".
        if (chainSwitch != null) ...[
          chainSwitch,
          const SizedBox(height: AppSpacing.sm),
        ],
        Align(alignment: Alignment.centerLeft, child: cosignLink),
        if (multisigNote != null)
          Text(
            multisigNote,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        const SizedBox(height: AppSpacing.lg),
      ] else
        PageHeader(
          title: 'Send',
          subtitle: multisigNote,
          actions: [cosignLink, ?chainSwitch],
        ),
      if (watchOnly) _watchOnlyBanner(),
      if (_loadingAssets)
        const Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_selectedAsset == null)
        FormCard(
          child: Text(
            'This wallet holds nothing that can be sent from here',
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
        )
      else ...[
        for (var i = 0; i < _outputs.length; i++) ...[
          _recipientCard(i, phone),
          const SizedBox(height: AppSpacing.sm),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            label: 'Add recipient',
            icon: Icons.add_outlined,
            onPressed: () => setState(() => _outputs.add(_OutputDraft())),
          ),
        ),
        if (_outputs.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          ..._totalLines(phone),
        ],
        const SizedBox(height: AppSpacing.xl),
        _feeCard(phone),
        const SizedBox(height: AppSpacing.lg),
        _coinsCard(phone),
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.lg),
        DangerBanner(message: _error!),
      ],
    ];
  }

  /// Switch the chain the transaction is built on — what the old Network
  /// step did.
  void _selectNetwork(AssetBalance a) {
    setState(() {
      if (_selectedAsset?.assetId != a.assetId) {
        // Chain changed: coin selection, output assets, and previews no
        // longer apply — start the recipient list fresh.
        _manualInputs = false;
        for (final i in List.generate(_utxos.length, (i) => i)) {
          _utxos[i] = _utxos[i].copyWith(isSelected: false);
        }
        _preview = null;
        for (final o in _outputs) {
          o.dispose();
        }
        _outputs
          ..clear()
          ..add(_OutputDraft());
      }
      _selectedAsset = a;
    });
  }

  /// Why an amount that has been typed cannot be sent, or null.
  String? _amountProblem(_OutputDraft o) {
    if (o.sendMax || o.amountCtrl.text.trim().isEmpty) return null;
    final sats = _amountSatsOf(o);
    if (sats == null) return 'Not a valid amount';
    if (sats <= 0) return 'Enter an amount above zero';
    return null;
  }

  /// The row asset's balance, for BTC / LBTC rows. A token's field takes base
  /// units while its balance is shown in display units, so a token row says
  /// nothing here rather than put two scales side by side.
  String? _availableText(_OutputDraft o) {
    final a = _rowAsset(o);
    if (a == null || !_rowIsBtcLike(o)) return null;
    // The backend formats LBTC amounts with a plain "BTC" suffix.
    final amount = a.ticker == 'LBTC'
        ? a.displayAmount.replaceFirst(RegExp(r'\bBTC\b'), 'LBTC')
        : a.displayAmount;
    return 'Available $amount';
  }

  Widget _recipientCard(int i, bool phone) {
    final s = AppScheme.of(context);
    final o = _outputs[i];
    final multi = _outputs.length > 1;
    final problem = _amountProblem(o);
    final approx = problem == null ? _equivalentText(o) : null;

    return FormCard(
      title: multi ? 'Recipient ${i + 1}' : 'Recipient',
      trailing: multi
          ? _IconAction(
              icon: Icons.close_outlined,
              tooltip: 'Remove recipient',
              onTap: () => setState(() {
                _outputs[i].dispose();
                _outputs.removeAt(i);
              }),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Per-output asset — Liquid only: one transaction can pay LBTC and
          // tokens to different recipients at once.
          if (!_isBtc && _liquidSpendable.length > 1) ...[
            const _FieldLabel('Asset'),
            _assetSelector(i),
            const SizedBox(height: AppSpacing.lg),
          ],
          const _FieldLabel('Address'),
          TextField(
            controller: o.addressCtrl,
            style: AppTypography.mono,
            // An address is not prose: no autocorrect, no suggestions, no
            // capitalisation — a "corrected" bech32 string is a different
            // address. No-ops on desktop.
            keyboardType: TextInputType.visiblePassword,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            // Phone: let the whole address show, wrapped, so it can be
            // checked in place; Enter never inserts a newline.
            maxLines: phone ? null : 1,
            textInputAction: phone ? TextInputAction.done : null,
            inputFormatters: phone
                ? [FilteringTextInputFormatter.deny(RegExp(r'[\r\n]'))]
                : null,
            decoration: InputDecoration(
              hintText: 'Paste, scan or type',
              suffixIcon: phone ? null : _addressActions(i),
            ),
            // A payment link pasted straight into the field (⌘V never goes
            // through the paste button) resolves to address + amount on the
            // spot. Setting the controller does not re-enter onChanged, so
            // this runs once: after it the field holds a bare address.
            onChanged: (v) => PaymentUri.isPaymentUri(v)
                ? _applyAddressInput(i, v)
                : setState(() {}),
          ),
          if (phone) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: _addressActionStrip(i),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          _FieldLabel('Amount', trailing: _availableText(o)),
          TextField(
            controller: o.amountCtrl,
            // Max owns the field while engaged — tap it again to edit.
            enabled: !o.maxEngaged,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: AppTypography.numeric,
            decoration: InputDecoration(
              hintText: o.sendMax
                  ? 'Everything after the fee'
                  : o.fiatInput
                  ? '0.00'
                  : (_rowIsBtcLike(o) ? '0.00000000' : '0'),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MaxToggle(
                      engaged: o.maxEngaged,
                      onTap: () => _toggleMax(i),
                    ),
                    // The unit — and, on a BTC/LBTC row with a price, the
                    // flip to fiat and back.
                    UnitChip(
                      label: o.fiatInput
                          ? PriceService.instance.currency
                          : _rowTicker(o),
                      other: _canToggleFiat(o)
                          ? (o.fiatInput
                                ? _rowTicker(o)
                                : PriceService.instance.currency)
                          : null,
                      onTap: _canToggleFiat(o) ? () => _toggleFiat(i) : null,
                    ),
                  ],
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (problem != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              problem,
              style: AppTypography.caption.copyWith(color: s.danger),
            ),
          ] else if (approx != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              approx,
              style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            ),
          ],
        ],
      ),
    );
  }

  /// The Liquid asset a row pays: logo, name and balance per option.
  Widget _assetSelector(int i) {
    final s = AppScheme.of(context);
    String nameOf(AssetBalance a) => a.ticker == 'LBTC'
        ? 'LBTC'
        : AssetRegistryService.instance.displayTicker(a);
    return DropdownButtonFormField<String>(
      initialValue: _rowAsset(_outputs[i])?.assetId,
      decoration: const InputDecoration(hintText: 'Choose asset'),
      // The value fills the field and a long ticker + amount ellipsises
      // instead of overflowing.
      isExpanded: true,
      items: [
        for (final a in _liquidSpendable)
          DropdownMenuItem(
            value: a.assetId,
            child: Row(
              children: [
                AssetLogo(ticker: a.ticker, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    nameOf(a),
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(color: s.ink),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    a.displayAmount,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.numericSmall.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (id) => setState(() {
        _outputs[i].asset = _liquidSpendable
            .where((a) => a.assetId == id)
            .firstOrNull;
        // Units changed meaning — the old amount no longer applies.
        _clearMax(_outputs[i]);
        _outputs[i].fiatInput = false;
        _outputs[i].amountCtrl.clear();
      }),
    );
  }

  /// One "Total BTC" (or other ticker) line per asset across the recipients, and a note
  /// for a Max recipient, whose amount only the preview knows.
  List<Widget> _totalLines(bool phone) {
    final s = AppScheme.of(context);
    final labelStyle = AppTypography.caption.copyWith(color: s.inkSecondary);
    final valueStyle = AppTypography.numericSmall.copyWith(color: s.ink);
    return [
      for (final entry in _totalsByTicker.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total ${entry.key}', style: labelStyle),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: phone
                    // Coin on one line, the fiat reading under it: side by
                    // side they wrapped at "· ≈" on a phone column.
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _totalCoinText(entry.key, entry.value),
                            textAlign: TextAlign.end,
                            style: valueStyle,
                          ),
                          if (_totalFiatText(entry.key, entry.value)
                              case final fiat?)
                            Text(
                              fiat,
                              textAlign: TextAlign.end,
                              style: AppTypography.numericSmall.copyWith(
                                color: s.inkFaint,
                              ),
                            ),
                        ],
                      )
                    : Text(
                        switch (_totalFiatText(entry.key, entry.value)) {
                          final fiat? =>
                            '${_totalCoinText(entry.key, entry.value)} · $fiat',
                          null => _totalCoinText(entry.key, entry.value),
                        },
                        textAlign: TextAlign.end,
                        style: valueStyle,
                      ),
              ),
            ],
          ),
        ),
      if (_hasMaxOutput)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Text('Max recipient', style: labelStyle),
              const Spacer(),
              Text(
                'Set at review',
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
            ],
          ),
        ),
    ];
  }

  // ── Fee ─────────────────────────────────────────────────────────────────────

  static const _feeTimes = {
    'slow': '~60 min',
    'normal': '~30 min',
    'fast': '~10 min',
  };

  bool get _customRateValid {
    final v = double.tryParse(_customFeeCtrl.text.trim());
    return v != null && v > 0;
  }

  /// The same rough size the old Fee step forecast with: the exact vsize
  /// only exists once the preview has built the transaction.
  int get _estVsize =>
      110 +
      68 * math.max<int>(1, _manualInputs ? _selectedUtxos.length : 1) +
      31 * _outputs.length;

  /// What the chosen rate means: `~30 min · 3 sat/vB · ≈ 627 sats`.
  String get _feeLine {
    if (_feePreset == 'custom' && !_customRateValid) {
      return 'Enter a rate in sat/vB · ${_fmtRate(_feeRate)} sat/vB until then';
    }
    final time = _feeTimes[_feePreset];
    final est = (_feeRate * _estVsize).round();
    return [
      ?time,
      '${_fmtRate(_feeRate)} sat/vB',
      '≈ ${_groupDigits(est)} sats',
    ].join(' · ');
  }

  Widget _feeCard(bool phone) {
    final s = AppScheme.of(context);
    if (!_isBtc) {
      return FormCard(
        title: 'Fee',
        child: Text(
          'Liquid uses a flat fee of about 0.1 sat/vB, taken automatically',
          style: AppTypography.body.copyWith(color: s.inkSecondary),
        ),
      );
    }
    return FormCard(
      title: 'Fee',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedSwitch<String>(
            expand: phone,
            selected: _feePreset,
            onChanged: (f) => setState(() => _feePreset = f),
            options: const [
              SegOption(value: 'slow', label: 'Slow'),
              SegOption(value: 'normal', label: 'Normal'),
              SegOption(value: 'fast', label: 'Fast'),
              SegOption(value: 'custom', label: 'Custom'),
            ],
          ),
          if (_feePreset == 'custom') ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: phone ? double.infinity : 200,
              child: TextField(
                controller: _customFeeCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: AppTypography.numeric,
                decoration: const InputDecoration(
                  hintText: '3.0',
                  suffixText: 'sat/vB',
                  helperText: 'Minimum 0.1 sat/vB',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            _feeLine,
            style: AppTypography.numericSmall.copyWith(color: s.inkSecondary),
          ),
          Text(
            'Times are estimates; the exact fee is set at review',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        ],
      ),
    );
  }

  // ── Coins ───────────────────────────────────────────────────────────────────

  /// Manual coin control: open the picker, loading the coins the first time.
  void _chooseCoins() {
    setState(() => _manualInputs = true);
    if (_utxos.isEmpty) _loadUtxos();
  }

  Widget _coinsCard(bool phone) {
    final s = AppScheme.of(context);
    final manual = _isBtc && _manualInputs;
    final subtitle = !_isBtc
        ? 'Chosen automatically; coin control is Bitcoin only'
        : manual
        ? 'Chosen by you'
        : 'Chosen automatically';

    final header = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Coins',
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle,
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
            ],
          ),
        ),
        if (_isBtc) ...[
          const SizedBox(width: AppSpacing.md),
          manual
              ? GhostButton(
                  label: 'Back to automatic',
                  onPressed: () => setState(() => _manualInputs = false),
                )
              : SecondaryButton(label: 'Choose coins', onPressed: _chooseCoins),
        ],
      ],
    );

    if (!manual) return FormCard(child: header);

    final insufficient =
        !_hasMaxOutput &&
        _outputsTotal > 0 &&
        _outputsTotal > _selectedInputTotal;
    final labelStyle = AppTypography.caption.copyWith(color: s.inkSecondary);
    final valueStyle = AppTypography.numericSmall.copyWith(color: s.ink);

    return FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: AppSpacing.lg),
          if (_loadingUtxos)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_utxos.isEmpty)
            Text('No spendable coins found', style: labelStyle)
          else
            UtxoPicker(
              utxos: _utxos,
              // Phone: no inner scroll region — the page scrolls and the coin
              // list takes the height it needs.
              maxHeight: phone ? double.infinity : 420,
              onToggle: (i) {
                // Frozen coins are listed so the total adds up, but are never
                // spent (CLAUDE.md rule 3).
                if (_utxos[i].isFrozen) return;
                setState(
                  () => _utxos[i] = _utxos[i].copyWith(
                    isSelected: !_utxos[i].isSelected,
                  ),
                );
              },
            ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('${_selectedUtxos.length} selected', style: labelStyle),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Text(
                  _fmtAmount(_selectedInputTotal),
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ),
            ],
          ),
          if (!_hasMaxOutput && _outputsTotal > 0)
            Row(
              children: [
                Text('Needed', style: labelStyle),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Text(
                    '${_fmtAmount(_outputsTotal)} + fee',
                    textAlign: TextAlign.end,
                    style: valueStyle,
                  ),
                ),
              ],
            ),
          if (_selectedUtxos.isEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Select at least one coin',
              style: AppTypography.caption.copyWith(color: s.danger),
            ),
          ] else if (insufficient) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'The selected coins may not cover the amount and the fee',
              style: AppTypography.caption.copyWith(color: s.warning),
            ),
          ],
        ],
      ),
    );
  }

  // ── Footer ──────────────────────────────────────────────────────────────────

  /// What is still missing before Review can open, said beside the button.
  /// Fields with a wrong value say so under themselves; this names the empty
  /// ones, which are not errors until the user tries to go on.
  String? get _composeHint {
    if (_loadingAssets || _canReview) return null;
    if (_selectedAsset == null) return null;
    if (_manualInputs && _selectedUtxos.isEmpty) {
      return 'Select at least one coin';
    }
    for (var i = 0; i < _outputs.length; i++) {
      final o = _outputs[i];
      final who = _outputs.length == 1 ? '' : ' for recipient ${i + 1}';
      if (o.addressCtrl.text.trim().isEmpty) return 'Add an address$who';
      if (!o.sendMax) {
        final sats = _amountSatsOf(o);
        if (sats == null || sats <= 0) return 'Enter an amount$who';
      }
    }
    return null;
  }

  Widget _footer(bool phone) {
    final s = AppScheme.of(context);
    if (_stage == _Stage.compose) {
      final hint = _composeHint;
      final button = PrimaryButton(
        label: 'Review',
        icon: Icons.arrow_forward_outlined,
        isFullWidth: phone,
        onPressed: _canReview ? _review : null,
      );
      final hintText = hint == null
          ? null
          : Text(
              hint,
              textAlign: phone ? TextAlign.center : TextAlign.end,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            );
      if (phone) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hintText != null) ...[
              hintText,
              const SizedBox(height: AppSpacing.sm),
            ],
            button,
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: hintText ?? const SizedBox.shrink()),
          const SizedBox(width: AppSpacing.lg),
          button,
        ],
      );
    }

    // Review. A signed transaction whose broadcast failed is the one thing
    // left to do here: retry it, without signing again.
    final Widget primary = _failedBroadcast != null
        ? PrimaryButton(
            label: _sending ? 'Broadcasting…' : 'Retry broadcast',
            icon: Icons.refresh_outlined,
            isFullWidth: phone,
            onPressed: _sending ? null : _retryBroadcast,
          )
        // Nothing is signed from here: the summary or the device that opens
        // next is where that happens, behind the password gate.
        : PrimaryButton(
            label: _sending ? 'Preparing…' : _sendButtonLabel,
            isFullWidth: phone,
            onPressed: _canSign ? _confirm : null,
          );
    if (phone) return primary;
    return Row(children: [const Spacer(), primary]);
  }

  // ── Review ──────────────────────────────────────────────────────────────────

  List<Widget> _reviewChildren(bool phone) {
    final s = AppScheme.of(context);
    final head = <Widget>[
      // On a phone the shell header's arrow is this Back (it steps Review →
      // Compose through the BackHandler); a second one under it is noise.
      if (!phone) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: GhostButton(
            label: 'Back',
            icon: Icons.arrow_back_outlined,
            onPressed: _sending ? null : _backToCompose,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      Text(
        'Review',
        style: AppTypography.pageTitleOf(context).copyWith(color: s.ink),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Check every address before you sign',
        style: AppTypography.bodyOf(context).copyWith(color: s.inkSecondary),
      ),
      SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
    ];

    if (_previewing) {
      return [
        ...head,
        const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
        Center(
          child: Text(
            'Building transaction…',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ),
      ];
    }

    // A broadcast failure after signing is recoverable without re-signing:
    // the signed PSBT was retained, so the footer offers the retry and this
    // offers the copy.
    if (_failedBroadcast != null) {
      return [
        ...head,
        if (_error != null) ...[
          DangerBanner(message: _error!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Text(
          'The transaction is signed — only the broadcast failed. Your '
          'signatures were kept: retry when the network is reachable, or '
          'copy the signed transaction and broadcast it elsewhere.',
          style: AppTypography.body.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryButton(
            label: 'Copy signed transaction',
            icon: Icons.content_copy_outlined,
            isFullWidth: phone,
            onPressed: _copyFailedBroadcastPsbt,
          ),
        ),
      ];
    }

    final preview = _preview;
    if (preview == null) {
      // The preview itself failed: say why and offer to build it again.
      return [
        ...head,
        if (_error != null) ...[
          DangerBanner(message: _error!),
          const SizedBox(height: AppSpacing.lg),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: SecondaryButton(
            label: 'Retry',
            icon: Icons.refresh_outlined,
            onPressed: _buildPreview,
          ),
        ),
      ];
    }

    return [
      ...head,
      // A signing or broadcast error keeps the transaction on screen: the
      // primary below tries again.
      if (_error != null) ...[
        DangerBanner(message: _error!),
        const SizedBox(height: AppSpacing.lg),
      ],
      // While the transaction is being signed and sent, a green stroke runs
      // round the flow: this is the thing being worked on.
      LiveEdge(
        mode: _sending ? LiveEdgeMode.working : LiveEdgeMode.off,
        color: s.success,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        width: 2,
        child: _TxDiagram(
          preview: preview,
          isBtcLike: _isBtcLike,
          ticker: _selectedAsset?.ticker ?? 'BTC',
          liquid: !_isBtc,
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
      _ReviewSummary(preview: preview, isBtc: _isBtc),
    ];
  }

  // ── Address helpers ─────────────────────────────────────────────────────────

  /// Toggle Max on a row — engaging and disengaging both work, for tokens as
  /// well as BTC/LBTC. Disengaging restores the amount that Max replaced.
  void _toggleMax(int i) {
    final o = _outputs[i];
    setState(() {
      if (o.maxEngaged) {
        _clearMax(o);
        return;
      }
      if (_rowIsBtcLike(o)) {
        // Only one row can drain the wallet: a second would have nothing left
        // to take. Disengaging the others restores their amounts.
        for (final other in _outputs) {
          if (!identical(other, o) &&
              other.maxEngaged &&
              _rowIsBtcLike(other)) {
            _clearMax(other);
          }
        }
      }
      o.amountBeforeMax = o.amountCtrl.text;
      o.maxEngaged = true;
      if (_rowIsBtcLike(o)) {
        // Drain: the backend resolves the amount once it knows the fee.
        o.sendMax = true;
        o.amountCtrl.clear();
      } else {
        // The fee is paid in LBTC, so a token Max is just the whole balance —
        // a number we can show right now.
        o.sendMax = false;
        o.amountCtrl.text = '${_rowAsset(o)?.amount ?? 0}';
      }
    });
  }

  /// Disengage Max on a row and put back whatever it replaced. Call inside a
  /// [setState]; it only mutates.
  void _clearMax(_OutputDraft o) {
    o.maxEngaged = false;
    o.sendMax = false;
    o.amountCtrl.text = o.amountBeforeMax ?? '';
    o.amountBeforeMax = null;
  }

  /// Fills a row from text that arrived whole — pasted, scanned, or dropped
  /// into the field in one go.
  ///
  /// A `bitcoin:` / `liquidtestnet:` payment link carries the amount beside
  /// the address, so the row takes both and the field is left holding the
  /// address alone: the recipient asked for a figure, and copying it across
  /// by eye is the step that puts a digit in the wrong place. A Max still
  /// engaged is stood down — an amount was named, so "everything" is no
  /// longer what is being sent.
  void _applyAddressInput(int i, String text) {
    final o = _outputs[i];
    final req = PaymentUri.parse(text);
    setState(() {
      if (req == null) {
        o.addressCtrl.text = text.trim();
        return;
      }
      o.addressCtrl.text = req.address;
      if (req.amountSats case final sats?) {
        _clearMax(o);
        o.fiatInput = false;
        o.amountCtrl.text = AmountUnits.coinText(sats);
      }
    });
  }

  Future<void> _pasteAddress(int i) async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && mounted) {
      _applyAddressInput(i, data!.text!);
    }
  }

  /// Camera scan into a row's address field. Plain-text QRs (addresses and
  /// payment links) come back as `descriptor`.
  Future<void> _scanAddress(int i) async {
    final outcome = await showUrScannerDialog(
      context,
      expectPsbt: false,
      title: 'Scan recipient address',
    );
    final value = outcome?.descriptor ?? outcome?.psbtBase64;
    if (value == null || value.isEmpty || !mounted) return;
    _applyAddressInput(i, value);
  }

  /// "Use my own address": one window — the next unused address and every
  /// one that already received, each under the label Receive gave it (handy
  /// when steering change to yourself). A sheet on a phone.
  Future<void> _pickMyAddress(int i) async {
    final address = await showOwnAddressPicker(
      context,
      bridge: _bridge,
      walletId: _walletId,
      asset: _isBtc ? 'BTC' : 'LBTC',
      useSats: context.read<AppState>().useSats,
    );
    if (address == null || !mounted) return;
    setState(() => _outputs[i].addressCtrl.text = address);
  }

  /// Phone: the address field keeps its whole width for the address and the
  /// actions sit under it as labelled buttons — tooltips do not exist on
  /// touch, and three 48 dp icon buttons would eat half the field.
  Widget _addressActionStrip(int i) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        if (cameraScanSupported)
          SecondaryButton(
            label: 'Scan',
            icon: Icons.qr_code_scanner_outlined,
            dense: true,
            onPressed: () => _scanAddress(i),
          ),
        SecondaryButton(
          label: 'Paste',
          icon: Icons.content_paste_outlined,
          dense: true,
          onPressed: () => _pasteAddress(i),
        ),
        SecondaryButton(
          label: 'My address',
          icon: Icons.account_balance_wallet_outlined,
          dense: true,
          onPressed: () => _pickMyAddress(i),
        ),
      ],
    );
  }

  /// Desktop: scan, paste and use-my-address as small icon buttons at the
  /// field's trailing edge, each with its tooltip.
  Widget _addressActions(int i) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cameraScanSupported)
            _IconAction(
              icon: Icons.qr_code_scanner_outlined,
              tooltip: 'Scan QR',
              onTap: () => _scanAddress(i),
            ),
          _IconAction(
            icon: Icons.content_paste_outlined,
            tooltip: 'Paste',
            onTap: () => _pasteAddress(i),
          ),
          _IconAction(
            icon: Icons.account_balance_wallet_outlined,
            tooltip: 'Use my own address',
            onTap: () => _pickMyAddress(i),
          ),
        ],
      ),
    );
  }

  /// A "Total BTC" figure: the coin amount; tokens are their base units.
  String _totalCoinText(String ticker, int amount) =>
      (ticker == 'BTC' || ticker == 'LBTC')
      ? '${AmountUnits.coinText(amount)} $ticker'
      : '$amount $ticker';

  /// The fiat reading of a BTC/LBTC total, when a price is known.
  String? _totalFiatText(String ticker, int amount) {
    if (ticker != 'BTC' && ticker != 'LBTC') return null;
    final price = PriceService.instance;
    if (!price.hasPrice) return null;
    return '≈ ${price.symbol}${AmountUnits.fiatText(amount, price.btcPrice)}';
  }
}

// ── Formatting ────────────────────────────────────────────────────────────────

/// `3` for a whole rate, `2.5` otherwise.
String _fmtRate(double rate) => rate == rate.roundToDouble()
    ? rate.toStringAsFixed(0)
    : rate.toStringAsFixed(1);

/// `1,734,567` — sats are grouped (design.md, "Type").
String _groupDigits(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

// ── Field label ───────────────────────────────────────────────────────────────

/// A field's label: an `eyebrow` above it, never floating inside, with an
/// optional quiet fact on the right (the balance above an amount).
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final t = trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
          ),
          if (t != null) ...[
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                t,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Small icon action ─────────────────────────────────────────────────────────

/// An icon button at a field's edge or a card's corner: 32 square on the
/// desktop with a 16 px glyph, a 48 dp target on a phone. Hover is a surface
/// step and the accent on the glyph, keyboard focus a ring, and the tooltip
/// names the action.
class _IconAction extends StatefulWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone ? AppLayout.minTouchTarget : AppSpacing.xxl;
    final button = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: _hover ? s.hover : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Icon(
        widget.icon,
        size: phone ? 20 : AppSpacing.iconSmall,
        // Under the pointer the glyph takes the accent, as every icon
        // control does.
        color: _hover ? s.accentGlyph : s.inkSecondary,
      ),
    );
    final tappable = Semantics(
      button: true,
      label: widget.tooltip,
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: button,
        ),
      ),
    );
    if (phone) return tappable;
    return Tooltip(message: widget.tooltip, child: tappable);
  }
}

// ── Max toggle ────────────────────────────────────────────────────────────────

/// The Max affordance on an amount field: a quiet text button that is a real
/// two-state toggle. Engaged it takes the selected surface and the primary
/// ink, so "is Max on?" is answerable at a glance; tapping again turns it
/// off.
class _MaxToggle extends StatefulWidget {
  const _MaxToggle({required this.engaged, required this.onTap});

  final bool engaged;
  final VoidCallback onTap;

  @override
  State<_MaxToggle> createState() => _MaxToggleState();
}

class _MaxToggleState extends State<_MaxToggle> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final on = widget.engaged;
    final phone = AppLayout.isPhone(context);
    final chip = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      height: AppSpacing.xl,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: on ? s.selected : (_hover ? s.hover : Colors.transparent),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: on ? s.edgeStrong : Colors.transparent),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Text(
        'Max',
        style: AppTypography.label.copyWith(
          color: on || _hover ? s.ink : s.inkSecondary,
        ),
      ),
    );
    final tappable = Semantics(
      button: true,
      toggled: on,
      label: 'Max',
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          // Touch: the whole 48 dp slot taps, not just the 24 dp chip.
          child: phone
              ? ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: AppLayout.minTouchTarget,
                    minHeight: AppLayout.minTouchTarget,
                  ),
                  child: Center(child: chip),
                )
              : chip,
        ),
      ),
    );
    if (phone) return tappable;
    return Tooltip(
      message: on
          ? 'Max is on — tap to type an amount'
          : 'Send the whole balance',
      child: tappable,
    );
  }
}

// ── Transaction diagram (the flow) ────────────────────────────────────────────

/// The previewed transaction as a [TxFlowDiagram]: the coins it spends, each
/// payment, the change, the fee.
class _TxDiagram extends StatelessWidget {
  const _TxDiagram({
    required this.preview,
    required this.isBtcLike,
    required this.ticker,
    required this.liquid,
  });

  final TxPreview preview;
  final bool isBtcLike;
  final String ticker;
  final bool liquid;

  String _fmt(int sats) {
    if (isBtcLike) return '${(sats / 1e8).toStringAsFixed(8)} $ticker';
    return '$sats $ticker';
  }

  /// Per-output amount: the backend's precision-aware display when present
  /// (Liquid multi-asset), else the transaction-level format.
  String _fmtIo(TxIo io) {
    if (io.amountDisplay != null) return io.amountDisplay!;
    if (io.ticker != null) return '${io.amountSats} ${io.ticker}';
    return _fmt(io.amountSats);
  }

  @override
  Widget build(BuildContext context) => TxFlowDiagram(
    liquid: liquid,
    inputs: preview.inputs.isEmpty
        ? const [
            TxFlowEntry(
              role: TxFlowRole.autoInput,
              title: 'Chosen automatically',
              amount: 'Confidential',
              mono: false,
            ),
          ]
        : [
            for (final i in preview.inputs)
              TxFlowEntry(
                role: TxFlowRole.input,
                title: i.address,
                amount: _fmt(i.amountSats),
              ),
          ],
    outputs: [
      for (final o in preview.outputs)
        TxFlowEntry(
          role: o.isChange ? TxFlowRole.change : TxFlowRole.recipient,
          title: o.address,
          amount: _fmtIo(o),
        ),
      TxFlowEntry(
        role: TxFlowRole.fee,
        title: 'Network fee',
        amount: preview.feeDisplay,
        mono: false,
      ),
    ],
  );
}

// ── Review summary ────────────────────────────────────────────────────────────

/// The figures under the flow, one per row: amount, fee and its rate, size,
/// the confirmation target, and the total set apart under a hairline.
class _ReviewSummary extends StatelessWidget {
  const _ReviewSummary({required this.preview, required this.isBtc});
  final TxPreview preview;
  final bool isBtc;

  /// The same thresholds as the fee presets: a target, not a promise.
  String get _eta {
    if (!isBtc) return '~1 min';
    if (preview.feeRate >= 8) return '~10 min';
    if (preview.feeRate >= 3) return '~30 min';
    return '~60 min or more';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryRow(label: 'Amount', value: preview.amountDisplay),
          _SummaryRow(
            label: 'Fee',
            value: isBtc
                ? '${_groupDigits(preview.feeSats)} sats · ${_fmtRate(preview.feeRate)} sat/vB'
                : preview.feeDisplay,
          ),
          if (isBtc)
            _SummaryRow(label: 'Size', value: '~${preview.vsizeEst} vB'),
          _SummaryRow(label: 'Confirmation target', value: _eta),
          const SizedBox(height: AppSpacing.sm),
          Divider(height: 1, thickness: 1, color: s.edge),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(label: 'Total', value: preview.totalDisplay, total: true),
        ],
      ),
    );
  }
}

/// A key on the left in the secondary ink, its figure right-aligned in the
/// primary ink. 40 tall; the total takes the larger figure.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.total = false,
  });

  final String label;
  final String value;
  final bool total;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 40),
      child: Row(
        children: [
          Text(
            label,
            style: AppTypography.label.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style:
                  (total
                          ? AppTypography.numericLargeOf(context)
                          : AppTypography.numeric)
                      .copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
  }
}
