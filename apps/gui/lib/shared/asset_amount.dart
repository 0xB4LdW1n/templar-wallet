/// Exact amounts of a Liquid asset in its own display units.
///
/// A token's precision says how many decimals its display unit has: `TMPL`
/// with precision 2 writes 10,000 base units as `100.00`. What the user types
/// is converted with integer arithmetic on the digits — never through a
/// `double`, which cannot hold every 8-decimal amount exactly — and a figure
/// with more decimals than the precision allows is refused rather than
/// rounded: what is signed must be what was typed.
library;

/// The outcome of [AssetAmount.parse]: base units, or why not.
class AssetAmountParse {
  const AssetAmountParse._(this.baseUnits, this.error);

  /// The amount in base units; null when [error] is set or the text is empty.
  final int? baseUnits;

  /// A short reason for people, e.g. `TMPL has 2 decimals at most`; null
  /// when the text parsed (or was empty).
  final String? error;

  bool get isEmpty => baseUnits == null && error == null;
  bool get isValid => baseUnits != null;
}

abstract final class AssetAmount {
  /// The largest amount one Liquid output can carry (21 million × 10^8).
  static const int maxBaseUnits = 2100000000000000;

  /// [text] in display units of an asset with [precision] decimals → base
  /// units. A decimal comma is accepted like a point; spaces, an underscore
  /// or an apostrophe between digit groups are ignored. With precision 0 no
  /// decimals are allowed at all. [unit] names the asset in the messages.
  static AssetAmountParse parse(
    String text,
    int precision, {
    String unit = 'This asset',
  }) {
    assert(precision >= 0 && precision <= 8);
    var t = text.trim().replaceAll(RegExp(r"[\s_']"), '');
    if (t.isEmpty) return const AssetAmountParse._(null, null);
    t = t.replaceAll(',', '.');
    if (!RegExp(r'^(\d+)?(\.(\d*))?$').hasMatch(t) || t == '.') {
      return const AssetAmountParse._(null, 'Enter a number');
    }
    final dot = t.indexOf('.');
    final whole = dot < 0 ? t : t.substring(0, dot);
    final frac = dot < 0 ? '' : t.substring(dot + 1);
    if (frac.length > precision) {
      return AssetAmountParse._(
        null,
        precision == 0
            ? '$unit has no decimals: enter a whole number'
            : '$unit has $precision decimal${precision == 1 ? '' : 's'} '
                  'at most',
      );
    }
    final digits =
        (whole.isEmpty ? '0' : whole) + frac.padRight(precision, '0');
    final value = BigInt.parse(digits);
    if (value > BigInt.from(maxBaseUnits)) {
      return const AssetAmountParse._(
        null,
        'That is more than any asset holds',
      );
    }
    return AssetAmountParse._(value.toInt(), null);
  }

  /// [baseUnits] written in display units with exactly [precision]
  /// decimals: `format(10000, 2)` is `100.00`. With [group], thousands are
  /// separated by commas (`10,000.00`).
  static String format(int baseUnits, int precision, {bool group = false}) {
    final negative = baseUnits < 0;
    final raw = baseUnits.abs().toString().padLeft(precision + 1, '0');
    var whole = raw.substring(0, raw.length - precision);
    final frac = raw.substring(raw.length - precision);
    if (group) whole = _group(whole);
    final body = precision == 0 ? whole : '$whole.$frac';
    return negative ? '-$body' : body;
  }

  /// Base units grouped for reading: `10,000 base units`.
  static String baseUnitsText(int baseUnits) =>
      '${_group(baseUnits.toString())} base unit${baseUnits == 1 ? '' : 's'}';

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return b.toString();
  }
}

/// An amount field of a Liquid asset: display units when the engine knows
/// the asset's [precision], base units (labelled as such) when it does not.
class AssetAmountField {
  const AssetAmountField({required this.precision, required this.unit});

  /// Null when unknown: the field then takes whole base units.
  final int? precision;

  /// The asset's ticker, for messages and the field's suffix.
  final String unit;

  bool get inBaseUnits => precision == null;

  AssetAmountParse parse(String text) => AssetAmount.parse(
    text,
    precision ?? 0,
    unit: unit.isEmpty ? 'This asset' : unit,
  );

  /// The figure in words: `100.00 TMPL`, or `10,000 base units`.
  String format(int baseUnits) => inBaseUnits
      ? AssetAmount.baseUnitsText(baseUnits)
      : '${AssetAmount.format(baseUnits, precision!, group: true)} $unit';

  /// The line under the field: the rule while it is empty, the base-unit
  /// figure that will be signed once it parses, or why it does not.
  String help(String text) {
    final p = parse(text);
    if (p.error != null) return p.error!;
    final base = p.baseUnits;
    if (inBaseUnits) {
      return base == null
          ? 'In base units: this asset\'s decimals are not known'
          : 'In base units: ${AssetAmount.baseUnitsText(base)}';
    }
    if (base == null) {
      return precision == 0
          ? 'In $unit, a whole number'
          : 'In $unit, up to $precision decimals';
    }
    return '= ${AssetAmount.baseUnitsText(base)}';
  }

  /// The text that fills the field for [baseUnits] (e.g. "Burn all").
  String fieldText(int baseUnits) =>
      inBaseUnits ? '$baseUnits' : AssetAmount.format(baseUnits, precision!);
}
