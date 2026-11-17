import 'dart:convert';
import 'dart:io' show Platform;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/cosigner_label_store.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/cosigner_label_editor.dart';
import '../../shared/widgets/cosigner_ring.dart'
    show CosignerEntry, resolveCosigners, signerSlotsFor;
import '../../shared/widgets/hybrid_kit.dart' show QuietTag;
import '../../shared/widgets/signer_donut.dart';
import '../../shared/widgets/step_header.dart' show SelectableOptionCard;
import '../../shared/widgets/ur_qr.dart'
    show UrAnimatedQr, cameraScanSupported, showUrScannerDialog;
import '../../services/file_export.dart';
import '../hardware/hw_error.dart';
import '../hardware/hw_platform.dart' show usbHardwareSupported;
import '../hardware/ledger_connect_dialog.dart';
import 'cosign_handoff.dart' show equalOptions, reportSaved, stackOrRow;
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'models/pset_inspection.dart';
import 'models/psbt_inspection.dart';

/// Which chain the transaction belongs to.
///
/// Asked first, as its own step (the owner's call, 2026-09-09): the user
/// knows which wallet's transaction they are holding, and answering it up
/// front lets the next screen ask for exactly one thing — a PSBT or a PSET —
/// and refuse the other with a reason. The payload's magic bytes still get
/// read, as the check that the answer and the blob agree.
enum CosignChain { bitcoin, liquid }

extension CosignChainWords on CosignChain {
  String get name => this == CosignChain.liquid ? 'Liquid' : 'Bitcoin';

  /// The artifact this chain's transactions travel as.
  String get artifact => this == CosignChain.liquid ? 'PSET' : 'PSBT';
}

/// Magic prefix of a serialized PSET: `pset\xff`. A PSBT starts `psbt\xff`.
const _psetMagic = [0x70, 0x73, 0x65, 0x74, 0xff];

/// Embeddable co-sign flow: choose the chain → paste a PSBT or PSET →
/// inspect → sign → export. Hosted by the Send screen's "Cosign a
/// transaction" mode; provides no Scaffold or page header of its own.
class CosignView extends StatefulWidget {
  const CosignView({super.key, this.bridge});

  /// Test seam: the engine this view talks to. Null in the app, which then
  /// uses the process-wide [walletBridge].
  final WalletBridge? bridge;

  @override
  State<CosignView> createState() => _CosignViewState();
}

