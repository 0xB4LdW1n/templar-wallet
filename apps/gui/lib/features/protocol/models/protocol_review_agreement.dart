import '../../psbt/models/pset_inspection.dart';
import 'protocol_link.dart';

/// Result of comparing the site's human summary with the wallet's PSET view.
///
/// Only lines with an unambiguous meaning are compared. Unknown prose is not
/// guessed. Any comparable mismatch blocks signing.
///
/// A line that names its `asset` id and `sats` is compared on those against
/// the engine's own figures: the ticker is only words (a regtest asset has
/// none the engine knows, and the site may call L-BTC rLBTC). A line without
/// them falls back to comparing the amount text, value and ticker.
class ProtocolReviewAgreement {
  const ProtocolReviewAgreement({
    required this.checked,
    required this.mismatches,
    required this.hasUnverifiedOutputs,
  });

  final int checked;
  final List<String> mismatches;
  final bool hasUnverifiedOutputs;

  bool get canSign => !hasUnverifiedOutputs && mismatches.isEmpty;
  bool get couldCompare => checked > 0;

  static ProtocolReviewAgreement compare(
    ProtocolRequest request,
    PsetInspection inspection,
  ) {
    var checked = 0;
    final mismatches = <String>[];
    final incoming = inspection.netChangeLines
        .where((line) => line.amountSats > 0)
        .map((line) => _Amount.parse(line.displayAmount))
        .whereType<_Amount>()
        .toList();
    final outgoing = inspection.netChangeLines
        .where((line) => line.amountSats < 0)
        .map((line) => _Amount.parse(line.displayAmount))
        .whereType<_Amount>()
        .toList();
    final locked = inspection.outputs
        .where((output) => output.isEscrow)
        .map((output) => _Amount.parse(output.displayAmount ?? ''))
        .whereType<_Amount>()
        .toList();
    final fee = _Amount.parse(inspection.feeDisplay);
    final incomingExact = [
      for (final l in inspection.netChangeLines)
        if (l.amountSats > 0) _Exact(l.assetId, l.amountSats),
    ];
    final outgoingExact = [
      for (final l in inspection.netChangeLines)
        if (l.amountSats < 0) _Exact(l.assetId, -l.amountSats),
    ];
    final lockedExact = [
      for (final o in inspection.outputs)
        if (o.isEscrow && o.assetId != null && o.amountSats != null)
          _Exact(o.assetId!, o.amountSats!),
    ];

    for (final line
        in request.summary?.lines ?? const <ProtocolSummaryLine>[]) {
      final label = line.label.toLowerCase().trim();
      final _Bucket bucket;
      if (label.contains('you receive')) {
        bucket = _Bucket.incoming;
      } else if (label.contains('you send') || label.contains('you pay')) {
        bucket = _Bucket.outgoing;
      } else if (label.contains('remains locked') ||
          label.contains('collateral locked')) {
        bucket = _Bucket.locked;
      } else if (label.contains('network fee')) {
        bucket = _Bucket.fee;
      } else {
        continue;
      }
      final bool agrees;
      if (line.isExact) {
        final claim = _Exact(line.assetId, line.sats!);
        agrees = switch (bucket) {
          _Bucket.incoming => incomingExact.contains(claim),
          _Bucket.outgoing => outgoingExact.contains(claim),
          _Bucket.locked => lockedExact.contains(claim),
          // The fee is always the policy asset: its amount is the figure.
          _Bucket.fee => line.sats == inspection.feeSats,
        };
      } else {
        final amount = _Amount.parse(line.amount);
        if (amount == null) continue;
        final expected = switch (bucket) {
          _Bucket.incoming => incoming,
          _Bucket.outgoing => outgoing,
          _Bucket.locked => locked,
          _Bucket.fee => fee == null ? const <_Amount>[] : [fee],
        };
        agrees = expected.contains(amount);
      }
      checked++;
      if (!agrees) {
        mismatches.add('${line.label}: site says ${line.amount}.');
      }
    }

    return ProtocolReviewAgreement(
      checked: checked,
      mismatches: mismatches,
      hasUnverifiedOutputs: inspection.hasUnverifiedOutputs,
    );
  }
}

enum _Bucket { incoming, outgoing, locked, fee }

/// An amount as the chain has it: asset id and base units.
class _Exact {
  _Exact(String assetId, this.sats) : assetId = assetId.toLowerCase();

  final String assetId;
  final int sats;

  @override
  bool operator ==(Object other) =>
      other is _Exact && other.assetId == assetId && other.sats == sats;

  @override
  int get hashCode => Object.hash(assetId, sats);
}

class _Amount {
  const _Amount(this.value, this.unit);

  final String value;
  final String unit;

  static _Amount? parse(String raw) {
    final match = RegExp(
      r'([+-]?[0-9][0-9,]*(?:\.[0-9]+)?)\s+([A-Za-z][A-Za-z0-9._-]*)',
    ).firstMatch(raw.trim());
    if (match == null) return null;
    var value = match.group(1)!.replaceAll(',', '');
    if (value.startsWith('+') || value.startsWith('-')) {
      value = value.substring(1);
    }
    final parts = value.split('.');
    var whole = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (whole.isEmpty) whole = '0';
    var fraction = parts.length == 1
        ? ''
        : parts.sublist(1).join().replaceFirst(RegExp(r'0+$'), '');
    value = fraction.isEmpty ? whole : '$whole.$fraction';
    return _Amount(value, match.group(2)!.toLowerCase());
  }

  @override
  bool operator ==(Object other) =>
      other is _Amount && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);
}
