import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches the BTC price in the selected fiat currency from CoinGecko.
/// Caches for 5 min. Custom/unknown tokens have price = 0.
class PriceService extends ChangeNotifier {
  PriceService._();
  static final PriceService instance = PriceService._();

  /// Supported fiat currencies (ISO code → display symbol).
  static const Map<String, String> currencySymbols = {
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CHF': 'CHF ',
    'CAD': 'C\$',
    'AUD': 'A\$',
  };

  /// Selected fiat currency (ISO code). Drives what CoinGecko is asked for and
  /// which symbol is rendered.
  String _currency = 'USD';
  String get currency => _currency;
  String get symbol => currencySymbols[_currency] ?? '$_currency ';

  /// Price of 1 BTC in [_currency].
  double _btcPrice = 0.0;
  double get btcPrice => _btcPrice;

  DateTime? _lastFetch;
  static const _cacheDuration = Duration(minutes: 5);
  bool _fetching = false;

  bool get hasPrice => _btcPrice > 0;

  /// Test seam: pin a price (and optionally a currency) without going near
  /// the network, so the screens that convert between coin and fiat can be
  /// driven from a widget test. The cache stamp is set too, so a screen's
  /// own `fetch()` on the way in does not immediately undo it.
  @visibleForTesting
  void debugSetPrice(double price, {String? currency}) {
    _btcPrice = price;
    if (currency != null) _currency = currency;
    _lastFetch = DateTime.now();
    notifyListeners();
  }

  /// Switch the fiat currency and refetch. No-op if unchanged.
  Future<void> setCurrency(String code) async {
    if (_currency == code) return;
    _currency = code;
    _btcPrice = 0.0; // avoid showing the old-currency value while refetching
    _lastFetch = null;
    notifyListeners();
    await fetch(force: true);
  }

  /// Format a satoshi amount as a fiat value in the selected currency
  /// ([formatFiat]). Returns null if the price is not yet loaded.
  String? fiatDisplay(int sats) {
    if (_btcPrice <= 0) return null;
    return formatFiat(sats / 1e8 * _btcPrice, symbol);
  }

  /// Format a satoshi total as a fiat value ([formatFiat]); `—` while there
  /// is no price.
  String totalFiatDisplay(int sats) {
    if (_btcPrice <= 0) return '—';
    return formatFiat(sats / 1e8 * _btcPrice, symbol);
  }

  /// Every fiat figure in the app: the symbol, the integer part grouped in
  /// thousands, then two decimals — or four below one unit, where two would
  /// round a real amount to zero. Never abbreviated: `€1,183.20`, not
  /// `€1.18k` (design.md, "Type": this is someone's money).
  static String formatFiat(double value, String symbol) {
    if (!value.isFinite) return '—';
    final negative = value < 0;
    final v = value.abs();
    var fixed = v.toStringAsFixed(v >= 1 ? 2 : 4);
    // 0.99996 rounds up to "1.0000": state it as the one unit it now is.
    if (v < 1 && fixed.startsWith('1')) fixed = v.toStringAsFixed(2);
    final dot = fixed.indexOf('.');
    final whole = int.parse(fixed.substring(0, dot));
    return '${negative ? '-' : ''}$symbol${_group(whole)}${fixed.substring(dot)}';
  }

  /// Format a satoshi amount in the user's Bitcoin denomination.
  /// [sat] true → grouped sats ("1,234,567 sats"); false → "0.01234567 BTC".
  /// [coin] labels the whole-coin unit (e.g. 'LBTC' for Liquid bitcoin).
  static String formatUnit(int sats, {required bool sat, String coin = 'BTC'}) {
    if (sat) return '${_group(sats)} sats';
    return '${(sats / 1e8).toStringAsFixed(8)} $coin';
  }

  static String _group(int n) {
    final s = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return (n < 0 ? '-' : '') + b.toString();
  }

  Future<void> fetch({bool force = false}) async {
    if (_fetching) return;
    if (!force &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < _cacheDuration) {
      return;
    }

    _fetching = true;
    final cur = _currency.toLowerCase();
    try {
      final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=$cur',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final price = (data['bitcoin']?[cur] as num?)?.toDouble();
        if (price != null && price > 0) {
          _btcPrice = price;
          _lastFetch = DateTime.now();
          notifyListeners();
        }
      }
    } catch (_) {
      // Network unavailable — keep last cached price
    } finally {
      _fetching = false;
    }
  }
}
