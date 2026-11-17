// "Use my own address" is one window: the next unused address and every one
// that already received, each under the label and the colour Receive gave
// it. Tapping a row picks that address.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/receive/models/address_info.dart';
import 'package:templar_wallet/features/send/own_address_dialog.dart';
import 'package:templar_wallet/services/address_label_store.dart';
import 'package:templar_wallet/shared/widgets/address_tag.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';

const _unused = 'tb1qunused0000000000000000000000000000000';
const _savings = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
const _plain = 'tb1qrp33g0q5c5txsp9arysrx4k6zdkfs4nce4xj0g';

class _Bridge implements WalletBridge {
  /// Whether a fresh address was asked for: opening the picker must not
  /// burn an index.
  bool askedFresh = false;

  @override
  Future<AddressInfo> generateReceiveAddress(
    String walletId,
    String asset, {
    bool fresh = false,
  }) async {
    askedFresh = askedFresh || fresh;
    return const AddressInfo(address: _unused, index: 7, asset: 'BTC');
  }

  @override
  Future<List<AddressInfo>> listPreviousAddresses(
    String walletId,
    String asset,
  ) async => const [
    AddressInfo(address: _plain, index: 2, asset: 'BTC', receivedSats: 0),
    AddressInfo(
      address: _savings,
      index: 4,
      asset: 'BTC',
      receivedSats: 500000,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<String?> Function() _open(WidgetTester t, _Bridge bridge) {
  String? picked;
  var done = false;
  t.view.physicalSize = const Size(1280, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final app = MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            picked = await showOwnAddressPicker(
              context,
              bridge: bridge,
              walletId: 'w1',
              asset: 'BTC',
              useSats: false,
            );
            done = true;
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  return () async {
    if (!done) {
      await t.pumpWidget(app);
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
    }
    return picked;
  };
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'address_labels_v1': json.encode({_savings: 'Savings'}),
      'address_label_hues_v1': json.encode({_savings: 3}),
    });
    AddressLabelStore.instance.debugReset();
  });

  testWidgets('one window lists the unused address and the used ones, the '
      'newest first, under their labels', (t) async {
    final bridge = _Bridge();
    await _open(t, bridge)();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Use my own address'), findsOneWidget);
    expect(find.text('Unused'), findsOneWidget);
    expect(find.text('Used · 2'), findsOneWidget);
    // Opening it reads the current address; it does not derive a new one.
    expect(bridge.askedFresh, isFalse);

    // The labelled address shows its tag; the others their own address.
    final tag = t.widget<AddressTag>(find.byType(AddressTag));
    expect(tag.label, 'Savings');
    expect(tag.hue, isNotNull);
    expect(find.text('#4 · tb1qw508d6qe…7kxpjzsx'), findsOneWidget);
    expect(find.text('0.00500000'), findsOneWidget);

    // Newest first: #4 above #2.
    final four = t.getTopLeft(find.text('#4 · tb1qw508d6qe…7kxpjzsx')).dy;
    final two = t.getTopLeft(find.text('#2')).dy;
    expect(four, lessThan(two));
    expect(t.takeException(), isNull);
  });

  testWidgets('tapping a row picks that address and closes the window', (
    t,
  ) async {
    final result = _open(t, _Bridge());
    await result();

    await t.tap(find.text('Savings'));
    await t.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(await result(), _savings);
  });

  testWidgets('Close backs out without picking', (t) async {
    final result = _open(t, _Bridge());
    await result();

    await t.tap(find.text('Close'));
    await t.pumpAndSettle();

    expect(find.byType(AppDialog), findsNothing);
    expect(await result(), isNull);
  });
}
