// The exact decimal arithmetic behind every token amount field: display
// units in, base units out, never through a double.

import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/shared/asset_amount.dart';
import 'package:templar_wallet/shared/asset_naming.dart';

void main() {
  group('AssetAmount.parse', () {
    test('reads display units at the asset precision', () {
      expect(AssetAmount.parse('100.00', 2).baseUnits, 10000);
      expect(AssetAmount.parse('100', 2).baseUnits, 10000);
      expect(AssetAmount.parse('100.5', 2).baseUnits, 10050);
      expect(AssetAmount.parse('0.01', 2).baseUnits, 1);
      expect(AssetAmount.parse('.5', 1).baseUnits, 5);
      expect(AssetAmount.parse('7', 0).baseUnits, 7);
      expect(AssetAmount.parse('10000.00', 2).baseUnits, 1000000);
    });

    test('is exact where a double is not', () {
      // 0.29 * 100 == 28.999999999999996 in floating point.
      expect(AssetAmount.parse('0.29', 2).baseUnits, 29);
      expect(AssetAmount.parse('1.15', 2).baseUnits, 115);
      expect(AssetAmount.parse('0.00000001', 8).baseUnits, 1);
      expect(
        AssetAmount.parse('20999999.99999999', 8).baseUnits,
        2099999999999999,
      );
    });

    test('accepts a decimal comma and digit grouping', () {
      expect(AssetAmount.parse('100,50', 2).baseUnits, 10050);
      expect(AssetAmount.parse(' 1 000.00 ', 2).baseUnits, 100000);
      expect(AssetAmount.parse("1'000", 0).baseUnits, 1000);
    });

    test('refuses more decimals than the precision allows', () {
      final p = AssetAmount.parse('1.001', 2, unit: 'TMPL');
      expect(p.baseUnits, isNull);
      expect(p.error, 'TMPL has 2 decimals at most');
      expect(
        AssetAmount.parse('1.5', 0, unit: 'NFT').error,
        'NFT has no decimals: enter a whole number',
      );
      expect(AssetAmount.parse('0.12', 1).error, contains('1 decimal at'));
    });

    test('keeps trailing zeros within the precision', () {
      expect(AssetAmount.parse('1.10', 2).baseUnits, 110);
      expect(AssetAmount.parse('1.100', 2).isValid, isFalse);
    });

    test('refuses what is not a number', () {
      for (final bad in ['abc', '1.2.3', '-1', '1e3', '.', '+5', '0x10']) {
        expect(AssetAmount.parse(bad, 2).error, 'Enter a number', reason: bad);
      }
    });

    test('empty is neither valid nor an error', () {
      final p = AssetAmount.parse('  ', 2);
      expect(p.isEmpty, isTrue);
      expect(p.isValid, isFalse);
    });

    test('refuses more than any asset holds', () {
      expect(AssetAmount.parse('21000001', 8).error, isNotNull);
      expect(AssetAmount.parse('99999999999999999999', 0).error, isNotNull);
    });
  });

  group('AssetAmount.format', () {
    test('writes exactly precision decimals', () {
      expect(AssetAmount.format(10000, 2), '100.00');
      expect(AssetAmount.format(1, 8), '0.00000001');
      expect(AssetAmount.format(7, 0), '7');
      expect(AssetAmount.format(0, 2), '0.00');
      expect(AssetAmount.format(-150, 2), '-1.50');
    });

    test('groups thousands on request', () {
      expect(AssetAmount.format(1000000, 2, group: true), '10,000.00');
      expect(AssetAmount.format(123456789, 0, group: true), '123,456,789');
      expect(AssetAmount.baseUnitsText(10000), '10,000 base units');
      expect(AssetAmount.baseUnitsText(1), '1 base unit');
    });

    test('round-trips', () {
      for (final (v, p) in [(10050, 2), (1, 8), (999, 0), (123456789, 4)]) {
        expect(AssetAmount.parse(AssetAmount.format(v, p), p).baseUnits, v);
      }
    });
  });

  group('AssetAmountField', () {
    const tmpl = AssetAmountField(precision: 2, unit: 'TMPL');
    const unknown = AssetAmountField(precision: null, unit: 'abcd1234');

    test('display units when the precision is known', () {
      expect(tmpl.parse('100.00').baseUnits, 10000);
      expect(tmpl.format(10000), '100.00 TMPL');
      expect(tmpl.help(''), 'In TMPL, up to 2 decimals');
      expect(tmpl.help('100.00'), '= 10,000 base units');
      expect(tmpl.help('1.234'), 'TMPL has 2 decimals at most');
      expect(tmpl.fieldText(10000), '100.00');
    });

    test('base units, labelled, when it is not', () {
      expect(unknown.inBaseUnits, isTrue);
      expect(unknown.parse('10000').baseUnits, 10000);
      expect(unknown.parse('1.5').error, isNotNull);
      expect(unknown.format(10000), '10,000 base units');
      expect(unknown.help(''), contains('In base units'));
      expect(unknown.fieldText(10000), '10000');
    });
  });

  group('asset naming', () {
    const id =
        'a9fab7bb1d633d1e6f26d3d20f6780018e0a0ae861941e4f478ab3ba575dc378';
    test('the short id goes beside a name the wallet did not give', () {
      expect(showsAssetIdBeside('book', shownName: 'TMPL', assetId: id), true);
      expect(showsAssetIdBeside('feed', shownName: 'X', assetId: id), true);
      expect(
        showsAssetIdBeside('wallet', shownName: 'LBTC', assetId: id),
        false,
      );
      expect(
        showsAssetIdBeside('none', shownName: 'a9fab7bb', assetId: id),
        false,
      );
      // A name that already is the short id is not repeated.
      expect(
        showsAssetIdBeside('feed', shownName: 'a9fab7bb', assetId: id),
        false,
      );
      expect(shortAssetId(id), 'a9fab7bb');
    });
  });
}