class _CosignViewState extends State<CosignView> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;
  final _pasteController = TextEditingController();

  /// The chain the user said the transaction is on. Null until they have:
  /// the load card is not shown before then.
  CosignChain? _chosen;

  /// Whether "Sign with device" is worth offering. The Android APK links the
  /// engine with `--no-default-features`: hidapi, serialport, Jade and Ledger
  /// are not in the binary at all, so the button's only possible outcome
  /// there is an error. Asked of the engine rather than guessed from the
  /// platform — the wizard's key-source picker settles it the same way — and
  /// a failed probe leaves USB on offer, so a real error explains itself
  /// instead of an option quietly vanishing on a guess.
  bool _usbAvailable = usbHardwareSupported;

  /// Chain of the loaded transaction. Decides which backend calls sign,
  /// inspect and broadcast it.
  CosignChain _chain = CosignChain.bitcoin;

  PsbtInspection? _inspection;
  bool _loading = false;
  bool _signing = false;
  String? _error;

  /// A headline for [_error] when the error is the engine's own words: the
  /// headline is shown, the engine's text folds away under it. Null when
  /// [_error] is already a sentence written for the user.
  String? _errorTitle;
  String? _signedPsbt;

  /// The open wallet's keys with their names and colours, so the quorum
  /// chart can say "Anna's phone" rather than `bb000002`. Empty for a
  /// wallet with no co-signers.
  List<CosignerEntry> _cosigners = const [];

  /// Re-inspection of the PSBT after our signature was added — drives the
  /// quorum display and the "Finalize & Broadcast" gate.
  PsbtInspection? _signedInspection;
  bool _broadcasting = false;
  String? _txid;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _checkUsb();
    _loadCosigners();
  }

  Future<void> _loadCosigners() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    try {
      final info = await _bridge.getWalletInfo(walletId);
      if (info.cosignerKeys.length < 2) return;
      final labels = await CosignerLabelStore.instance.load(walletId);
      if (!mounted) return;
      setState(
        () => _cosigners = resolveCosigners(
          cosignerKeys: info.cosignerKeys,
          labels: labels,
          localFingerprints: info.localFingerprints,
        ),
      );
    } catch (_) {
      // Names are a convenience; the chart works by fingerprint without them.
    }
  }

  /// The chart's slots for [i]: the wallet's labels where the fingerprints
  /// match, fingerprints otherwise.
  List<SignerSlot>? _slotsFor(PsbtInspection i) => i.signers.isEmpty
      ? null
      : signerSlotsFor(
          entries: _cosigners,
          signerFingerprints: i.signers.map((x) => x.fingerprint),
          signedFingerprints: [
            for (final x in i.signers)
              if (x.hasSigned) x.fingerprint,
          ],
        );

  /// The rename control for a signer row: only for a key the open wallet
  /// knows, and it goes through the same label editor as the dashboard.
  VoidCallback? _renameFor(SignerSlot slot) {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return null;
    CosignerEntry? entry;
    for (final e in _cosigners) {
      if (e.fingerprint.isNotEmpty && e.fingerprint == slot.id.toLowerCase()) {
        entry = e;
        break;
      }
    }
    final known = entry;
    if (known == null) return null;
    return () async {
      final edited = await showCosignerLabelEditor(
        context,
        label: known.label,
        index: known.index,
        subtitle: '${known.fingerprint} · m/${known.path}',
      );
      if (edited == null || !mounted) return;
      await CosignerLabelStore.instance.saveOne(walletId, edited);
      await _loadCosigners();
    };
  }

  Future<void> _checkUsb() async {
    if (!Platform.isAndroid) return;
    bool supported;
    try {
      supported = (await _bridge.hwiStatus()).hardwareSupported;
    } catch (_) {
      return;
    }
    if (!mounted || supported) return;
    setState(() => _usbAvailable = false);
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  /// Inspect a PSBT or PSET from any source (paste / file / QR). Shared by all
  /// three. The chain was chosen a step earlier; the payload's magic bytes
  /// are read only to catch a blob from the other chain, which is refused
  /// with the reason rather than handed to a decoder that will not know it.
  Future<void> _inspectText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final chain = _chosen ?? _detectChain(trimmed);
    final detected = _detectChain(trimmed);
    if (detected != chain) {
      setState(() {
        _errorTitle = null;
        _error = chain == CosignChain.bitcoin
            ? 'This is a Liquid PSET, not a Bitcoin PSBT. Go back and choose '
                  'Liquid to co-sign it.'
            : 'This is not a Liquid PSET. If it is a Bitcoin PSBT, go back and '
                  'choose Bitcoin to co-sign it.';
      });
      return;
    }
    setState(() {
      _chain = chain;
      _loading = true;
      _error = null;
      _errorTitle = null;
      _signedPsbt = null;
      _signedInspection = null;
      _txid = null;
    });
    try {
      final result = await _inspectFor(trimmed, chain);
      if (mounted) {
        setState(() {
          _inspection = result;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorTitle = 'This ${chain.artifact} could not be read';
          _error = e.toString().replaceFirst('Exception: wallet-ffi: ', '');
        });
      }
    }
  }

  /// Read the chain off the payload's magic bytes. Anything that is not a
  /// recognizable PSET is handed to the Bitcoin path, which reports a decode
  /// error of its own — better than this guess inventing one.
  static CosignChain _detectChain(String base64Text) {
    try {
      final bytes = base64.decode(base64Text);
      if (bytes.length >= _psetMagic.length) {
        for (var i = 0; i < _psetMagic.length; i++) {
          if (bytes[i] != _psetMagic[i]) return CosignChain.bitcoin;
        }
        return CosignChain.liquid;
      }
    } catch (_) {
      // Not base64 at all — let the Bitcoin decoder produce the message.
    }
    return CosignChain.bitcoin;
  }

  /// Inspect through the right backend and normalise the answer, so the whole
  /// display below stays chain-agnostic.
  Future<PsbtInspection> _inspectFor(String raw, CosignChain chain) async {
    if (chain == CosignChain.bitcoin) return _bridge.inspectPsbt(raw);
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) {
      throw Exception(
        'Open the Liquid wallet this transaction belongs to first — its '
        'amounts are confidential and only that wallet can read them.',
      );
    }
    return _asPsbtInspection(await _bridge.inspectPset(walletId, raw));
  }

  /// A PSET rendered in the same shape as a PSBT, so one review screen serves
  /// both.
  ///
  /// Inputs come from the engine's script view: every input, tagged with
  /// whether it asks for this wallet's signature and whether it is a script
  /// contract (a Templar Protocol escrow is a P2WSH input carrying our `2121'`
  /// key). Amounts are blinded commitments unless the PSET carries them
  /// explicitly, so a row may show "Confidential". Older engines without
  /// the script view leave the list empty and the panel is hidden.
  ///
  /// Outputs prefer the classified list (own / escrow / external / fee) and
  /// fall back to LWK's recipients.
  static PsbtInspection _asPsbtInspection(PsetInspection p) => PsbtInspection(
    inputs: [
      for (final i in p.inputs)
        PsbtInput(
          outpoint: i.outpoint,
          amountSats: i.amountSats,
          displayAmount: _inputLabel(i),
        ),
    ],
    outputs: p.outputs.isNotEmpty
        ? [
            for (final o in p.outputs)
              if (!o.isFee)
                PsbtOutput(
                  address:
                      '${o.kindLabel}: '
                      '${o.address ?? (o.isEscrow ? 'P2WSH contract (no address)' : 'confidential output')}',
                  amountSats: o.amountSats ?? 0,
                  displayAmount: o.unverified
                      ? _unverifiable
                      : o.displayAmount ??
                            (o.ticker != null
                                ? '$_confidential (${o.ticker})'
                                : _confidential),
                ),
          ]
        : [
            for (final r in p.recipients)
              PsbtOutput(
                address: r.address ?? 'confidential output (not ours to read)',
                amountSats: r.amountSats ?? 0,
                displayAmount: r.unverified
                    ? _unverifiable
                    : r.displayAmount ??
                          (r.ticker != null
                              ? '$_confidential (${r.ticker})'
                              : _confidential),
              ),
          ],
    feeSats: p.feeSats,
    feeDisplay: p.feeDisplay,
    sigsPresent: p.sigsHave,
    sigsRequired: p.sigsNeeded,
    signers: [
      for (final fp in p.signersPresent)
        PsbtSigner(fingerprint: fp, hasSigned: true),
      for (final fp in p.signersMissing)
        PsbtSigner(fingerprint: fp, hasSigned: false),
    ],
    policyHint: p.sigsNeeded > 1
        ? 'Liquid ${p.sigsNeeded}-of-${p.signersPresent.length + p.signersMissing.length} multisig'
        : 'Liquid transaction',
    rawPsbt: p.rawPset,
    // An output whose amount its commitment does not prove hides what
    // the signature pays, exactly like an inconsistent PSBT input.
    utxoCheck: p.hasUnverifiedOutputs
        ? PsbtUtxoStatus.conflicting
        : PsbtUtxoStatus.ok,
  );

  /// What a blinded Liquid amount is called on screen. Never a zero: the
  /// value exists, this wallet just cannot read it.
  static const _confidential = 'Confidential';

  /// An output whose commitment does not prove its amount.
  static const _unverifiable = 'Unverifiable amount — do not sign';

  /// Amount column of a Liquid input row: the explicit amount when the PSET
  /// carries one, plus who the input belongs to.
  static String _inputLabel(PsetInput i) {
    final amount = i.unverified && !i.isOurs
        ? 'Unverifiable amount'
        : i.displayAmount ??
              (i.ticker != null
                  ? '$_confidential (${i.ticker})'
                  : _confidential);
    final who = i.isOurs
        ? (i.isScriptHash ? 'contract · your key' : 'your coin')
        : (i.isScriptHash ? 'contract · not yours' : 'not yours');
    return '$amount · $who';
  }

  void _loadPsbt() => _inspectText(_pasteController.text);

  /// Open a `.psbt`/`.pset`/`.txt` file and inspect it. Binary PSBTs (magic
  /// `psbt\xff`) are base64-encoded; text files are taken as-is.
  Future<void> _pickFile() async {
    try {
      final liquid = _chosen == CosignChain.liquid;
      final group = XTypeGroup(
        label: liquid ? 'PSET' : 'PSBT',
        extensions: [liquid ? 'pset' : 'psbt', 'txt'],
        // macOS UTIs — allow both a dedicated PSBT type and plain text.
        uniformTypeIdentifiers: const ['public.text', 'public.data'],
      );
      final file = await openFile(acceptedTypeGroups: [group]);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      await _inspectText(_psbtBytesToBase64(bytes));
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorTitle = 'Could not read the file';
          _error = '$e';
        });
      }
    }
  }

  static String _psbtBytesToBase64(Uint8List bytes) {
    // Binary PSBT starts `psbt\xff`, binary PSET `pset\xff`. Both are files a
    // co-signer's tool may hand back, and both need base64 before the backend
    // will look at them.
    const psbtMagic = [0x70, 0x73, 0x62, 0x74, 0xff];
    bool startsWith(List<int> magic) {
      if (bytes.length < magic.length) return false;
      for (var i = 0; i < magic.length; i++) {
        if (bytes[i] != magic[i]) return false;
      }
      return true;
    }

    if (startsWith(psbtMagic) || startsWith(_psetMagic)) {
      return base64.encode(bytes);
    }
    // Otherwise the file already holds base64 (or hex) text.
    return utf8.decode(bytes, allowMalformed: true).trim();
  }

  /// Open the shared camera scanner; inspect whatever QR payload comes back.
  /// The shared dialog reassembles multi-frame BC-UR payloads — a PSBT as
  /// `ur:crypto-psbt`, a PSET as Templar's `ur:bytes` animation — and the
  /// chain check in [_inspectText] catches a code from the other chain.
  Future<void> _scanQr() async {
    final artifact = (_chosen ?? CosignChain.bitcoin).artifact;
    final outcome = await showUrScannerDialog(
      context,
      expectPsbt: true,
      title: 'Scan $artifact QR code',
    );
    final result = outcome?.transactionBase64 ?? outcome?.descriptor;
    if (result == null || result.trim().isEmpty) return;
    await _inspectText(result);
  }

  Future<void> _sign() async {
    final inspection = _inspection;
    if (inspection == null) return;
    // The engine refuses these too; saying so here spares a password prompt
    // for a signature that can never be made.
    if (!inspection.utxoCheckOk) {
      setState(() {
        _errorTitle = null;
        _error =
            'This transaction hides what it spends — its amounts '
            'cannot be proven, so it will not be signed.';
      });
      return;
    }
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    await _runSign(
      () => _chain == CosignChain.liquid
          ? _bridge.signPset(walletId, inspection.rawPsbt)
          : _bridge.signPsbt(walletId, inspection.rawPsbt),
    );
  }

  /// Co-sign with a connected USB device.
  ///
  /// This is the only route by which a hardware key enrolled in a multisig
  /// actually signs: the send flow picks its signing path from the wallet's
  /// type, and a multisig wallet's type is "Multisig" — never
  /// "Hardware (…)" — so a device that was enrolled as a cosigner could
  /// contribute an xpub and then never be asked for a signature.
  Future<void> _signWithDevice() async {
    final inspection = _inspection;
    if (inspection == null) return;

    // Liquid skips the device picker: a Jade is the only device that can sign
    // an Elements transaction, so there is nothing to choose between. The
    // backend connects over serial and registers the multisig on the device
    // before asking for the signature.
    if (_chain == CosignChain.liquid) {
      final walletId = context.read<AppState>().activeWalletId;
      if (walletId == null) return;
      await _runSign(() => _bridge.signPsetHw(walletId, inspection.rawPsbt));
      return;
    }

    final device = await showHwDevicePickerDialog(
      context,
      title: 'Connect the co-signing device',
    );
    if (device == null || !mounted) return;
    await _runSign(
      () => _bridge.signPsbtHw(device.fingerprint, inspection.rawPsbt),
    );
  }

  /// Shared signing wrapper: both routes produce a signed PSBT and both need
  /// the same re-inspection and error handling around it.
  Future<void> _runSign(Future<String> Function() sign) async {
    setState(() {
      _signing = true;
      _error = null;
      _errorTitle = null;
    });
    try {
      final signed = await sign();
      // Re-inspect to learn whether the quorum is now met. Display-only — a
      // failure here must not lose the signed PSBT.
      PsbtInspection? after;
      try {
        after = await _inspectFor(signed, _chain);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _signedPsbt = signed;
          _signedInspection = after;
          _signing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signing = false;
          _errorTitle = null;
          _error = friendlyHwError(e);
        });
      }
    }
  }

  /// Finalize the fully-signed PSBT and hand it to the network. Available
  /// once every required signature is present — whether we just added the
  /// last one, or a complete PSBT was loaded for broadcast.
  Future<void> _broadcast() async {
    final psbt = _signedPsbt ?? _inspection?.rawPsbt;
    if (psbt == null) return;
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    setState(() {
      _broadcasting = true;
      _error = null;
      _errorTitle = null;
    });
    try {
      final txid = _chain == CosignChain.liquid
          ? await _bridge.broadcastPset(walletId, psbt)
          : await _bridge.broadcastSignedPsbt(
              walletId: walletId,
              psbtBase64: psbt,
            );
      if (mounted) {
        setState(() {
          _txid = txid;
          _broadcasting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _broadcasting = false;
          _errorTitle = null;
          _error = e.toString().replaceFirst('Exception: wallet-ffi: ', '');
        });
      }
    }
  }

  Future<void> _copySignedPsbt() async {
    if (_signedPsbt == null) return;
    await Clipboard.setData(ClipboardData(text: _signedPsbt!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  /// Back to the load card of the same chain: the transaction is dropped,
  /// the chain answer is kept.
  void _reset() => setState(() {
    _inspection = null;
    _signedPsbt = null;
    _signedInspection = null;
    _txid = null;
    _broadcasting = false;
    _error = null;
    _errorTitle = null;
    _pasteController.clear();
  });

  void _chooseChain(CosignChain chain) => setState(() {
    _chosen = chain;
    _chain = chain;
    _error = null;
    _errorTitle = null;
  });

  /// Back to the chain question. Only offered before anything is loaded —
  /// once a transaction is on screen, Decline is the way out.
  void _changeChain() {
    _reset();
    setState(() => _chosen = null);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final Widget body;
    if (chosen == null) {
      body = _ChainStep(
        liquidAvailable: context.watch<AppState>().activeWalletLiquid,
        onChoose: _chooseChain,
      );
    } else if (_inspection == null && !_loading) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GhostButton(
              icon: Icons.arrow_back_outlined,
              label: '${chosen.name} · change chain',
              onPressed: _changeChain,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _LoadPsbtCard(
            chain: chosen,
            controller: _pasteController,
            onLoadPaste: _loadPsbt,
            onPickFile: _pickFile,
            onScan: _scanQr,
            error: _error,
            errorTitle: _errorTitle,
          ),
        ],
      );
    } else if (_loading) {
      body = Padding(
        padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else {
      body = PsbtInspectionPanel(
        inspection: _inspection!,
        chain: _chain,
        signedInspection: _signedInspection,
        signing: _signing,
        signedPsbt: _signedPsbt,
        broadcasting: _broadcasting,
        txid: _txid,
        copied: _copied,
        usbAvailable: _usbAvailable,
        // Broadcasting belongs to the session that started the
        // transaction — the coordinator's sheet. A co-signer on a phone
        // signs and hands the copy back; it never sends.
        allowBroadcast: !AppLayout.isMobilePlatform,
        slots: _slotsFor(_signedInspection ?? _inspection!),
        error: _error,
        onRename: _renameFor,
        onSign: _sign,
        onSignWithDevice: _signWithDevice,
        onBroadcast: _broadcast,
        onCopy: _copySignedPsbt,
        onDecline: _reset,
      );
    }
    // One readable column for the whole flow, the same width on every step,
    // aligned with the page title above it.
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _columnWidth),
        child: body,
      ),
    );
  }
}

