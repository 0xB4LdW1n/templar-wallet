// The rate of a two-leg swap, stated both ways ("1 LBTC = 100,000 USDT" and
// "1 USDT = 0.00001 LBTC"), computed only from the two amounts the review
// already shows — no price feed, no figure the engine did not give us.

/// The two rate lines for [aAmount] of [aTicker] against [bAmount] of
/// [bTicker], or null when either amount is not a positive number.
(String, String)? swapRateLines(
  String aAmount,
  String aTicker,
  String bAmount,
  String bTicker,
) {
  final a = _number(aAmount);
  final b = _number(bAmount);
  if (a == null || b == null || a <= 0 || b <= 0) return null;
  return (
    '1 $aTicker = ${_format(b / a)} $bTicker',
    '1 $bTicker = ${_format(a / b)} $aTicker',
  );
}

/// The leading figure of a display amount ("1,000.50 USDT" → 1000.5).
double? _number(String display) {
  final match = RegExp(r'[0-9][0-9,]*(\.[0-9]+)?').firstMatch(display);
  if (match == null) return null;
  return double.tryParse(match.group(0)!.replaceAll(',', ''));
}

/// Up to eight decimals with trailing zeros dropped, grouped thousands.
String _format(double v) {
  var text = v.toStringAsFixed(8);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  final parts = text.split('.');
  final whole = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) b.write(',');
    b.write(whole[i]);
  }
  return parts.length > 1 ? '$b.${parts[1]}' : b.toString();
}
