// Issuing a token on a test server's regtest: no domain (the engine writes
// its reserved default), the supply typed in the token's own units and
// shown in base units before signing, the password before the issuance is
// signed, and a result that says whether the lab's order book took the
// name — with a retry when it did not. On Liquid testnet the domain stays.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/liquid/issue_screen.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';

MockWalletBridge get _mock => walletBridge as MockWalletBridge;

Future<AppState> _state({required bool lab}) async {
  if (lab) {
    await _mock.setTestServer('http://127.0.0.1:8196');
  } else {
    await _mock.clearTestServer();
  }
  return AppState()
    ..setActiveWallet(
      'wallet-1',
      name: 'Primary',
      type: 'Software',
      liquid: true,
    )
    ..setLiquidNetworkInfo(await _mock.getLiquidNetwork())
    ..setTestServerInfo(await _mock.getTestServer());
}

Future<void> _pump(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1280, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: const MaterialApp(home: IssueScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

Future<void> _define(WidgetTester tester) async {
  await tester.enterText(_field('Token name'), 'Templar Token');
  await tester.enterText(_field('Ticker'), 'TMPL');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> _issue(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('issue-supply')), '10000.00');
  await tester.pump();
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Issue asset'));
  await tester.pumpAndSettle();
  expect(find.text('Confirm with your app password'), findsOneWidget);
  await tester.enterText(
    find.descendant(
      of: find.byType(PromptDialog),
      matching: find.byType(TextField),
    ),
    'app password',
  );
  await tester.tap(
    find.descendant(of: find.byType(PromptDialog), matching: find.text('Sign')),
  );
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _mock.mockBookRegisterError = null;
    _mock.lastIssue = null;
  });
  tearDown(() async => _mock.clearTestServer());

  testWidgets('on a lab: no domain, the book named it, no domain proof', (
    tester,
  ) async {
    await _pump(tester, (await tester.runAsync(() => _state(lab: true)))!);

    expect(find.text('Domain'), findsNothing);
    expect(find.textContaining('no domain is needed'), findsOneWidget);
    expect(
      find.textContaining('order book lists a ticker of 3–16'),
      findsOneWidget,
    );
    // Two decimals by default, not eight.
    final precision = tester.widget<TextField>(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == '2',
      ),
    );
    expect(precision.controller!.text, '2');

    await _define(tester);
    expect(find.text('Initial supply'), findsWidgets);
    await tester.enterText(find.byKey(const Key('issue-supply')), '10000.00');
    await tester.pump();
    expect(find.textContaining('= 1,000,000 base units'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    // The review says what is signed, in both units.
    expect(find.text('10,000.00 TMPL'), findsOneWidget);
    expect(find.text('1,000,000 base units'), findsOneWidget);
    expect(find.text('Domain'), findsNothing);
    await tester.tap(find.text('Back').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await _issue(tester);
    expect(_mock.lastIssue!['amount_sats'], 1000000);
    expect(_mock.lastIssue!['precision'], 2);
    expect(_mock.lastIssue!['domain'], isNull);
    expect(find.text('Named on the order book'), findsOneWidget);
    expect(find.text('Domain proof required'), findsNothing);
    expect(find.text('Register again'), findsNothing);
  });

  testWidgets('supply with more decimals than the precision is refused', (
    tester,
  ) async {
    await _pump(tester, (await tester.runAsync(() => _state(lab: true)))!);
    await _define(tester);
    await tester.enterText(find.byKey(const Key('issue-supply')), '1.001');
    await tester.pump();
    expect(find.text('TMPL has 2 decimals at most'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('TMPL has 2 decimals at most.'), findsOneWidget);
    expect(find.text('Review and sign'), findsNothing);
  });

  testWidgets('the book refused the name: the reason and a retry', (
    tester,
  ) async {
    _mock.mockBookRegisterError = 'the ticker TMPL is taken';
    await _pump(tester, (await tester.runAsync(() => _state(lab: true)))!);
    await _define(tester);
    await _issue(tester);
    expect(find.text('Not named on the order book'), findsOneWidget);
    expect(find.textContaining('the ticker TMPL is taken'), findsOneWidget);

    _mock.mockBookRegisterError = null;
    await tester.tap(find.text('Try again'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Named on the order book'), findsOneWidget);
    expect(find.text('Not named on the order book'), findsNothing);
  });

  testWidgets('on Liquid testnet the domain is still asked for', (
    tester,
  ) async {
    await _pump(tester, (await tester.runAsync(() => _state(lab: false)))!);
    expect(find.text('Domain'), findsOneWidget);
    expect(find.textContaining('no domain is needed'), findsNothing);
  });
}
