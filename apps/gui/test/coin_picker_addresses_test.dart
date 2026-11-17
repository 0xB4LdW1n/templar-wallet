// Picking coins for a send: the coins sit under the address they are on, as
// they do on the coin screen — a row of the register per address, under the
// spine of its colour — in the list and in the notes alike. And the "Sent"
// receipt has a way straight to the transaction in Activity.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/send/models/tx_preview.dart';
import 'package:templar_wallet/features/utxos/models/utxo.dart';
import 'package:templar_wallet/features/utxos/utxo_wall.dart';
import 'package:templar_wallet/services/address_label_store.dart';
import 'package:templar_wallet/shared/widgets/address_tag.dart';
import 'package:templar_wallet/shared/widgets/tx_success_view.dart';
import 'package:templar_wallet/shared/widgets/utxo_views.dart';
import 'package:templar_wallet/theme/app_scheme.dart';

const _savings = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
const _exchange = 'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a';

Utxo _coin(String id, int sats, String address) => Utxo(
  outpoint: '${id * 64}:0',
  amount: sats,
  displayAmount: '$sats sats',
  confirmations: 6,
  state: UtxoState.available,
  ticker: 'BTC',
  address: address,
);

final _coins = [
  _coin('a', 30000, _savings),
  _coin('b', 90000, _savings),
  _coin('c', 20000, _exchange),
];

Future<List<int>> _pumpPicker(WidgetTester t) async {
  final toggled = <int>[];
  t.view.physicalSize = const Size(1000, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 720,
            child: UtxoPicker(
              utxos: _coins,
              maxHeight: 900,
              onToggle: toggled.add,
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
  return toggled;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'address_labels_v1': json.encode({_savings: 'Savings'}),
    });
    AddressLabelStore.instance.debugReset();
  });

  testWidgets('the list keeps each coin under its address', (t) async {
    await AddressLabelStore.instance.load();
    final toggled = await _pumpPicker(t);

    expect(find.byType(AddressCards), findsOneWidget);
    expect(find.byType(AddressCoinGroup), findsNWidgets(2));
    final savings = find.ancestor(
      of: find.text('Savings'),
      matching: find.byType(AddressCoinGroup),
    );
    expect(
      find.descendant(of: savings, matching: find.byType(CoinRow)),
      findsNWidgets(2),
    );
    // A labelled address is named by its tag; the other by the address
    // itself. Neither was coloured, so both cards' swatches are grey.
    final tags = t.widgetList<AddressTag>(find.byType(AddressTag)).toList();
    expect(tags.map((tag) => tag.label), ['Savings']);
    expect(tags.map((tag) => tag.hue), isNot(contains(null)));
    expect(find.text(shortCoinAddress(_exchange)), findsOneWidget);
    final s = AppScheme.of(t.element(find.byType(UtxoPicker)));
    for (final address in [_savings, _exchange]) {
      final section = find.byWidgetPredicate(
        (w) => w is AddressCoinGroup && w.address == address,
      );
      expect(
        t
            .widget<AddressSwatch>(
              find.descendant(
                of: section,
                matching: find.byType(AddressSwatch),
              ),
            )
            .hue,
        s.hueSlate,
      );
    }

    // Picking still reports the coin's own index.
    await t.tap(find.text('90000 sats'));
    await t.pump();
    expect(toggled, [1]);
    expect(t.takeException(), isNull);
  });

  testWidgets('the notes sit in the tray of their address', (t) async {
    await AddressLabelStore.instance.load();
    await _pumpPicker(t);
    await t.tap(find.text('Notes'));
    await t.pumpAndSettle();

    expect(find.byType(AddressCards), findsOneWidget);
    expect(find.byType(AddressTray), findsNWidgets(2));
    final savings = find.ancestor(
      of: find.text('Savings'),
      matching: find.byType(AddressTray),
    );
    expect(
      find.descendant(of: savings, matching: find.byType(UtxoBanknote)),
      findsNWidgets(2),
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('"View in activity" leaves the receipt for the transaction', (
    t,
  ) async {
    var opened = 0;
    t.view.physicalSize = const Size(1280, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showTxSuccessDialog(
                  context,
                  txid: 'f' * 64,
                  ticker: 'BTC',
                  preview: const TxPreview(
                    chain: 'bitcoin',
                    recipientAddress: _savings,
                    amountDisplay: '0.0025 BTC',
                    feeSats: 450,
                    feeDisplay: '450 sats',
                    feeRate: 3,
                    totalDisplay: '0.0025045 BTC',
                    vsizeEst: 150,
                  ),
                  onViewInActivity: () => opened++,
                ),
                child: const Text('send'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('send'));
    await t.pumpAndSettle();

    // Beside the explorer link and Done.
    expect(find.text('View in explorer'), findsOneWidget);
    expect(find.text('View in activity'), findsOneWidget);
    await t.tap(find.text('View in activity'));
    await t.pumpAndSettle();

    expect(opened, 1);
    expect(find.text('Sent'), findsNothing);
  });
}