/// The co-sign flow's column: one width from the chain question to the
/// signed hand-off.
const double _columnWidth = 720;

// ── Chain step ────────────────────────────────────────────────────────────────

/// "Which chain?" — the co-sign flow's first question. Picking a card moves
/// on, as the Send wizard's type step does; there is nothing else to decide
/// on this screen.
class _ChainStep extends StatelessWidget {
  const _ChainStep({required this.liquidAvailable, required this.onChoose});

  /// Whether the open wallet has a Liquid side. A PSET's amounts are
  /// confidential and only the wallet they belong to can read them, so a
  /// wallet without Liquid has nothing to co-sign there.
  final bool liquidAvailable;
  final void Function(CosignChain) onChoose;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Which chain?',
          style: AppTypography.sectionTitle.copyWith(color: s.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'The transaction you were handed belongs to one of them',
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        SelectableOptionCard(
          title: 'Bitcoin',
          description:
              'A PSBT from a Bitcoin multisig, an air-gapped signer, or '
              'another Bitcoin wallet',
          isSelected: false,
          icon: Icons.currency_bitcoin,
          onTap: () => onChoose(CosignChain.bitcoin),
        ),
        const SizedBox(height: AppSpacing.md),
        SelectableOptionCard(
          title: 'Liquid',
          description: liquidAvailable
              ? 'A PSET from a Liquid multisig. Its amounts are '
                    'confidential, so it must be opened with the wallet it '
                    'belongs to — this one.'
              : 'This wallet has no Liquid side. Open the Liquid wallet the '
                    'transaction belongs to, then come back here.',
          isSelected: false,
          icon: Icons.water_drop_outlined,
          onTap: liquidAvailable ? () => onChoose(CosignChain.liquid) : null,
        ),
      ],
    );
  }
}

