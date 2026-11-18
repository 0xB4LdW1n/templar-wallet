// The co-signature hand-off sheets: the surface a transaction sits on while it
// is out with its co-signers.
//
// One shape, two chains. The quorum sits at the top — the state in words, a
// seal per required signature, and a row per co-signer whose seal is stamped
// once the engine sees that key's signature — and, while a key this app does
// not hold is still to sign, the button that plugs a device in and signs
// right here. Below it, the copy going out: a QR
// where the chain has one, the artifact itself, and Copy · Save · Paste in
// one row. Paste is the way a signed copy comes back: it opens a box (filled
// from the clipboard when a transaction is on it), the copy is read, and its
// signatures are FOLDED INTO the copy being handed out. Signing in turn or
// in parallel both work; a copy that brings nothing new is refused with the
// reason instead of quietly replacing what was there. Every collected
// signature is shown landing: the co-signer's seal stamps, the header line
// moves, and a note says whose signature arrived and how many are left.
// Scan and file remain as the other ways back.
//
// Lives here rather than inside the Send screen because it is also where a
// widget test can reach it — the chart following an imported signature is the
// behaviour this whole surface exists for.

import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart' show XFile, XTypeGroup;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/cosigner_label_store.dart';
import '../../services/file_export.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/cosigner_label_editor.dart';
import '../../shared/widgets/cosigner_ring.dart'
    show CosignerEntry, resolveCosigners, signerSlotsFor;
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hex_text.dart';
import '../../shared/widgets/hybrid_kit.dart' show QuietTag;
import '../../shared/widgets/seal_mark.dart';
import '../../shared/widgets/signer_donut.dart';
import '../../shared/widgets/ur_qr.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../create_wallet/models/hw_device.dart';
import '../hardware/hw_platform.dart' show usbHardwareSupported;
import '../hardware/usb_cosign.dart';
import 'models/pset_inspection.dart';
import 'models/psbt_inspection.dart';

/// Reads a picked PSBT/PSET file as the text the bridge expects. A binary
/// `.psbt`/`.pset` (magic `psbt\xff` / `pset\xff`) is base64-encoded; a text
/// file must be base64 or hex and is returned without whitespace. Android's
/// picker cannot filter by extension (no MIME type for `.psbt`), so the
/// content is what gets checked, on every platform alike.
Future<String> readPsbtLikeFile(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.length > 5 && bytes[4] == 0xff) {
    final magic = String.fromCharCodes(bytes.take(4));
    if (magic == 'psbt' || magic == 'pset') return base64Encode(bytes);
  }
  final text = utf8.decode(bytes, allowMalformed: true).trim();
  if (text.isEmpty) throw const FormatException('That file is empty.');
  final base64Like = RegExp(r'^[A-Za-z0-9+/=\s]+$');
  final hexLike = RegExp(r'^[0-9a-fA-F\s]+$');
  if (!base64Like.hasMatch(text) && !hexLike.hasMatch(text)) {
    throw const FormatException(
      'That file does not look like a PSBT/PSET (expected base64 or hex).',
    );
  }
  return text.replaceAll(RegExp(r'\s+'), '');
}

/// Snackbar after [FileExport.saveOrShareText]: a path on desktop, nothing
/// on a phone (the share sheet was the feedback), nothing when cancelled.
void reportSaved(BuildContext context, String? outcome) {
  if (outcome == null || outcome == 'shared') return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text('Saved to $outcome')));
}

/// Whether a clipboard's text could be a transaction worth reading: base64
/// or hex, no spaces, and long enough to be more than a word. Anything else
/// (a URL, a chat message) is left alone rather than reported as "not a
/// PSBT" the moment the box opens.
bool looksLikeTransactionText(String text) {
  final t = text.trim();
  if (t.length < 40) return false;
  return RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(t) ||
      RegExp(r'^[0-9a-fA-F]+$').hasMatch(t);
}

/// One transaction's quorum, as the chart draws it. Slots on the ring, plus
/// the signature count the inspection actually reported — which can exceed
/// the filled slots when a signature belongs to no named signer.
typedef HandoffQuorum = ({
  int signed,
  int total,
  int? needed,
  int collected,
  String? caption,
});

/// The label that names a block of a sheet. Two sections here — the copy
/// going out and the copy coming back — and an eyebrow names each without a
/// second headline.
class HandoffEyebrow extends StatelessWidget {
  const HandoffEyebrow(this.label, {super.key, this.trailing});
  final String label;

  /// Always the secondary ink: a status is said in words here, not in a
  /// colour.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
      ],
    );
  }
}

// ── Shared state of both sheets ───────────────────────────────────────────────

