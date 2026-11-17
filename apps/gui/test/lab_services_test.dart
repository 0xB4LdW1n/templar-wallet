// What a joined test server provides, stated where the user looks: the
// Test server card lists its faucet (and the coins it pays), its order
// book, its lending site and its peg; Loans and Settings › Templar
// Protocol offer the lab's lending site in the browser.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/loans/lending_site.dart';
import 'package:templar_wallet/features/loans/loans_screen.dart';
import 'package:templar_wallet/features/settings/protocol_section.dart';
import 'package:templar_wallet/features/settings/test_server_section.dart';

Future<(MockWalletBridge, AppState)> _lab({bool join = true}) async {
  final bridge = MockWalletBridge();
  if (join) await bridge.setTestServer('http://127.0.0.1:8196');
  final state = AppState()
    ..setActiveWallet('wallet-1', name: 'Primary', type: 'Software')
    ..setLiquidNetworkInfo(await bridge.getLiquidNetwork())
    ..setTestServerInfo(await bridge.getTestServer())
    ..testServerChecked = true;
  return (bridge, state);
}

Future<void> _pump(WidgetTester tester, AppState state, Widget child) async {
  tester.view.physicalSize = const Size(1100, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the Test server card says what the lab provides', (
    tester,
  ) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    await _pump(tester, state, TestServerCard(bridge: bridge));
    expect(find.text('Faucet'), findsOneWidget);
    expect(
      find.text(
        'Pays BTC, L-BTC and USDt to this wallet, from Test coins on the '
        'Dashboard and Receive',
      ),
      findsOneWidget,
    );
    expect(find.text('Order book'), findsOneWidget);
    expect(
      find.textContaining('LiquiDEX offers and token names'),
      findsOneWidget,
    );
    expect(find.text('Lending site'), findsOneWidget);
    expect(
      find.text(
        'Templar Protocol loans on its regtest · http://127.0.0.1:8098',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Peg-in and peg-out between its Bitcoin and Liquid regtest'),
      findsOneWidget,
    );
  });

  test('the lending site is offered only on the lab\'s regtest', () async {
    final (_, onLab) = await _lab();
    expect(labLendingSite(onLab).toString(), 'http://127.0.0.1:8098');
    final (_, off) = await _lab(join: false);
    expect(labLendingSite(off), isNull);
  });

  testWidgets('Loans, no site yet: open the test server\'s lending site', (
    tester,
  ) async {
    final (_, state) = (await tester.runAsync(_lab))!;
    tester.view.physicalSize = const Size(1100, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: LoansScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('No site connected to this wallet'), findsOneWidget);
    expect(find.byKey(const Key('loans-open-lending-site')), findsOneWidget);
    expect(find.text(kOpenLendingSite), findsOneWidget);
    expect(find.text('http://127.0.0.1:8098'), findsOneWidget);
    expect(find.textContaining('Connect Templar Wallet'), findsOneWidget);
  });

  testWidgets('Loans off a lab: no lending-site link', (tester) async {
    final (_, state) = (await tester.runAsync(() => _lab(join: false)))!;
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: LoansScreen()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text(kOpenLendingSite), findsNothing);
  });

  testWidgets('Settings › Templar Protocol offers the lending site', (
    tester,
  ) async {
    final (bridge, state) = (await tester.runAsync(_lab))!;
    await _pump(tester, state, ProtocolSection(bridge: bridge));
    expect(find.byKey(const Key('protocol-lab-lending-site')), findsOneWidget);
    expect(find.text(kOpenLendingSite), findsOneWidget);
  });
}
