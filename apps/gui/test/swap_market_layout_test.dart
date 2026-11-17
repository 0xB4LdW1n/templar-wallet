import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/swap/swap_screen.dart';
import 'package:templar_wallet/shared/widgets/buttons.dart';
import 'package:templar_wallet/theme/app_layout.dart';
import 'package:templar_wallet/theme/app_typography.dart';

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
    AppLayout.debugMobileOverride = true;
    addTearDown(() => AppLayout.debugMobileOverride = null);

    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    expect(find.text('Local order book'), findsOneWidget);
    expect(find.text('3 open routes'), findsOneWidget);
    expect(find.text('Testnet'), findsOneWidget);
    expect(find.text('New offer'), findsOneWidget);
    expect(find.text('Maker posts; taker completes'), findsOneWidget);
    expect(find.text('Two-wallet test'), findsOneWidget);
    expect(find.textContaining('LOCAL ROUTING'), findsNothing);
    expect(find.textContaining('Trade across'), findsNothing);

    // The page's name is the phone page title, not a card heading.
    final title = tester.widget<Text>(find.text('LiquiDEX').first);
    expect(
      title.style?.fontSize,
      AppTypography.pageTitleOf(
        tester.element(find.text('LiquiDEX').first),
      ).fontSize,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('market keeps the same restrained hierarchy on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen());
    await tester.pumpAndSettle();

    final title = tester.widget<Text>(find.text('LiquiDEX').first);
    expect(title.style?.fontSize, AppTypography.pageTitle.fontSize);
    expect(find.text('Markets · 3'), findsOneWidget);
    // Venues are sentence-case quiet tags, never shouted.
    expect(find.text('HTLC demo'), findsNWidgets(2));
    expect(find.text('HTLC DEMO'), findsNothing);
    // Exactly one filled accent control: "New offer".
    expect(find.byType(PrimaryButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