// ── Load step (paste / file / scan) ───────────────────────────────────────────

class _LoadPsbtCard extends StatefulWidget {
  const _LoadPsbtCard({
    required this.chain,
    required this.controller,
    required this.onLoadPaste,
    required this.onPickFile,
    required this.onScan,
    this.error,
    this.errorTitle,
  });

  /// Names the artifact on every tile: a PSBT on Bitcoin, a PSET on Liquid.
  final CosignChain chain;
  final TextEditingController controller;
  final VoidCallback onLoadPaste;
  final Future<void> Function() onPickFile;
  final Future<void> Function() onScan;

  /// Why the last load failed, shown under the sources.
  final String? error;
  final String? errorTitle;

  @override
  State<_LoadPsbtCard> createState() => _LoadPsbtCardState();
}

class _LoadPsbtCardState extends State<_LoadPsbtCard> {
  /// Whether the Paste tile is open (revealing its text field). File and Scan
  /// tiles fire their native flows directly, so they need no open state.
  bool _pasteOpen = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    // Three equal sources: side by side on a desktop, stacked full-width
    // rows on a phone, where three squares do not fit a line.
    final phone = AppLayout.isPhone(context);
    final artifact = widget.chain.artifact;
    final tiles = <Widget>[
      _SourceTile(
        icon: Icons.content_paste_outlined,
        label: 'Paste',
        sub: 'base64 $artifact text',
        tooltip: 'Paste the $artifact as text',
        selected: _pasteOpen,
        wide: phone,
        onTap: () => setState(() => _pasteOpen = !_pasteOpen),
      ),
      _SourceTile(
        icon: Icons.folder_open_outlined,
        label: 'Open file',
        sub: '.${artifact.toLowerCase()}',
        tooltip: 'Open a .${artifact.toLowerCase()} or .txt file',
        wide: phone,
        onTap: () {
          setState(() => _pasteOpen = false);
          widget.onPickFile();
        },
      ),
      // Only where a camera exists: on Windows and Linux mobile_scanner has no
      // implementation, and the tile's only outcome is an apology dialog. Both
      // chains scan: a PSBT arrives as ur:crypto-psbt, a PSET as the ur:bytes
      // animation another Templar shows for it.
      if (cameraScanSupported)
        _SourceTile(
          icon: Icons.qr_code_scanner_outlined,
          label: 'Scan QR',
          sub: 'camera',
          tooltip: 'Scan the $artifact QR with the camera',
          wide: phone,
          onTap: () {
            setState(() => _pasteOpen = false);
            widget.onScan();
          },
        ),
    ];
    final error = widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Load the $artifact',
          style: AppTypography.sectionTitle.copyWith(color: s.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Paste it, open its file, or scan its QR',
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (phone)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                tiles[i],
              ],
            ],
          )
        else
          Row(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                Expanded(child: tiles[i]),
              ],
            ],
          ),
        if (_pasteOpen) ...[
          const SizedBox(height: AppSpacing.xl),
          _PasteSource(
            artifact: artifact,
            controller: widget.controller,
            onLoad: widget.onLoadPaste,
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _InlineError(title: widget.errorTitle, message: error),
        ],
      ],
    );
  }
}

