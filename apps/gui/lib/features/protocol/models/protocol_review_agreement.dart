import '../../psbt/models/pset_inspection.dart';
import 'protocol_link.dart';

/// Result of comparing the site's human summary with the wallet's PSET view.
///
/// Only lines with an unambiguous meaning are compared. Unknown prose is not
/// guessed. Any comparable mismatch blocks signing.
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

    for (final line
        in request.summary?.lines ?? const <ProtocolSummaryLine>[]) {
      final label = line.label.toLowerCase().trim();
      final amount = _Amount.parse(line.amount);
      if (amount == null) continue;
      List<_Amount>? expected;
      if (label.contains('you receive')) {
        expected = incoming;
      } else if (label.contains('you send') || label.contains('you pay')) {
        expected = outgoing;
      } else if (label.contains('remains locked') ||
          label.contains('collateral locked')) {
        expected = locked;
      } else if (label.contains('network fee')) {
        expected = fee == null ? const [] : [fee];
      }
      if (expected == null) continue;
      checked++;
      if (!expected.contains(amount)) {
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