/// What the two sheets have in common: the wallet's co-signers and their
/// labels, the paste box, the USB route, and the "signature landed" note.
/// The chain-specific parts — reading, merging, signing — stay in each
/// sheet's own State.
mixin _HandoffCommon<T extends StatefulWidget> on State<T> {
  WalletBridge get bridge;

  /// 'PSBT' or 'PSET'.
  String get artifactName;

  /// The copy currently being handed out.
  String get artifact;

  /// Read a copy that came back and fold it in. Chain-specific.
  Future<void> takeReturned(String text);

  final pasteCtrl = TextEditingController();
  bool pasteOpen = false;

  /// A copy is being read — the first inspection of the copy going out, or
  /// one that came back. Every way in (paste, scan, file, USB) is held while
  /// it is true, so a returning copy can never be folded into a copy that
  /// has not been read yet: with nothing to compare against it would simply
  /// replace it, local signature and all.
  bool checking = true;
  String? importError;
  bool copied = false;

  /// The wallet's keys with their names, colours and hardware flags. Empty
  /// on a wallet with no co-signers, or before the store answers.
  List<CosignerEntry> cosigners = const [];

  /// The "signature landed" note, briefly, after a copy is taken in.
  String? collected;
  Timer? _collectedTimer;

  bool hwBusy = false;

  Future<void> loadCosigners() async {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return;
    try {
      final info = await bridge.getWalletInfo(walletId);
      if (info.cosignerKeys.length < 2) return;
      final labels = await CosignerLabelStore.instance.load(walletId);
      if (!mounted) return;
      setState(() {
        cosigners = resolveCosigners(
          cosignerKeys: info.cosignerKeys,
          labels: labels,
          localFingerprints: info.localFingerprints,
        );
      });
    } catch (_) {
      // Names are a convenience; the sheet works by fingerprint without them.
    }
  }

  /// The chart's slots for a transaction that names its signers: the
  /// wallet's labels where it has them, fingerprints otherwise. Null when
  /// the transaction names nobody (the ring then draws required-signature
  /// slots from the counts).
  List<SignerSlot>? slotsFor(
    Iterable<String> signerFingerprints,
    Iterable<String> signed,
  ) {
    if (signerFingerprints.isEmpty) return null;
    return signerSlotsFor(
      entries: cosigners,
      signerFingerprints: signerFingerprints,
      signedFingerprints: signed,
    );
  }

  /// The rename control for a signer row: a key the wallet knows, through
  /// the same label editor as the dashboard.
  VoidCallback? renameFor(SignerSlot slot) {
    final walletId = context.read<AppState>().activeWalletId;
    if (walletId == null) return null;
    CosignerEntry? entry;
    for (final e in cosigners) {
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
      await loadCosigners();
    };
  }

  /// The keys a connected device could still sign for: every key of the
  /// wallet this app does not hold and whose signature is missing. Empty
  /// hides the USB button.
  ///
  /// Deliberately not narrowed to keys labelled as hardware. A label is
  /// presentation — typed by hand, absent on an imported wallet, gone on
  /// another computer — and the only way to sign with a device must not
  /// vanish with it. A device that holds none of these keys is turned away
  /// at the connect gate, by fingerprint.
  Set<String> usbPending(Iterable<String> signed) {
    final done = signed.map((f) => f.toLowerCase()).toSet();
    return {
      for (final e in cosigners)
        if (!e.isLocal &&
            e.fingerprint.isNotEmpty &&
            !done.contains(e.fingerprint))
          e.fingerprint,
    };
  }

  /// USB is on offer at all: a desktop build with the hardware stack.
  bool get usbOffered => !AppLayout.isMobilePlatform && usbHardwareSupported;

  /// What to call a signer in the "landed" note: its label, else its
  /// fingerprint.
  String nameOf(String fingerprint) {
    for (final e in cosigners) {
      if (e.fingerprint == fingerprint.toLowerCase()) return e.name;
    }
    return fingerprint;
  }

  /// The Paste button. Opens the box — filled from the clipboard and read at
  /// once when a transaction is on it, which is the common case: a
  /// co-signer's copy just copied out of a chat. A second press closes it.
  Future<void> onPastePressed() async {
    if (pasteOpen) {
      setState(() {
        pasteOpen = false;
        importError = null;
      });
      return;
    }
    setState(() {
      pasteOpen = true;
      importError = null;
    });
    String? clip;
    try {
      clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim();
    } catch (_) {
      clip = null;
    }
    if (!mounted) return;
    if (clip != null && clip.isNotEmpty && looksLikeTransactionText(clip)) {
      pasteCtrl.text = clip;
      await takeReturned(clip);
    }
  }

  Future<void> onAddSignaturePressed() => takeReturned(pasteCtrl.text);

  Future<void> copyArtifact() async {
    await Clipboard.setData(ClipboardData(text: artifact));
    if (!mounted) return;
    setState(() => copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => copied = false);
  }

  /// A copy has been taken in: close the box, and say what arrived. On a
  /// phone a haptic tick marks it — a signature really did arrive.
  void signatureLanded(String note) {
    _collectedTimer?.cancel();
    if (!mounted) return;
    setState(() {
      pasteOpen = false;
      pasteCtrl.clear();
      importError = null;
      collected = note;
    });
    if (AppLayout.isMobilePlatform) HapticFeedback.mediumImpact();
    _collectedTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => collected = null);
    });
  }

  /// The wording of the note: whose signature, and where the quorum stands.
  String landedNote(Iterable<String> newFingerprints, int have, int? needed) {
    final names = newFingerprints.map(nameOf).toList();
    final who = names.isEmpty
        ? 'Signature added'
        : names.length == 1
        ? 'Signature from ${names.single} added'
        : 'Signatures from ${names.join(', ')} added';
    if (needed == null) return '$who · $have collected';
    final left = needed - have;
    return left <= 0
        ? '$who · $have of $needed — quorum met'
        : '$who · $have of $needed, $left more needed';
  }

  /// Connect a device and take its signature in.
  Future<void> signWithUsb({
    required Set<String> expected,
    required Future<String> Function(HwDevice device) sign,
  }) async {
    if (hwBusy) return;
    setState(() {
      hwBusy = true;
      importError = null;
    });
    try {
      final signed = await runUsbCosign(
        context,
        expectedFingerprints: expected,
        sign: sign,
      );
      if (!mounted || signed == null) return;
      await takeReturned(signed);
    } finally {
      if (mounted) setState(() => hwBusy = false);
    }
  }

  void disposeCommon() {
    _collectedTimer?.cancel();
    pasteCtrl.dispose();
  }
}

// ── The Bitcoin sheet ─────────────────────────────────────────────────────────

class PsbtHandoffSheet extends StatefulWidget {
  const PsbtHandoffSheet({
    super.key,
    required this.unsignedPsbt,
    required this.onBroadcast,
    this.bridge,
    this.title = 'Air-gap signing',
    this.exportEyebrow = 'Export the transaction',
    this.intro =
        'Scan this QR with your signer (Jade: QR mode) — it carries '
        'the unsigned transaction. Copy or save the file instead if your '
        'signer takes one.',
    this.returnEyebrow = 'Bring it back',
    this.returnLabel =
        'Paste the signed transaction with the button above, '
        'or scan or load it here. Nothing reaches the network before you '
        'have reviewed what it pays.',
    this.progressNote,
    this.quorumHave,
    this.quorumNeeded,
  });

  final String unsignedPsbt;
  final void Function(String signedPsbt) onBroadcast;

  /// Test seam. Null in the app, where the global engine is used.
  final WalletBridge? bridge;

  final String title;
  final String exportEyebrow;
  final String intro;
  final String returnEyebrow;
  final String returnLabel;

  /// Extra context above the export section (multisig: what is still missing).
  final String? progressNote;

  /// The quorum the engine reported when it handed this PSBT back, drawn
  /// until the first inspection lands and refines it. Null on a wallet with
  /// no quorum — a singlesig air-gap send — where no chart is drawn at all.
  final int? quorumHave;
  final int? quorumNeeded;