/// One source (Paste / Open file / Scan QR): the raised-surface grammar of
/// every option in the app — a hairline at rest, a hover step, and the
/// selected surface with a firmer edge while its box is open.
class _SourceTile extends StatefulWidget {
  const _SourceTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.tooltip,
    required this.onTap,
    this.selected = false,
    this.wide = false,
  });
  final IconData icon;
  final String label;
  final String sub;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  /// Phone shape: a full-width row, so the sources stack down the column.
  final bool wide;

  @override
  State<_SourceTile> createState() => _SourceTileState();
}

class _SourceTileState extends State<_SourceTile> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final selected = widget.selected;
    final radius = widget.wide
        ? AppSpacing.radiusPhoneControl
        : AppSpacing.radiusLg;
    final fill = selected
        ? s.selected
        : _hover
        ? Color.alphaBlend(s.hover, s.panel)
        : s.panel;
    final edge = selected || _hover ? s.edgeStrong : s.edge;

    final label = Text(
      widget.label,
      style: AppTypography.bodyOf(
        context,
      ).copyWith(color: s.ink, fontWeight: FontWeight.w500),
    );
    final sub = Text(
      widget.sub,
      style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
    );
    final icon = Icon(
      widget.icon,
      size: widget.wide ? 22 : AppSpacing.icon,
      color: selected ? s.ink : s.inkSecondary,
    );

    final tile = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      constraints: BoxConstraints(
        minHeight: widget.wide ? AppSpacing.phoneFieldHeight : 96,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: widget.wide
          ? Row(
              children: [
                icon,
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [label, sub],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: AppSpacing.md),
                label,
                sub,
              ],
            ),
    );

    final control = Semantics(
      button: true,
      selected: selected,
      label: widget.label,
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
          child: tile,
        ),
      ),
    );
    // A phone has no hover to show a tooltip on; the sub-line says it.
    if (widget.wide) return control;
    return Tooltip(message: widget.tooltip, child: control);
  }
}

class _PasteSource extends StatelessWidget {
  const _PasteSource({
    required this.artifact,
    required this.controller,
    required this.onLoad,
  });
  final String artifact;
  final TextEditingController controller;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$artifact text',
          style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: controller,
          maxLines: 6,
          minLines: 4,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: 'Base64 $artifact'),
          style: AppTypography.mono.copyWith(color: s.ink),
        ),
        const SizedBox(height: AppSpacing.lg),
        Align(
          alignment: Alignment.centerRight,
          child: PrimaryButton(
            label: 'Load and inspect',
            isFullWidth: phone,
            onPressed: onLoad,
          ),
        ),
      ],
    );
  }
}

/// A load that failed, said where the sources are. A sentence written for
/// the user stands alone; the engine's own words fold away under a headline,
/// in a mono well, for whoever needs them.
class _InlineError extends StatefulWidget {
  const _InlineError({required this.message, this.title});
  final String message;
  final String? title;

  @override
  State<_InlineError> createState() => _InlineErrorState();
}

