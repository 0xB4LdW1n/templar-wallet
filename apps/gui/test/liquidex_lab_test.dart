// LiquiDEX on a test server's regtest and on Liquid testnet: the
// cross-chain (BTC ↔ Liquid HTLC) feature exists only on testnet, My swaps
// reads its two lists apart so a failure of one never hides the other, a
// row that is not live says why in words, a name the wallet did not give
// carries its short asset id, and the lab's one dashboard is the admin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/swap/make_offer_flow.dart';
import 'package:templar_wallet/features/swap/models/swap_offer.dart';
import 'package:templar_wallet/features/swap/order_book_admin.dart';
import 'package:templar_wallet/features/swap/swap_screen.dart';

MockWalletBridge get _mock => walletBridge as MockWalletBridge;

Future<AppState> _state({required bool lab}) async {
  if (lab) {
    await _mock.setTestServer('http://127.0.0.1:8196');
  } else {
    await _mock.clearTestServer();
  }
  return AppState()
    ..setActiveWallet('wallet-1', name: 'Primary', type: 'Software')
    ..setLiquidNetworkInfo(await _mock.getLiquidNetwork())
    ..setTestServerInfo(await _mock.getTestServer())
    ..testServerChecked = true;
}

Future<void> _pump(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1280, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: SwapScreen()),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mock.mockMyOffersError = null;
    _mock.mockAtomicSwapListError = null;
  });
  tearDown(() async => _mock.clearTestServer());

  testWidgets('on a lab: no BTC routes, a registry name with its id', (
    tester,
  ) async {
    await _pump(tester, (await tester.runAsync(() => _state(lab: true)))!);

    expect(find.text('BTC routes'), findsNothing);
    expect(find.text('Liquid assets'), findsNothing);
    expect(find.text('Closed'), findsWidgets);
    expect(find.textContaining('HTLC'), findsNothing);
    // TMPL is the book's name, not the wallet's: its short id beside it.
    expect(find.text('Receive 100.00 TMPL · 80d249a8'), findsOneWidget);
    expect(find.textContaining('Pay 0.05000000 LBTC'), findsOneWidget);
    expect(find.textContaining('b2e15d0d'), findsNothing);
    expect(
      find.text('Offers created by this wallet appear here'),
      findsNothing,
    ); // the mock wallet has offers
    expect(find.text('Cross-chain swaps'), findsNothing);
  });

  testWidgets('on a lab, New offer goes straight to LiquiDEX', (tester) async {
    await _pump(tester, (await tester.runAsync(() => _state(lab: true)))!);
    await tester.tap(find.text('New offer'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(MakeOfferFlowScreen), findsOneWidget);
    expect(find.text('Choose settlement'), findsNothing);
    expect(find.text('BTC ↔ Liquid'), findsNothing);
  });

  testWidgets('on testnet the cross-chain feature stays', (tester) async {
    await _pump(tester, (await tester.runAsync(() => _state(lab: false)))!);
    expect(find.text('BTC routes'), findsOneWidget);
    expect(find.text('Cross-chain swaps'), findsOneWidget);
    await tester.tap(find.text('New offer'));
    await tester.pumpAndSettle();
    expect(find.text('Choose settlement'), findsOneWidget);
  });

  testWidgets('a failing cross-chain list never hides the offers', (
    tester,
  ) async {
    _mock.mockAtomicSwapListError =
        'Order book HTTP 404: Unknown atomic swap: 1';
    await _pump(tester, (await tester.runAsync(() => _state(lab: false)))!);

    expect(find.text('My swaps'), findsOneWidget);
    expect(find.textContaining('Order book HTTP'), findsNothing);
    expect(
      find.text(
        'The cross-chain swaps could not be read: the order book answered '
        'with an error (404). Refresh to try again',
      ),
      findsOneWidget,
    );
    // The wallet's LiquiDEX offers are still listed.
    expect(find.textContaining('of_'), findsWidgets);
  });

  testWidgets('a failing offers list never hides the cross-chain swaps', (
    tester,
  ) async {
    _mock.mockMyOffersError = 'Order book HTTP 500: boom';
    await _pump(tester, (await tester.runAsync(() => _state(lab: false)))!);
    expect(find.textContaining('Order book HTTP'), findsNothing);
    expect(
      find.textContaining('This wallet\'s LiquiDEX offers could not be read'),
      findsOneWidget,
    );
    expect(find.text('Cross-chain swaps'), findsOneWidget);
    expect(find.textContaining('#7'), findsWidgets);
  });

  test('availability states read as words', () {
    expect(
      atomicAvailabilityText('not_on_this_book'),
      'this order book no longer knows it',
    );
    expect(atomicAvailabilityText('book_unreachable'), contains('may still'));
    expect(atomicAvailabilityBadge('other_book'), 'Other book');
    expect(atomicAvailabilityBadge('book_mismatch'), 'Mismatch');
    final s = AtomicSwap.fromJson({
      'offer_id': 1,
      'role': 'maker',
      'availability': 'not_on_this_book',
      'row': <String, dynamic>{},
    });
    expect(s.isLive, isFalse);
  });

  test('raw order-book errors become sentences', () {
    expect(
      plainBookError(
        Exception('wallet-ffi: Order book HTTP 404: Unknown atomic swap: 1'),
        what: 'X',
      ),
      'X: the order book answered with an error (404). Refresh to try again',
    );
    expect(
      plainBookError(Exception('wallet-ffi: connection refused'), what: 'X'),
      'X: the order book did not answer. Refresh to try again',
    );
  });

  testWidgets('a lab on this machine: the admin is its one dashboard', (
    tester,
  ) async {
    final state = (await tester.runAsync(() => _state(lab: true)))!;
    expect(
      orderBookAdminUri(state).toString(),
      'http://127.0.0.1:8196/admin#liquidex',
    );
  });
}