  @override
  State<PsbtHandoffSheet> createState() => _PsbtHandoffSheetState();
}

class _PsbtHandoffSheetState extends State<PsbtHandoffSheet>
    with _HandoffCommon<PsbtHandoffSheet> {
  @override
  late final WalletBridge bridge = widget.bridge ?? walletBridge;

  @override
  String get artifactName => 'PSBT';

  /// The copy currently being handed out. Starts as the PSBT this wallet
  /// signed and GROWS with every returning copy: their signatures are folded
  /// in, so a round-robin (A → B → C) and two co-signers signing the same
  /// original in parallel both end in one complete copy.
  late String _artifact = widget.unsignedPsbt;

  @override
  String get artifact => _artifact;

  List<String>? _urParts;
  String? _urError;

  /// Inspection of [_artifact]. Null while it is in flight, and on a chain or
  /// build where the call fails — the chart then falls back to the counts the
  /// send returned, and never invents any.
  PsbtInspection? _inspection;

  @override
  void initState() {
    super.initState();
    unawaited(loadCosigners());
    unawaited(_loadQr(_artifact));
    unawaited(_inspectArtifact(_artifact));
  }

  @override
  void dispose() {
    disposeCommon();
    super.dispose();
  }

  Future<void> _loadQr(String psbt) async {
    setState(() {
      _urParts = null;
      _urError = null;
    });
    try {
      final parts = await bridge.urPsbtEncode(psbt);
      // A newer copy arrived while this one was encoding — drop the stale QR.
      if (!mounted || psbt != _artifact) return;
      setState(() => _urParts = parts);
    } catch (e) {
      if (!mounted || psbt != _artifact) return;
      setState(
        () =>
            _urError = e.toString().replaceFirst('Exception: wallet-ffi: ', ''),
      );
    }
  }

  /// The first look at the copy going out. The sheet opens in `checking`
  /// and leaves it here, whether or not the engine could read the copy: a
  /// failed inspection is not fatal (the chart falls back to the counts the
  /// send reported), but the ways back in stay shut until it has answered.
  Future<void> _inspectArtifact(String psbt) async {
    PsbtInspection? i;
    try {
      i = await bridge.inspectPsbt(psbt);
    } catch (_) {
      i = null;
    }
    if (!mounted || psbt != _artifact) return;
    setState(() {
      _inspection = i;
      checking = false;
    });
  }

  Future<void> _saveFile() async {
    try {
      final outcome = await FileExport.saveOrShareText(
        context,
        suggestedName: 'transaction.psbt',
        text: _artifact,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PSBT', extensions: ['psbt']),
        ],
        shareTitle: 'Partially signed PSBT',
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

  Future<void> _scanSigned() async {
    final outcome = await showUrScannerDialog(context, expectPsbt: true);
    if (outcome == null || !mounted) return;
    final signed = outcome.psbtBase64;
    if (signed == null || signed.isEmpty) {
      setState(() => importError = 'The scanned QR did not contain a PSBT.');
      return;
    }
    await _takeReturned(signed, advanceWhenComplete: true);
  }

  /// Load a signed PSBT from disk — the return path that works on every
  /// desktop. Air-gap signing used to offer Save-to-file on the way out but
  /// only camera or paste on the way back, which left Windows and Linux users
  /// hand-copying base64 out of a text editor.
  Future<void> _loadSignedFile() async {
    try {
      final file = await FileExport.pickFile(
        label: 'PSBT',
        extensions: const ['psbt', 'txt'],
      );
      if (file == null || !mounted) return;
      final text = await readPsbtLikeFile(file);
      if (!mounted) return;
      await _takeReturned(text, advanceWhenComplete: true);
    } on FormatException catch (e) {
      if (mounted) setState(() => importError = e.message);
    } catch (e) {
      if (mounted) setState(() => importError = 'Could not read the file: $e');
    }
  }

  @override
  Future<void> takeReturned(String text) =>
      _takeReturned(text, advanceWhenComplete: false);

  static Set<String> _signedSet(PsbtInspection? i) => {
    if (i != null)
      for (final s in i.signers)
        if (s.hasSigned) s.fingerprint.toLowerCase(),
  };

  /// A copy came back. Read it, fold its signatures into the copy being
  /// handed out, move the chart, and say what arrived.
  ///
  /// [advanceWhenComplete] is for the scan and file paths: a returning copy
  /// that completes the quorum goes straight to the broadcast review, exactly
  /// as it did before this screen had a chart. A paste never advances on its
  /// own — the note says the quorum is met and the button is right there.
  Future<void> _takeReturned(
    String text, {
    required bool advanceWhenComplete,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      checking = true;
      importError = null;
    });
    String clean(Object e) =>
        e.toString().replaceFirst('Exception: wallet-ffi: ', '');

    PsbtInspection returned;
    try {
      returned = await bridge.inspectPsbt(trimmed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        checking = false;
        importError = clean(e);
      });
      return;
    }
    if (!mounted) return;

    // What does this copy bring that the one going out lacks? Nothing — the
    // original pasted back, or a co-signer's copy read twice — is refused
    // with the reason rather than adopted as if it were progress. A copy a
    // third-party signer FINALIZED brings the final witnesses: its partial
    // signatures were stripped when they were folded into the witness, so
    // it can read as zero signatures and still be the finished transaction.
    final current = _inspection;
    final before = _signedSet(current);
    final newSigs = returned.signers.isEmpty
        ? const <String>{}
        : _signedSet(returned).difference(before);
    final unnamedGain =
        returned.signers.isEmpty &&
        current != null &&
        returned.sigsPresent > current.sigsPresent;
    final finalizedGain =
        returned.finalized && current != null && !current.finalized;
    if (current != null && newSigs.isEmpty && !unnamedGain && !finalizedGain) {
      setState(() {
        checking = false;
        importError = trimmed == _artifact
            ? 'That is the copy you are handing out — it carries nothing '
                  'new. Give it to a co-signer and bring back the copy they '
                  'signed.'
            : 'No new signature in that copy: it has '
                  '${returned.sigsPresent} of ${returned.sigsRequired ?? '?'}, '
                  'the same as the one going out. Bring back a copy a '
                  'co-signer has signed.';
      });
      return;
    }

    // Fold it in. Two copies of one transaction combine whatever order they
    // were signed in; a copy of some other transaction is refused with the
    // reason. A finalized copy is combined too: the copy going out keeps
    // the previous-output data the review needs, and the final witnesses
    // ride along.
    var adopted = trimmed;
    var merged = returned;
    if (current != null && trimmed != _artifact) {
      try {
        adopted = await bridge.combinePsbts([_artifact, trimmed]);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          checking = false;
          importError = clean(e);
        });
        return;
      }
      if (!mounted) return;
      if (adopted != trimmed) {
        try {
          merged = await bridge.inspectPsbt(adopted);
        } catch (_) {
          adopted = trimmed;
          merged = returned;
        }
        if (!mounted) return;
      }
    }

    setState(() {
      checking = false;
      _artifact = adopted;
      _inspection = merged;
    });
    signatureLanded(
      finalizedGain && newSigs.isEmpty
          ? 'Finalized copy received · ready to broadcast'
          : landedNote(
              newSigs.isEmpty ? const <String>[] : newSigs,
              merged.sigsPresent,
              merged.sigsRequired,
            ),
    );
    // The copy going out is now this one: the QR has to say so too.
    unawaited(_loadQr(adopted));
    if (advanceWhenComplete && _complete) {
      await _reviewThenBroadcast(adopted);
    }
  }

  /// The copy in hand can go to the network: it is finalized, it meets a
  /// quorum the engine stated, or — on a transaction with no quorum to
  /// chart, a singlesig air-gap send — it carries a signature at all. Never
  /// true while a copy is being read.
  bool get _complete {
    final i = _inspection;
    if (checking || i == null) return false;
    if (i.finalized) return true;
    final needed = _quorum?.needed;
    return needed == null ? i.carriesSignature : i.sigsPresent >= needed;
  }

  /// Last defense before hitting the network: decode the signed PSBT, show
  /// what it actually pays, and only then hand it to the broadcast callback.
  Future<void> _reviewThenBroadcast(String signedPsbt) async {
    PsbtInspection inspection;
    try {
      inspection = await bridge.inspectPsbt(signedPsbt);
    } catch (e) {
      if (mounted) {
        setState(
          () => importError = e.toString().replaceFirst(
            'Exception: wallet-ffi: ',
            '',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (_) => SignedPsbtReviewDialog(inspection: inspection),
    );
    if (confirmed == true) widget.onBroadcast(signedPsbt);
  }

  /// What the chart draws, or null when this transaction has no quorum to
  /// show — a singlesig air-gap PSBT, where a one-slot ring says nothing.
  HandoffQuorum? get _quorum {
    final i = _inspection;
    if (i != null && i.signers.isNotEmpty) {
      // One named key and no threshold above one: the engine writes the
      // wallet's own key into every PSBT it builds, so a singlesig send
      // names exactly one signer (`sigs_required` 1, or null on an older
      // engine that only read a threshold off a witness script).
      if (i.signers.length <= 1 && (i.sigsRequired ?? 1) <= 1) return null;
      return (
        signed: i.signers.where((x) => x.hasSigned).length,
        total: i.signers.length,
        needed: i.sigsRequired,
        collected: i.sigsPresent,
        caption: null,
      );
    }
    // No named signers: draw the ring in required-signature slots instead,
    // from whichever count the engine gave us.
    final needed = i?.sigsRequired ?? widget.quorumNeeded;
    if (needed == null || needed <= 1) return null;
    final have = i?.sigsPresent ?? widget.quorumHave ?? 0;
    return (
      signed: have.clamp(0, needed),
      total: needed,
      needed: needed,
      collected: have,
      caption:
          '$have of $needed required signature'
          '${needed == 1 ? '' : 's'} collected',
    );
  }

  /// Signatures still missing, by the engine's counts; null when it stated
  /// no threshold.
  int? _left(HandoffQuorum q) {
    final needed = q.needed;
    if (needed == null) return null;
    return needed - q.collected;
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final q = _quorum;
    final i = _inspection;
    final left = q == null ? null : _left(q);
    // A finalized copy has met its quorum by definition, whatever the
    // partial-signature count says.
    final met =
        q != null && ((i?.finalized ?? false) || (left != null && left <= 0));
    final remaining = q == null ? null : stateLine(met: met, left: left);
    final signedFps = _signedSet(i);
    final slots = i == null
        ? null
        : slotsFor(i.signers.map((s) => s.fingerprint), signedFps);
    final hwPending = usbPending(signedFps);

    final body = _HandoffBody(
      artifactName: 'PSBT',
      quorum: q,
      remaining: remaining,
      met: met,
      slots: slots,
      onRename: renameFor,
      progressNote: widget.progressNote,
      exportEyebrow: widget.exportEyebrow,
      intro: widget.intro,
      returnEyebrow: widget.returnEyebrow,
      returnLabel: widget.returnLabel,
      urParts: _urParts,
      urError: _urError,
      artifact: _artifact,
      copied: copied,
      checking: checking,
      importError: importError,
      collected: collected,
      pasteOpen: pasteOpen,
      pasteCtrl: pasteCtrl,
      usbOffered: usbOffered && !met && hwPending.isNotEmpty,
      hwBusy: hwBusy,
      onCopy: copyArtifact,
      onSave: _saveFile,
      onPaste: onPastePressed,
      onAddSignature: onAddSignaturePressed,
      onScan: cameraScanSupported ? _scanSigned : null,
      onLoadFile: _loadSignedFile,
      onSignUsb: () => signWithUsb(
        expected: hwPending,
        sign: (device) => bridge.signPsbtHw(device.fingerprint, _artifact),
      ),
    );

    // Broadcast is offered once the copy in hand meets the quorum — or, on a
    // transaction with no quorum to chart (a singlesig air-gap send), or
    // whose threshold the engine could not state, once it carries a
    // signature at all; the review dialog is then the last check, and the
    // engine's finalize refuses an under-signed copy with the reason. The
    // button must never be the thing that strands a signed transaction.
    final canBroadcast = !checking && (met || _complete);
    return AppDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: phone ? double.infinity : 560,
        // The sheet scrolls on its own; a nested scroll view would swallow
        // the drag.
        child: phone ? body : SingleChildScrollView(child: body),
      ),
      // Quiet action first, the primary last (a phone's sheet stacks them
      // reversed, the primary on top).
      actions: [
        GhostButton(
          label: 'Cancel',
          isFullWidth: phone,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(
          label: 'Review and broadcast',
          isFullWidth: phone,
          onPressed: canBroadcast
              ? () => _reviewThenBroadcast(_artifact)
              : null,
        ),
      ],
    );
  }
}

/// Two or three options of equal weight: one row of equal cells on a
/// desktop, stacked full width on a phone. The buttons should be built with
/// `isFullWidth: true` so each fills its cell.
Widget equalOptions(bool phone, List<Widget> buttons) {
  if (phone) return stackOrRow(true, buttons);
  return Row(
    children: [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(width: AppSpacing.sm),
        Expanded(child: buttons[i]),
      ],
    ],
  );
}

