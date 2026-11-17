// LiquiDEX signs with this wallet's key when it takes an offer (and when it
// makes or cancels one): nothing is signed without the app password, as in
// Send. A dismissed gate takes nothing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/swap/take_flow.dart';

AppState _state({String type = 'Software'}) => AppState()
  ..setActiveWallet('wallet-1', name: 'Primary', type: type, liquid: true)
  ..setLiquidNetworkInfo(
    const LiquidNetworkInfo(
      network: 'liquid-testnet',
      shortName: 'testnet',
      policyAsset:
          '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49',
      backend: 'electrum',
      backendDescription: 'test',
    ),
  );

Future<void> _toConfirm(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: TakeFlowScreen(proposalJson: '{}')),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Take swap'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sign and broadcast'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('taking asks for the app password; a dismissed gate takes '
      'nothing', (tester) async {
    await _toConfirm(tester, _state());

    expect(find.text('Confirm with your app password'), findsOneWidget);
    expect(find.textContaining('sign the swap'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    expect(find.text('Swap broadcast'), findsNothing);
    expect(find.text('Take swap'), findsOneWidget);
  });

  testWidgets('with the password, the swap is signed and broadcast', (
    tester,
  ) async {
    await _toConfirm(tester, _state());

    await tester.enterText(find.byType(TextField).last, 'app password');
    await tester.tap(find.text('Sign'));
    // The mock's broadcast takes a second.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Swap broadcast'), findsOneWidget);
    // The post-broadcast background sync of the mock.
    await tester.pump(const Duration(seconds: 10));
  });

  testWidgets('a hardware wallet approves on its device, not with the '
      'password', (tester) async {
    await _toConfirm(tester, _state(type: 'Hardware (Jade)'));

    expect(find.text('Confirm with your app password'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Swap broadcast'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });
}