class _InlineErrorState extends State<_InlineError> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final title = widget.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.error_outline,
                size: AppSpacing.iconSmall,
                color: s.danger,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                title ?? widget.message,
                style: AppTypography.caption.copyWith(color: s.danger),
              ),
            ),
            if (title != null)
              GhostButton(
                label: _open ? 'Hide details' : 'Details',
                onPressed: () => setState(() => _open = !_open),
              ),
          ],
        ),
        if (title != null && _open) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: s.well,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: s.edge),
            ),
            child: SelectableText(
              widget.message,
              style: AppTypography.mono.copyWith(color: s.inkSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Loaded transaction ────────────────────────────────────────────────────────

/// Everything shown once a PSBT or PSET has been decoded: where its
/// signatures stand, who has signed, what it does, and the actions.
///
/// Public so it can be driven from a test with a hand-written
/// [PsbtInspection] — reaching the signer list and the action row through the
/// real engine would need a multisig PSBT fixture to assert on what are pure
/// layout decisions.
class PsbtInspectionPanel extends StatelessWidget {
  const PsbtInspectionPanel({
    super.key,
    required this.inspection,
    required this.chain,
    required this.signedInspection,
    required this.signing,
    required this.signedPsbt,
    required this.broadcasting,
    required this.txid,
    required this.copied,
    this.usbAvailable = true,
    this.allowBroadcast = true,
    this.slots,
    this.error,
    this.onRename,
    required this.onSign,
    required this.onSignWithDevice,
    required this.onBroadcast,
    required this.onCopy,
    required this.onDecline,
  });

  final PsbtInspection inspection;

  /// Which chain this transaction is on. Only changes wording and the inputs
  /// block — a PSET reports what it pays, not what it spends.
  final CosignChain chain;

  final PsbtInspection? signedInspection;
  final bool signing;
  final String? signedPsbt;
  final bool broadcasting;
  final String? txid;
  final bool copied;

  /// Whether this build can talk to a USB signer at all — false on Android,
  /// whose engine is linked without the hardware stack.
  final bool usbAvailable;

  /// Whether "Finalize and broadcast" is offered here at all. False on a
  /// phone: broadcasting is the coordinator's move, in the session that
  /// built the transaction; a co-signer's job ends at handing the signed
  /// copy back.
  final bool allowBroadcast;

  /// The signers by name, when the open wallet knows them. Null: one row
  /// per fingerprint the inspection names.
  final List<SignerSlot>? slots;

  /// A signing or broadcast failure, shown above the actions.
  final String? error;

  /// The rename control for a signer row, or null where there is none.
  final VoidCallback? Function(SignerSlot slot)? onRename;

  final VoidCallback onSign;

  /// Co-sign with a connected USB hardware device.
  final VoidCallback onSignWithDevice;
  final VoidCallback onBroadcast;
  final VoidCallback onCopy;
  final VoidCallback onDecline;

  /// Every required signature is present — the PSBT can be finalized and
  /// broadcast. Only claimed when the threshold is actually known.
  bool get _isComplete {
    final i = signedInspection ?? inspection;
    return i.sigsRequired != null && i.sigsPresent >= i.sigsRequired!;
  }

  /// Complete AND this surface may broadcast.
  bool get _offersBroadcast => allowBroadcast && _isComplete;

  /// The transaction's state in words. Every count in it is the engine's.
  String _stateLine(PsbtInspection i, List<SignerSlot> rows) {
    if (_isComplete) {
      return allowBroadcast
          ? 'Fully signed, ready to broadcast'
          : 'Fully signed';
    }
    final mineSigned = rows.any((x) => x.isLocal && x.signed);
    if (signedPsbt == null && mineSigned) return 'You have already signed this';
    final required = i.sigsRequired;
    if (required != null) {
      final left = required - i.sigsPresent;
      return 'Needs $left more signature${left == 1 ? '' : 's'}';
    }
    return i.sigsPresent > 0 ? 'Partially signed' : 'Not signed yet';
  }

  @override
  Widget build(BuildContext context) {
    // Post-signature inspection supersedes the original: same transaction,
    // but with our signature counted.
    final i = signedInspection ?? inspection;
    final rows = (slots != null && slots!.isNotEmpty)
        ? slots!
        : [
            for (final x in i.signers)
              SignerSlot(id: x.fingerprint, signed: x.hasSigned),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignatureHeader(
          state: _stateLine(i, rows),
          signed: i.sigsPresent,
          required: i.sigsRequired,
        ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SignerList(slots: rows, onRename: onRename),
        ],
        const SizedBox(height: AppSpacing.xl),
        _FlowCard(inspection: i, chain: chain),
        // Broadcast result / signed copy going out
        if (txid != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _BroadcastResultCard(txid: txid!),
        ] else if (signedPsbt != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _SignedExportCard(
            signedPsbt: signedPsbt!,
            chain: chain,
            copied: copied,
            onCopy: onCopy,
            message: _exportMessage(i),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: AppSpacing.xl),
          DangerBanner(message: error!),
        ],
        const SizedBox(height: AppSpacing.xl),
        _actionRow(context),
      ],
    );
  }

  /// The buttons under the transaction: one right-aligned line on a desktop,
  /// a full-width stack on a phone. The list is written most important
  /// first, which is the stack's order; the desktop row reverses it so the
  /// primary sits last, at the right.
  Widget _actionRow(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final buttons = <Widget>[];

    if (txid != null) {
      buttons.add(
        SecondaryButton(
          label: 'Co-sign another transaction',
          isFullWidth: phone,
          onPressed: onDecline,
        ),
      );
    } else if (signedPsbt == null) {
      if (signing || broadcasting) {
        return const Align(
          alignment: Alignment.centerRight,
          child: _ActionSpinner(),
        );
      }
      // A loaded PSBT that already carries every signature (e.g. the
      // coordinator got it back from the last cosigner) skips straight to
      // broadcast — where this surface may broadcast at all.
      if (_offersBroadcast) {
        buttons.add(
          PrimaryButton(
            label: 'Finalize and broadcast',
            icon: Icons.send_outlined,
            isFullWidth: phone,
            onPressed: onBroadcast,
          ),
        );
        buttons.add(
          SecondaryButton(
            label: 'Sign',
            icon: Icons.draw_outlined,
            isFullWidth: phone,
            onPressed: onSign,
          ),
        );
      } else {
        buttons.add(
          PrimaryButton(
            label: 'Sign',
            icon: Icons.draw_outlined,
            isFullWidth: phone,
            onPressed: onSign,
          ),
        );
        // Offered next to the software key, not instead of it: a multisig
        // quorum is routinely a mix of both. Not on Android, which has no USB
        // stack at all — there the button's only outcome is an error.
        if (usbAvailable) {
          buttons.add(
            SecondaryButton(
              label: 'Sign with device',
              icon: Icons.usb_outlined,
              isFullWidth: phone,
              onPressed: onSignWithDevice,
            ),
          );
        }
      }
      buttons.add(
        GhostButton(label: 'Decline', isFullWidth: phone, onPressed: onDecline),
      );
    } else {
      if (_offersBroadcast) {
        if (broadcasting) {
          return const Align(
            alignment: Alignment.centerRight,
            child: _ActionSpinner(),
          );
        }
        buttons.add(
          PrimaryButton(
            label: 'Finalize and broadcast',
            icon: Icons.send_outlined,
            isFullWidth: phone,
            onPressed: onBroadcast,
          ),
        );
      }
      buttons.add(
        SecondaryButton(
          label: 'Co-sign another transaction',
          isFullWidth: phone,
          onPressed: onDecline,
        ),
      );
    }

    if (phone) return stackOrRow(true, buttons);
    final row = buttons.reversed.toList();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 0; i < row.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.sm),
          row[i],
        ],
      ],
    );
  }

  /// The word for what the user is holding, on the chain they are on.
  String get _artifact => chain == CosignChain.liquid ? 'PSET' : 'PSBT';

  /// Copy under the signed export card: either the quorum is met and the
  /// transaction is broadcast-ready, or it states how many signatures are
  /// missing.
  String _exportMessage(PsbtInspection i) {
    if (_isComplete) {
      return allowBroadcast
          ? 'All ${i.sigsRequired} required signatures are present. Finalize '
                'and broadcast below, or copy the $_artifact to broadcast '
                'elsewhere.'
          : 'All ${i.sigsRequired} required signatures are present. Hand this '
                '$_artifact back to whoever started the transaction — it is '
                'broadcast from there.';
    }
    final required = i.sigsRequired;
    if (required != null) {
      final missing = (required - i.sigsPresent).clamp(1, required);
      return 'Your signature has been added. $missing more '
          'signature${missing == 1 ? '' : 's'} needed — pass the $_artifact '
          'on to the other signers or the coordinator.';
    }
    return 'Your signature has been added. Pass the $_artifact on to the '
        'other signers or the coordinator.';
  }
}

