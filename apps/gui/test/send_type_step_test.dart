// Send opens on Compose — one page with the recipient, the fee and the coins —
// and Review is the only step after it. What used to be the Type step's
// second card, "Cosign a transaction", is a link on Compose that still reaches
// the co-sign view.
//
// Review must stay unreachable until the form would have passed every check
// the old six-step wizard made on its way there: an address and an amount
// above zero.
//
// "Verify a PSBT" was once a third type and is gone. The guard is that it
// stays gone: it inspected a transaction while withholding every action,
// which is the load-and-inspect half of the co-sign screen with buttons
// removed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/dashboard/models/dashboard_data.dart';
import 'package:templar_wallet/features/psbt/cosign_view.dart';
import 'package:templar_wallet/features/send/send_screen.dart';
import 'package:templar_wallet/shared/widgets/buttons.dart';

/// A wallet with a Bitcoin balance and nothing else. Every other call misses
/// (noSuchMethod), which the screens under test catch. Keeps the native
/// library and the user's wallet directory out of a unit test.
class _BtcOnlyBridge implements WalletBridge {
  @override
  Future<DashboardData> getWalletSummary(String walletId) async =>
      const DashboardData(
        walletId: 'w1',
        walletName: 'Test',
        totalBalanceDisplay: '0.01000000 BTC',
        assets: [
          AssetBalance(
            assetId: 'btc',
            ticker: 'BTC',
            name: 'Bitcoin',
            amount: 1000000,
            displayAmount: '0.01000000 BTC',
            isNative: true,
          ),
        ],
        recentActivity: [],
        syncState: 'synced',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(String walletType) => MaterialApp(
  home: ChangeNotifierProvider<AppState>(
    create: (_) =>
        AppState()..setActiveWallet('w1', name: 'Test', type: walletType),
    child: SendScreen(bridge: _BtcOnlyBridge()),
  ),
);

/// A desktop window: `AppLayout.isPhone` also needs a mobile platform, so a
/// host test can only ever exercise this arm.
Future<void> _pump(WidgetTester t, String walletType) async {
  t.view.physicalSize = const Size(1280, 2000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(_host(walletType));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

PrimaryButton _reviewButton(WidgetTester t) => t.widget<PrimaryButton>(
  find.widgetWithText(PrimaryButton, 'Review'),
);

Finder _field(String hint) =>
    find.ancestor(of: find.text(hint), matching: find.byType(TextField));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('Send opens on Compose, with no type step', (t) async {
    await _pump(t, 'Standard');

    expect(find.text('Recipient'), findsOneWidget);
    expect(find.text('Fee'), findsOneWidget);
    expect(find.text('Coins'), findsOneWidget);
    expect(find.widgetWithText(PrimaryButton, 'Review'), findsOneWidget);
    expect(find.text('Standard transaction'), findsNothing);
    expect(find.text('Create a partial transaction'), findsNothing);
    expect(find.text('Continue'), findsNothing);
  });

  testWidgets('"Cosign a transaction" still reaches the cosign view', (
    t,
  ) async {
    for (final type in const ['Standard', 'Multisig 2-of-3']) {
      await _pump(t, type);
      expect(find.byType(CosignView), findsNothing);

      await t.tap(find.text('Cosign a transaction'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(CosignView), findsOneWidget);

      // And back out to Compose, with nothing carried across.
      await t.tap(find.text('Back to send'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(CosignView), findsNothing);
      expect(find.widgetWithText(PrimaryButton, 'Review'), findsOneWidget);
    }
  });

  testWidgets('Review is unreachable without a valid recipient and amount', (
    t,
  ) async {
    await _pump(t, 'Standard');
    expect(_reviewButton(t).onPressed, isNull);
    expect(find.text('Add an address'), findsOneWidget);

    await t.enterText(
      _field('Paste, scan or type'),
      'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
    );
    await t.pump();
    expect(_reviewButton(t).onPressed, isNull);
    expect(find.text('Enter an amount'), findsOneWidget);

    // A typed amount that is not one says so under the field.
    await t.enterText(_field('0.00000000'), '0');
    await t.pump();
    expect(_reviewButton(t).onPressed, isNull);
    expect(find.text('Enter an amount above zero'), findsOneWidget);

    await t.enterText(find.byType(TextField).at(1), '0.0025');
    await t.pump();
    expect(_reviewButton(t).onPressed, isNotNull);

    // An emptied address closes it again.
    await t.enterText(find.byType(TextField).first, '');
    await t.pump();
    expect(_reviewButton(t).onPressed, isNull);
  });

  testWidgets('no wallet is offered a verify-only mode', (t) async {
    for (final type in const ['Multisig 2-of-3', 'Standard']) {
      await _pump(t, type);
      expect(find.text('Verify a PSBT'), findsNothing);
      expect(find.textContaining('Nothing is signed'), findsNothing);
    }
  });
}