/// The state line of a hand-off sheet, in words: fully signed, or how many
/// signatures are still missing. [left] is the engine's count; null when it
/// stated no threshold.
String stateLine({required bool met, required int? left}) {
  if (met) return 'Fully signed, ready to broadcast';
  if (left == null) return 'Partially signed';
  return 'Needs $left more signature${left == 1 ? '' : 's'}';
}

/// A row of buttons on a desktop — wrapping onto a second line when three
/// of them will not fit a 560 px sheet — or stacked full width on a phone.
Widget stackOrRow(bool phone, List<Widget> buttons) {
  if (!phone) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: buttons,
    );
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < buttons.length; i++) ...[
        if (i > 0) const SizedBox(height: AppSpacing.sm),
        buttons[i],
      ],
    ],
  );
}

// ── The Liquid sheet ──────────────────────────────────────────────────────────

/// Export/import surface for a Liquid multisig transaction that still needs
/// co-signatures.
///
/// The same shape as the Bitcoin sheet: the quorum charted at the top, the
/// copy going out with Copy · Save · Paste, scan and file as the other ways
/// back. The QR is Templar's own `ur:bytes` animation of the PSET — the
/// registry has no PSET type and no hardware signer reads one over QR (Jade's
/// QR mode is Bitcoin-only), so the camera on the other side is another
/// Templar, a co-signer's phone across the table. A Jade over USB signs a
/// PSET directly, so the USB button here is Jade's.
class PsetHandoffSheet extends StatefulWidget {
  const PsetHandoffSheet({
    super.key,
    required this.pset,
    required this.have,
    required this.needed,
    required this.onBroadcast,
    this.bridge,
  });

