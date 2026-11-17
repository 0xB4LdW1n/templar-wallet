// Test coins from a joined test server's faucet, asked for inside the
// wallet: the Dashboard card lists what the faucet pays with one action per
// coin, a payment says what is on its way and syncs the wallet once after
// the lab's next block, the four refusals read as plain words, and a
// wallet without a chain gets no action for that chain's coin.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/test_coins/test_coins.dart';
import 'package:templar_wallet/features/test_coins/test_coins_card.dart';

Future<(MockWalletBridge, AppState)> _lab({
  bool liquid = true,
  bool bitcoin = true,
  bool join = true,
}) async {
  final bridge = MockWalletBridge();
  if (join) await bridge.setTestServer('http://127.0.0.1:8196');
  final state = AppState()
    ..setActiveWallet(
      'wallet-1',
      name: 'Primary',
      type: 'Software',
      liquid: liquid,
      bitcoin: bitcoin,
    )
    ..setLiquidNetworkInfo(await bridge.getLiquidNetwork())
    ..setTestServerInfo(await bridge.getTestServer());
  return (bridge, state);
}

Future<void> _pump(WidgetTester tester, AppState state, Widget child) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(24), child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestCoins.instance.reset();
    TestCoins.syncDelay = const Duration(seconds: 35);
  });

  testWidgets('the card lists every coin the faucet pays', (tester) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    await _pump(tester, state, TestCoinsCard(bridge: bridge));

    expect(find.text('Test coins'), findsOneWidget);
    expect(find.text('Get BTC'), findsOneWidget);
    expect(find.text('Get L-BTC'), findsOneWidget);
    expect(find.text('Get USDt'), findsOneWidget);
    expect(find.text('0.01000000 BTC per request'), findsOneWidget);
    expect(find.text('100.00000000 USDt per request'), findsOneWidget);
    expect(find.textContaining('faucet of Mock testlab'), findsOneWidget);
  });

  testWidgets('a payment says what is on its way, then syncs once', (
    tester,
  ) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    TestCoins.syncDelay = const Duration(seconds: 5);
    await _pump(tester, state, TestCoinsCard(bridge: bridge));
    final before = state.syncVersion;

    await tester.tap(find.text('Get BTC'));
    await tester.pump();
    expect(find.text('Asking the faucet…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(bridge.faucetRequests, ['btc']);
    expect(
      find.text(
        '0.01000000 BTC on its way: it shows after the test server\'s next '
        'block, in about 30 seconds',
      ),
      findsOneWidget,
    );
    // No sync yet: the coins are not in a block.
    expect(state.syncVersion, before);
    await tester.pump(const Duration(seconds: 5));
    expect(state.syncState, SyncState.syncing);
    await tester.pump(const Duration(seconds: 3));
    expect(state.syncState, SyncState.synced);
    expect(state.syncVersion, before + 1);
  });

  testWidgets('a rate limit says when to try again', (tester) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    bridge.mockFaucetError =
        'FAUCET_RATE_LIMITED: 3 requests per address per hour. Try again in '
        '840 seconds.';
    await _pump(tester, state, TestCoinsCard(bridge: bridge));
    await tester.tap(find.text('Get L-BTC'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(
        'The faucet\'s limit is reached (3 requests per address per hour). '
        'Try again in 14 minutes',
      ),
      findsOneWidget,
    );
    // Nothing paid, nothing to sync.
    await tester.pump(const Duration(seconds: 40));
    expect(state.syncState, isNot(SyncState.syncing));
  });

  testWidgets('an unavailable or silent faucet is said plainly', (
    tester,
  ) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    bridge.mockFaucetError =
        'FAUCET_UNAVAILABLE: the faucet answered HTTP 503 (its node refused).';
    await _pump(tester, state, TestCoinsCard(bridge: bridge));
    await tester.tap(find.text('Get USDt'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(
        'The faucet cannot pay this here: the faucet answered HTTP 503 (its '
        'node refused)',
      ),
      findsOneWidget,
    );

    bridge.mockFaucetError = 'FAUCET_UNREACHABLE: connection refused';
    await tester.tap(find.text('Get BTC'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.textContaining('The test server\'s faucet did not answer'),
      findsOneWidget,
    );
  });

  testWidgets('no faucet off the lab, and no coin for a missing chain', (
    tester,
  ) async {
    final (bridge, off) = (await tester.runAsync(() => _lab(join: false)))!;
    await _pump(tester, off, TestCoinsCard(bridge: bridge));
    expect(find.text('Test coins'), findsNothing);

    final (bridge2, btcOnly) = (await tester.runAsync(
      () => _lab(liquid: false),
    ))!;
    await _pump(tester, btcOnly, TestCoinsCard(bridge: bridge2));
    expect(find.text('Get BTC'), findsOneWidget);
    expect(find.text('Get L-BTC'), findsNothing);
    expect(find.text('Get USDt'), findsNothing);
  });

  testWidgets('one coin\'s action, as Receive and Peg show it', (tester) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    await _pump(
      tester,
      state,
      Column(
        children: [
          TestCoinAction(bitcoin: false, bridge: bridge),
          TestCoinAction(bitcoin: true, bridge: bridge),
        ],
      ),
    );
    expect(find.text('Get test L-BTC'), findsOneWidget);
    expect(find.text('Get test BTC'), findsOneWidget);
    await tester.tap(find.text('Get test L-BTC'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(bridge.faucetRequests, ['lbtc']);
    expect(find.textContaining('0.01000000 L-BTC on its way'), findsOneWidget);
    TestCoins.instance.reset();
  });
}
