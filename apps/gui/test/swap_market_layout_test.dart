import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/swap/swap_screen.dart';

Widget _screen() => ChangeNotifierProvider<AppState>(
  create: (_) => AppState()
    ..setActiveWallet('wallet-1', name: 'Primary', type: 'Software')
    ..setLiquidNetworkInfo(
      const LiquidNetworkInfo(
        network: 'liquid-testnet',
        shortName: 'testnet',
        policyAsset:
            '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49',
        backend: 'electrum',
        backendDescription: 'test',
      ),
    ),
  child: const MaterialApp(home: SwapScreen()),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('market reads as a compact wallet tool on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    expect(find.text('Local order book'), findsOneWidget);
    expect(find.text('LOCAL ROUTING · TESTNET'), findsOneWidget);
    expect(find.text('3 open routes'), findsOneWidget);
    expect(find.text('Liquid swaps · live settlement'), findsOneWidget);
    expect(find.text('Bitcoin routes · live HTLC testnet'), findsOneWidget);
    expect(find.text('New offer'), findsOneWidget);
    expect(find.text('Maker posts; taker completes'), findsOneWidget);
    expect(find.text('Two-wallet test'), findsOneWidget);
    expect(find.textContaining('Trade across'), findsNothing);

    final title = tester.widget<Text>(find.text('Local order book'));
    expect(title.style?.fontSize, lessThanOrEqualTo(21));
  });

  testWidgets('market keeps the same restrained hierarchy on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('Local order book'));
    expect(title.style?.fontSize, 21);
    expect(find.text('3 MARKETS'), findsOneWidget);
    expect(find.text('HTLC DEMO'), findsNWidgets(2));
  });
}
