import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/services/price_service.dart';

void main() {
  group('formatFiat', () {
    test('two decimals and thousands groups from one unit up', () {
      expect(PriceService.formatFiat(1183.2, '€'), '€1,183.20');
      expect(PriceService.formatFiat(842.1, '€'), '€842.10');
      expect(PriceService.formatFiat(1250000, '€'), '€1,250,000.00');
      expect(PriceService.formatFiat(1, '\$'), '\$1.00');
    });

    test('four decimals below one unit', () {
      expect(PriceService.formatFiat(0.0042, '€'), '€0.0042');
      expect(PriceService.formatFiat(0, '€'), '€0.0000');
      expect(PriceService.formatFiat(0.99996, '€'), '€1.00');
    });

    test('never abbreviated', () {
      final s = PriceService.formatFiat(98765432.1, 'CHF ');
      expect(s, 'CHF 98,765,432.10');
      expect(s.contains('k') || s.contains('M'), isFalse);
    });
  });

  group('PriceService displays', () {
    tearDown(() => PriceService.instance.debugSetPrice(0));

    test('no price: null and a dash', () {
      PriceService.instance.debugSetPrice(0);
      expect(PriceService.instance.fiatDisplay(100000), isNull);
      expect(PriceService.instance.totalFiatDisplay(100000), '—');
    });

    test('sats valued at the pinned price', () {
      PriceService.instance.debugSetPrice(68210, currency: 'EUR');
      // 1,734,567 sats × €68,210 / BTC.
      expect(PriceService.instance.totalFiatDisplay(1734567), '€1,183.15');
      expect(PriceService.instance.fiatDisplay(1234567), '€842.10');
      expect(PriceService.instance.fiatDisplay(6), '€0.0041');
    });
  });
}