class _ActionSpinner extends StatelessWidget {
  const _ActionSpinner();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

/// What the transaction does, in the neutral flow grammar of Send's review:
/// what goes in, where it goes, the fee. Every amount and address is the
/// inspection's text, untouched; outpoints and addresses are never
/// truncated.
class _FlowCard extends StatelessWidget {
  const _FlowCard({required this.inspection, required this.chain});
  final PsbtInspection inspection;
  final CosignChain chain;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final i = inspection;
    // A PSET lists its inputs only when the engine's script view is present
    // (it tags each input with whose key it asks for); without it an empty
    // block would read as "spends nothing", so it is left out.
    final showInputs = chain == CosignChain.bitcoin || i.inputs.isNotEmpty;
    final known = i.ownershipKnown;
    final rule = Divider(height: AppSpacing.xl, thickness: 1, color: s.edge);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'What it does',
            style: AppTypography.sectionTitle.copyWith(color: s.ink),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (showInputs) ...[
            for (var n = 0; n < i.inputs.length; n++) ...[
              if (n > 0) const SizedBox(height: AppSpacing.md),
              _FlowRow(
                role: 'In',
                subject: i.inputs[n].outpoint,
                amount: i.inputs[n].displayAmount,
                yours: known && i.inputs[n].isMine == true,
              ),
            ],
            rule,
          ],
          for (var n = 0; n < i.outputs.length; n++) ...[
            if (n > 0) const SizedBox(height: AppSpacing.md),
            _FlowRow(
              role: 'To',
              subject: i.outputs[n].address,
              amount: i.outputs[n].displayAmount,
              yours: known && i.outputs[n].isMine == true,
            ),
          ],
          rule,
          _TotalRow(label: 'Fee', value: i.feeDisplay, figure: true),
          if (i.policyHint.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _TotalRow(label: 'Policy', value: i.policyHint),
          ],
        ],
      ),
    );
  }
}