  final String pset;
  final int have;
  final int needed;
  final void Function(String signedPset) onBroadcast;

  /// Test seam. Null in the app, where the global engine is used.
  final WalletBridge? bridge;

  @override
  State<PsetHandoffSheet> createState() => _PsetHandoffSheetState();
}

class _PsetHandoffSheetState extends State<PsetHandoffSheet>
    with _HandoffCommon<PsetHandoffSheet> {
  @override
  late final WalletBridge bridge = widget.bridge ?? walletBridge;

  @override
  String get artifactName => 'PSET';

  /// The copy currently being handed out — grown by every returning copy.
  late String _artifact = widget.pset;

  @override
  String get artifact => _artifact;

  /// `ur:bytes` frames of [_artifact], once the engine has encoded them.
  List<String>? _urParts;
  String? _urError;

  /// Inspection of [_artifact]; null until the first one lands, and on a
  /// build where the call fails — the chart then falls back to the counts the
  /// send reported.
  PsetInspection? _inspection;

  @override
  void initState() {
    super.initState();
    unawaited(loadCosigners());
    unawaited(_loadQr(_artifact));
    unawaited(_inspectArtifact(_artifact));
  }

  @override
  void dispose() {
    disposeCommon();
    super.dispose();
  }

  String? get _walletId => context.read<AppState>().activeWalletId;

  Future<void> _loadQr(String pset) async {
    setState(() {
      _urParts = null;
      _urError = null;
    });
    try {
      final parts = await bridge.urPsetEncode(pset);
      // A newer copy arrived while this one was encoding — drop the stale QR.
      if (!mounted || pset != _artifact) return;
      setState(() => _urParts = parts);
    } catch (e) {
      if (!mounted || pset != _artifact) return;
      setState(
        () =>
            _urError = e.toString().replaceFirst('Exception: wallet-ffi: ', ''),
      );
    }
  }

  /// The first look at the copy going out; the sheet opens in `checking`
  /// and leaves it here, read or not — see the Bitcoin sheet.
  Future<void> _inspectArtifact(String pset) async {
    final walletId = _walletId;
    PsetInspection? i;
    if (walletId != null) {
      try {
        i = await bridge.inspectPset(walletId, pset);
      } catch (_) {
        i = null;
      }
    }
    if (!mounted || pset != _artifact) return;
    setState(() {
      _inspection = i;
      checking = false;
    });
  }

  /// A signed copy read off another Templar's screen.
  Future<void> _scanSigned() async {
    final outcome = await showUrScannerDialog(
      context,
      expectPsbt: true,
      title: 'Scan signed PSET',
    );
    if (outcome == null || !mounted) return;
    final signed = outcome.transactionBase64;
    if (signed == null || signed.isEmpty) {
      setState(() => importError = 'The scanned QR did not contain a PSET.');
      return;
    }
    await takeReturned(signed);
  }

  Future<void> _saveFile() async {
    try {
      final outcome = await FileExport.saveOrShareText(
        context,
        suggestedName: 'transaction.pset',
        text: _artifact,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'PSET', extensions: ['pset']),
        ],
        shareTitle: 'Partially signed PSET',
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

  Future<void> _loadSignedFile() async {
    try {
      final file = await FileExport.pickFile(
        label: 'PSET',
        extensions: const ['pset', 'txt'],
      );
      if (file == null) return;
      final text = await readPsbtLikeFile(file);
      if (!mounted) return;
      await takeReturned(text);
    } on FormatException catch (e) {
      if (mounted) setState(() => importError = e.message);
    } catch (e) {
      if (mounted) setState(() => importError = 'Could not read file: $e');
    }
  }

  static Set<String> _signedSet(PsetInspection? i) => {
    if (i != null)
      for (final f in i.signersPresent) f.toLowerCase(),
  };

  /// A copy came back: read it, fold it into the copy being handed out,
  /// move the chart, and say what arrived. Nothing is broadcast from here —
  /// that is the sheet's own action, and it re-checks the quorum first.
  @override
  Future<void> takeReturned(String text) async {
    final walletId = _walletId;
    if (walletId == null) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      checking = true;
      importError = null;
    });
    String clean(Object e) =>
        e.toString().replaceFirst('Exception: wallet-ffi: ', '');

    PsetInspection returned;
    try {
      returned = await bridge.inspectPset(walletId, trimmed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        checking = false;
        importError = clean(e);
      });
      return;
    }
    if (!mounted) return;

    final current = _inspection;
    final before = _signedSet(current);
    final named =
        returned.signersPresent.isNotEmpty ||
        returned.signersMissing.isNotEmpty;
    final newSigs = named
        ? _signedSet(returned).difference(before)
        : <String>{};
    final unnamedGain =
        !named && current != null && returned.sigsHave > current.sigsHave;
    if (current != null && newSigs.isEmpty && !unnamedGain) {
      setState(() {
        checking = false;
        importError = trimmed == _artifact
            ? 'That is the copy you are handing out — it carries nothing '
                  'new. Give it to a co-signer and bring back the copy they '
                  'signed.'
            : 'No new signature in that copy: it has ${returned.sigsHave} '
                  'of ${returned.sigsNeeded}, the same as the one going out. '
                  'Bring back a copy a co-signer has signed.';
      });
      return;
    }

    var adopted = trimmed;
    var merged = returned;
    if (current != null && trimmed != _artifact) {
      try {
        adopted = await bridge.combinePsets(walletId, [_artifact, trimmed]);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          checking = false;
          importError = clean(e);
        });
        return;
      }
      if (!mounted) return;
      if (adopted != trimmed) {
        try {
          merged = await bridge.inspectPset(walletId, adopted);
        } catch (_) {
          adopted = trimmed;
          merged = returned;
        }
        if (!mounted) return;
      }
    }

    setState(() {
      checking = false;
      _artifact = adopted;
      _inspection = merged;
    });
    signatureLanded(
      landedNote(
        newSigs.isEmpty ? const <String>[] : newSigs,
        merged.sigsHave,
        merged.sigsNeeded,
      ),
    );
    // The copy going out is now this one: the QR has to say so too.
    unawaited(_loadQr(adopted));
  }

  /// Check the PSET in hand before broadcasting: it must actually carry the
  /// full quorum. Broadcasting an under-signed PSET fails at finalization
  /// with a message about script satisfaction that explains nothing.
  Future<void> _reviewThenBroadcast() async {
    final walletId = _walletId;
    if (walletId == null) return;
    final signed = _artifact;
    setState(() {
      checking = true;
      importError = null;
    });
    try {
      final info = await bridge.inspectPset(walletId, signed);
      if (!mounted) return;
      setState(() {
        checking = false;
        _inspection = info;
      });
      if (!info.canFinalize) {
        setState(
          () => importError =
              'Still ${info.sigsRemaining} signature(s) short — this copy has '
              '${info.sigsHave} of ${info.sigsNeeded}. Send it to the remaining '
              'co-signer(s) before broadcasting.',
        );
        return;
      }
      widget.onBroadcast(signed);
    } catch (e) {
      if (mounted) {
        setState(() {
          checking = false;
          importError = e.toString().replaceFirst(
            'Exception: wallet-ffi: ',
            '',
          );
        });
      }
    }
  }

  /// What the chart draws. Named signers when the inspection knows them,
  /// required-signature slots otherwise — and either way only counts the
  /// engine gave us.
  HandoffQuorum get _quorum {
    final i = _inspection;
    if (i != null &&
        (i.signersPresent.isNotEmpty || i.signersMissing.isNotEmpty)) {
      return (
        signed: i.signersPresent.length,
        total: i.signersPresent.length + i.signersMissing.length,
        needed: i.sigsNeeded,
        collected: i.sigsHave,
        caption: null,
      );
    }
    final needed = i?.sigsNeeded ?? widget.needed;
    final have = i?.sigsHave ?? widget.have;
    return (
      signed: have.clamp(0, needed),
      total: needed,
      needed: needed,
      collected: have,
      caption:
          '$have of $needed required signature'
          '${needed == 1 ? '' : 's'} collected',
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final q = _quorum;
    final left = (q.needed ?? q.total) - q.collected;
    final met = left <= 0;
    final remaining = stateLine(met: met, left: left);
    final i = _inspection;
    final signedFps = _signedSet(i);
    final slots = i == null
        ? null
        : slotsFor([...i.signersPresent, ...i.signersMissing], signedFps);
    final hwPending = usbPending(signedFps);

    final body = _HandoffBody(
      artifactName: 'PSET',
      quorum: q,
      remaining: remaining,
      met: met,
      slots: slots,
      onRename: renameFor,
      progressNote:
          'Partially signed — ${widget.have} of ${widget.needed} '
          'signatures collected. Nothing was broadcast.',
      exportEyebrow: 'Hand it to your co-signers',
      intro:
          'Send them this PSET — let them scan the QR from their Templar, '
          'or pass it by clipboard or file. Each one loads it under Send › '
          'Cosign a transaction, signs, and returns it.',
      returnEyebrow: 'Collect the signatures',
      returnLabel:
          'Paste each signed copy with the button above, or scan or '
          'load it here. Its signatures join the copy you hand out, and the '
          'chart follows.',
      urParts: _urParts,
      urError: _urError,
      artifact: _artifact,
      copied: copied,
      checking: checking,
      importError: importError,
      collected: collected,
      pasteOpen: pasteOpen,
      pasteCtrl: pasteCtrl,
      usbOffered: usbOffered && !met && hwPending.isNotEmpty,
      hwBusy: hwBusy,
      onCopy: copyArtifact,
      onSave: _saveFile,
      onPaste: onPastePressed,
      onAddSignature: onAddSignaturePressed,
      onScan: cameraScanSupported ? _scanSigned : null,
      onLoadFile: _loadSignedFile,
      // A Jade is the only device that signs a PSET; the engine registers
      // the multisig on it and asks for the signature.
      onSignUsb: () => signWithUsb(
        expected: hwPending,
        sign: (_) => bridge.signPsetHw(_walletId ?? '', _artifact),
      ),
    );
    final canBroadcast = !checking && met;
    return AppDialog(
      title: const Text('Co-signatures needed'),
      content: SizedBox(
        width: phone ? double.infinity : 560,
        child: phone ? body : SingleChildScrollView(child: body),
      ),
      // One grammar with the air-gap sheet next door.
      actions: [
        GhostButton(
          label: 'Cancel',
          isFullWidth: phone,
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(
          label: checking ? 'Checking…' : 'Review and broadcast',
          isFullWidth: phone,
          onPressed: canBroadcast ? _reviewThenBroadcast : null,
        ),
      ],
    );
  }
}

// ── The body both sheets draw ─────────────────────────────────────────────────

class _HandoffBody extends StatelessWidget {
  const _HandoffBody({
    required this.artifactName,
    required this.quorum,
    required this.remaining,
    required this.met,
    required this.slots,
    required this.progressNote,
    required this.exportEyebrow,
    required this.intro,
    required this.returnEyebrow,
    required this.returnLabel,
    required this.urParts,
    required this.urError,
    required this.artifact,
    required this.copied,
    required this.checking,
    required this.importError,
    required this.collected,
    required this.pasteOpen,
    required this.pasteCtrl,
    required this.usbOffered,
    required this.hwBusy,
    required this.onCopy,
    required this.onSave,
    required this.onPaste,
    required this.onAddSignature,
    required this.onScan,
    required this.onLoadFile,
    required this.onSignUsb,
    this.onRename,
  });

  final String artifactName;
  final HandoffQuorum? quorum;
  final String? remaining;
  final bool met;
  final List<SignerSlot>? slots;
  final String? progressNote;
  final String exportEyebrow;
  final String intro;
  final String returnEyebrow;
  final String returnLabel;
  final List<String>? urParts;
  final String? urError;
  final String artifact;
  final bool copied;
  final bool checking;
  final String? importError;
  final String? collected;
  final bool pasteOpen;
  final TextEditingController pasteCtrl;
  final bool usbOffered;
  final bool hwBusy;
  final VoidCallback onCopy;
  final VoidCallback onSave;
  final VoidCallback onPaste;
  final VoidCallback onAddSignature;
  final VoidCallback? onScan;
  final VoidCallback onLoadFile;
  final VoidCallback onSignUsb;
  final VoidCallback? Function(SignerSlot slot)? onRename;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final lower = artifactName.toLowerCase();
    final saveLabel = FileExport.sharesInsteadOfSaves
        ? 'Share .$lower'
        : 'Save .$lower file';
    final q = quorum;
    // The error belongs next to whichever control produced it: inside the
    // paste box while it is open, under the other routes otherwise.
    final errorBelowRoutes = importError != null && !pasteOpen;
    // A size that animates open and shut — except under reduced motion,
    // where AnimatedSize with a zero duration re-dirties itself mid-layout
    // and the plain child is the right widget anyway.
    Widget sized(Duration d, Widget child) => d == Duration.zero
        ? child
        : AnimatedSize(
            duration: d,
            curve: AppMotion.settle,
            alignment: Alignment.topCenter,
            child: child,
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (progressNote != null) ...[
          WarningBanner(
            title: 'More signatures required',
            message: progressNote!,
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        // ── Who has signed ──────────────────────────────────────────────
        if (q != null) ...[
          SignatureHeader(
            state: remaining ?? '',
            signed: q.collected,
            required: q.needed,
          ),
          if (slots != null && slots!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            SignerList(slots: slots!, onRename: onRename),
          ],
          // The note a collected signature leaves behind, for a few seconds.
          sized(
            AppMotion.of(context, AppMotion.standard),
            collected == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: _CollectedNote(
                      key: ValueKey(collected),
                      message: collected!,
                    ),
                  ),
          ),
          if (usbOffered) ...[
            const SizedBox(height: AppSpacing.md),
            // A key still to sign may live on a USB device: connect it and
            // sign right here, and its seal stamps like any other. Again for
            // the next device, until the quorum is met.
            SecondaryButton(
              label: 'Sign with USB hardware wallet',
              icon: Icons.usb_outlined,
              isFullWidth: true,
              isLoading: hwBusy,
              onPressed: hwBusy || checking ? null : onSignUsb,
            ),
          ],
          Divider(height: AppSpacing.xxl, thickness: 1, color: s.edge),
        ],
        // ── The copy going out — and the way back in ────────────────────
        HandoffEyebrow(exportEyebrow),
        const SizedBox(height: AppSpacing.sm),
        Text(intro, style: AppTypography.body.copyWith(color: s.inkSecondary)),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: urParts != null
              ? UrAnimatedQr(
                  parts: urParts!,
                  size: phone ? AppLayout.qrSide(context, max: 300) : 240,
                )
              : urError != null
              ? Text(
                  urError!,
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
        const SizedBox(height: AppSpacing.lg),
        CodeBox(value: artifact, maxLines: 4),
        const SizedBox(height: AppSpacing.md),
        // Three equal, quiet options: two ways to hand the copy out and,
        // beside them, the way a signed copy comes back. The sheet's one
        // filled control is the broadcast in its footer.
        equalOptions(phone, [
          SecondaryButton(
            label: copied ? 'Copied' : 'Copy $artifactName',
            icon: copied ? Icons.check : Icons.content_copy_outlined,
            isFullWidth: true,
            onPressed: onCopy,
          ),
          SecondaryButton(
            label: saveLabel,
            icon: FileExport.sharesInsteadOfSaves
                ? Icons.ios_share_outlined
                : Icons.save_alt_outlined,
            isFullWidth: true,
            onPressed: onSave,
          ),
          SecondaryButton(
            label: pasteOpen ? 'Close paste box' : 'Paste signed copy',
            icon: pasteOpen ? Icons.expand_less : Icons.content_paste_outlined,
            isFullWidth: true,
            onPressed: checking ? null : onPaste,
          ),
        ]),
        sized(
          AppMotion.of(context, AppMotion.quick),
          pasteOpen
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: _PasteBox(
                    artifactName: artifactName,
                    controller: pasteCtrl,
                    checking: checking,
                    error: importError,
                    onAdd: onAddSignature,
                    phone: phone,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: AppSpacing.xxl, thickness: 1, color: s.edge),
        // ── The other ways back ─────────────────────────────────────────
        HandoffEyebrow(returnEyebrow),
        const SizedBox(height: AppSpacing.sm),
        Text(
          returnLabel,
          style: AppTypography.body.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        // Only offer the camera where it exists: mobile_scanner has no
        // Windows/Linux implementation, so a Scan button there is a button
        // whose only outcome is an apology dialog. File import takes the
        // lead role on those platforms instead.
        equalOptions(phone, [
          if (onScan != null)
            SecondaryButton(
              label: 'Scan signed QR',
              icon: Icons.qr_code_scanner_outlined,
              isFullWidth: true,
              onPressed: checking ? null : onScan,
            ),
          SecondaryButton(
            label: onScan != null
                ? 'Load .$lower file'
                : 'Load signed .$lower file',
            icon: Icons.folder_open_outlined,
            isFullWidth: true,
            onPressed: checking ? null : onLoadFile,
          ),
        ]),
        if (checking && !pasteOpen) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Reading the transaction…',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
        if (errorBelowRoutes) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            importError!,
            style: AppTypography.caption.copyWith(color: s.danger),
          ),
        ],
      ],
    );
  }
}

/// The paste box: a field, one button that reads what is in it, and the
/// verdict right beneath. Opened by the Paste button and closed by a copy
/// that was taken in.
class _PasteBox extends StatelessWidget {
  const _PasteBox({
    required this.artifactName,
    required this.controller,
    required this.checking,
    required this.error,
    required this.onAdd,
    required this.phone,
  });

  final String artifactName;
  final TextEditingController controller;
  final bool checking;
  final String? error;
  final VoidCallback onAdd;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: s.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Paste the signed $artifactName a co-signer sent back. Its '
            'signatures join the copy above.',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: controller,
            maxLines: 3,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            onSubmitted: (_) => onAdd(),
            decoration: InputDecoration(hintText: 'Signed $artifactName'),
            style: AppTypography.mono.copyWith(color: s.ink),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: checking
                    ? Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Reading the transaction…',
                            style: AppTypography.caption.copyWith(
                              color: s.inkSecondary,
                            ),
                          ),
                        ],
                      )
                    : error != null
                    ? Text(
                        error!,
                        style: AppTypography.caption.copyWith(color: s.danger),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Secondary: the sheet's one filled control is the broadcast.
              SecondaryButton(
                label: 'Add signature',
                onPressed: checking ? null : onAdd,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Signature from Anna's phone added · 2 of 3, 1 more needed" — said
/// beside the list that just moved, for a few seconds. A seal leads it: it
/// is a signature that arrived, and nothing else gets this mark.
class _CollectedNote extends StatelessWidget {
  const _CollectedNote({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final note = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          const SealMark(stamped: true, size: AppSpacing.iconSmall),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
    // A fade in, nothing more: no scale, no pop.
    final d = AppMotion.of(context, AppMotion.emphasized);
    if (d == Duration.zero) return note;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: d,
      curve: AppMotion.settle,
      builder: (_, t, child) => Opacity(opacity: t.clamp(0, 1), child: child),
      child: note,
    );
  }
}

/// Confirmation shown between scanning/pasting a signed PSBT and broadcasting
/// it: what it pays, what it costs, and how many signatures it carries.
class SignedPsbtReviewDialog extends StatelessWidget {
  const SignedPsbtReviewDialog({super.key, required this.inspection});
  final PsbtInspection inspection;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final i = inspection;
    final sigs = i.finalized
        ? 'finalized'
        : i.sigsRequired != null
        ? '${i.sigsPresent} of ${i.sigsRequired}'
        : '${i.sigsPresent}';
    final phone = AppLayout.isPhone(context);
    // A copy whose inputs cannot be priced has no fee to review. This
    // dialog exists to show what the transaction pays before it leaves; a
    // fee nobody can state fails that test, so the button is held.
    final hidesSpend = !i.utxoCheckOk;
    final unsigned = !i.carriesSignature;
    final amountStyle = AppTypography.numeric.copyWith(color: s.ink);
    // The wallet's own outputs are its change: named, so the recipient is
    // the one line left to check.
    Widget ownTag(PsbtOutput o) => i.ownershipKnown && o.isMine == true
        ? const Padding(
            padding: EdgeInsets.only(right: AppSpacing.sm),
            child: QuietTag(label: 'Change'),
          )
        : const SizedBox.shrink();
    Widget kv(String label, String value, {Color? ink}) => Row(
      children: [
        Text(label, style: AppTypography.label.copyWith(color: s.inkSecondary)),
        const Spacer(),
        Text(value, style: AppTypography.numeric.copyWith(color: ink ?? s.ink)),
      ],
    );
    return AppDialog(
      title: const Text('Review signed transaction'),
      content: SizedBox(
        width: phone ? double.infinity : 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Outputs',
              style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...i.outputs.map(
              (o) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: phone
                    // Phone: the whole address, wrapped, with the amount
                    // under it — an ellipsis would hide the checksum tail
                    // this review exists to check.
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HexText(
                            o.address,
                            style: AppTypography.mono.copyWith(color: s.ink),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              ownTag(o),
                              Text(o.displayAmount, style: amountStyle),
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Text(
                              o.address,
                              style: AppTypography.mono.copyWith(color: s.ink),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          ownTag(o),
                          Text(o.displayAmount, style: amountStyle),
                        ],
                      ),
              ),
            ),
            Divider(height: AppSpacing.xl, thickness: 1, color: s.edge),
            kv('Fee', i.feeLabel, ink: i.feeSats == null ? s.danger : null),
            const SizedBox(height: AppSpacing.sm),
            kv('Signatures', sigs),
            if (hidesSpend) ...[
              const SizedBox(height: AppSpacing.md),
              DangerBanner(
                message:
                    'This transaction hides what it spends — do not '
                    'broadcast. Its previous outputs are '
                    '${i.utxoCheck == PsbtUtxoStatus.conflicting ? 'inconsistent' : 'missing'}, '
                    'so the fee cannot be checked.',
              ),
            ],
            if (unsigned) ...[
              const SizedBox(height: AppSpacing.md),
              const DangerBanner(
                message:
                    'No signatures detected — this looks like the unsigned '
                    'PSBT. Broadcasting it will fail.',
              ),
            ],
          ],
        ),
      ),
      // The last confirmation before the network gets the transaction.
      actions: [
        GhostButton(
          label: 'Cancel',
          isFullWidth: phone,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        PrimaryButton(
          label: 'Broadcast',
          isFullWidth: phone,
          onPressed: hidesSpend ? null : () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}