/// One leg of the flow: a quiet role word, the outpoint or address in mono,
/// the amount in the tabular figure face. A blinded Liquid amount is a word
/// in the faint ink, never a zero; an unverifiable one is in the danger ink.
class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.role,
    required this.subject,
    required this.amount,
    this.yours = false,
  });

  final String role;
  final String subject;
  final String amount;

  /// The engine says this coin or address belongs to the open wallet.
  final bool yours;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final lower = amount.toLowerCase();
    final TextStyle amountStyle;
    if (lower.contains('unverifiable')) {
      amountStyle = AppTypography.caption.copyWith(color: s.danger);
    } else if (lower.startsWith('confidential')) {
      amountStyle = AppTypography.caption.copyWith(color: s.inkFaint);
    } else {
      amountStyle = AppTypography.numeric.copyWith(color: s.ink);
    }
    final roleText = SizedBox(
      width: 48,
      child: Text(
        role,
        style: AppTypography.caption.copyWith(color: s.inkFaint),
      ),
    );
    final subjectText = SelectableText(
      subject,
      style: AppTypography.mono.copyWith(color: s.ink),
    );
    final amountCol = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (yours) ...[
          const QuietTag(label: 'Yours'),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(amount, style: amountStyle, textAlign: TextAlign.right),
        ),
      ],
    );
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              roleText,
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: amountCol,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          subjectText,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        roleText,
        Expanded(child: subjectText),
        const SizedBox(width: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: amountCol,
        ),
      ],
    );
  }
}

/// A key and its value on one line, the value right-aligned.
class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.figure = false,
  });
  final String label;
  final String value;
  final bool figure;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.label.copyWith(color: s.inkSecondary)),
        const SizedBox(width: AppSpacing.lg),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: (figure ? AppTypography.numeric : AppTypography.body)
                .copyWith(color: s.ink),
          ),
        ),
      ],
    );
  }
}

/// What a co-signer does with the transaction once they have signed it:
/// read it back as a QR, copy the text, or hand it over as a file.
///
/// Copy alone is the one route that goes nowhere on a phone — there is no
/// second window to paste base64 into. The QR is the air-gap route the rest
/// of the app already speaks (BC-UR, animated when the payload needs more
/// than one part); the share sheet is how a phone moves a file at all.
class _SignedExportCard extends StatefulWidget {
  const _SignedExportCard({
    required this.signedPsbt,
    required this.chain,
    required this.copied,
    required this.onCopy,
    required this.message,
  });
  final String signedPsbt;
  final CosignChain chain;
  final bool copied;
  final VoidCallback onCopy;
  final String message;

  @override
  State<_SignedExportCard> createState() => _SignedExportCardState();
}

class _SignedExportCardState extends State<_SignedExportCard> {
  /// BC-UR fragments of the signed PSBT, once the engine has encoded them.
  List<String>? _urParts;
  String? _urError;
  bool _showQr = false;

  /// A PSBT goes out as `ur:crypto-psbt`, which any air-gap signer reads; a
  /// PSET has no registry type and goes out as Templar's own `ur:bytes`
  /// animation, for the coordinator's Templar across the table.
  Future<void> _toggleQr() async {
    setState(() => _showQr = !_showQr);
    if (!_showQr || _urParts != null || _urError != null) return;
    try {
      final parts = widget.chain == CosignChain.liquid
          ? await walletBridge.urPsetEncode(widget.signedPsbt)
          : await walletBridge.urPsbtEncode(widget.signedPsbt);
      if (mounted) setState(() => _urParts = parts);
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _urError = e.toString().replaceFirst('Exception: wallet-ffi: ', ''),
      );
    }
  }

  Future<void> _saveFile() async {
    final liquid = widget.chain == CosignChain.liquid;
    try {
      final outcome = await FileExport.saveOrShareText(
        context,
        suggestedName: liquid ? 'signed.pset' : 'signed.psbt',
        text: widget.signedPsbt,
        acceptedTypeGroups: [
          XTypeGroup(
            label: liquid ? 'PSET' : 'PSBT',
            extensions: [liquid ? 'pset' : 'psbt'],
          ),
        ],
        shareTitle: liquid ? 'Signed PSET' : 'Signed PSBT',
      );
      if (!mounted) return;
      reportSaved(context, outcome);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final artifact = widget.chain == CosignChain.liquid ? 'PSET' : 'PSBT';
    final saveLabel = FileExport.sharesInsteadOfSaves
        ? 'Share .${artifact.toLowerCase()}'
        : 'Save .${artifact.toLowerCase()} file';

    return FormCard(
      title: 'Signed $artifact',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBanner(message: widget.message),
          const SizedBox(height: AppSpacing.lg),
          equalOptions(phone, [
            SecondaryButton(
              label: _showQr ? 'Hide QR' : 'Show QR',
              icon: Icons.qr_code_2_outlined,
              isFullWidth: true,
              onPressed: _toggleQr,
            ),
            SecondaryButton(
              label: widget.copied ? 'Copied' : 'Copy $artifact',
              icon: widget.copied ? Icons.check : Icons.content_copy_outlined,
              isFullWidth: true,
              onPressed: widget.onCopy,
            ),
            SecondaryButton(
              label: saveLabel,
              icon: FileExport.sharesInsteadOfSaves
                  ? Icons.ios_share_outlined
                  : Icons.save_alt_outlined,
              isFullWidth: true,
              onPressed: _saveFile,
            ),
          ]),
          if (_showQr) ...[
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: _urParts != null
                  ? UrAnimatedQr(
                      parts: _urParts!,
                      size: phone ? AppLayout.qrSide(context, max: 300) : 260,
                    )
                  : _urError != null
                  ? Text(
                      _urError!,
                      style: AppTypography.caption.copyWith(color: s.danger),
                    )
                  : const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          CodeBox(value: widget.signedPsbt, maxLines: 5),
        ],
      ),
    );
  }
}

class _BroadcastResultCard extends StatelessWidget {
  const _BroadcastResultCard({required this.txid});
  final String txid;

  @override
  Widget build(BuildContext context) {
    return FormCard(
      title: 'Transaction broadcast',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InfoBanner(
            message:
                'All required signatures were present — the transaction '
                'was finalized and sent to the network.',
          ),
          const SizedBox(height: AppSpacing.lg),
          CodeBox(value: txid, label: 'Transaction ID'),
        ],
      ),
    );
  }
}
