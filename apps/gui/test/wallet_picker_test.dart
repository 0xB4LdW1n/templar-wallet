// The wallet list is where the app is entered, and almost always to get back
// into the same wallet. So the cursor starts on the wallet opened last and
// Enter opens it; the arrows move the cursor; 1–9 open a row outright.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/features/wallet_picker/wallet_picker_screen.dart';
import 'package:templar_wallet/services/wallet_customization_store.dart';

/// The mock bridge lists three wallets: Primary (wallet-1), Treasury 2-of-3
/// (wallet-2) and Cold Storage (wallet-3).
Future<AppState> _open(WidgetTester t) async {
  t.view.physicalSize = const Size(1280, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final appState = AppState();
  final router = GoRouter(
    initialLocation: AppRoutes.walletPicker,
    routes: [
      GoRoute(
        path: AppRoutes.walletPicker,
        builder: (_, _) => const WalletPickerScreen(),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (_, _) => const Scaffold(body: Text('inside the wallet')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await t.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: appState,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  // The mock answers after a short delay; the spinner keeps frames coming
  // until it does.
  await t.pump(const Duration(milliseconds: 600));
  await t.pumpAndSettle();
  return appState;
}

String _opened(Duration ago) => json.encode({
  'opened_at': DateTime.now().subtract(ago).millisecondsSinceEpoch,
});

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the wallets are rows of one register, in a stable order', (
    t,
  ) async {
    await _open(t);
    final names = ['Primary', 'Treasury 2-of-3', 'Cold Storage'];
    for (final n in names) {
      expect(find.text(n), findsOneWidget);
    }
    final tops = [for (final n in names) t.getTopLeft(find.text(n)).dy];
    expect(tops[0], lessThan(tops[1]));
    expect(tops[1], lessThan(tops[2]));
    // Names start on one line: a column to scan, not a grid to search.
    final lefts = {for (final n in names) t.getTopLeft(find.text(n)).dx};
    expect(lefts, hasLength(1));
    expect(t.takeException(), isNull);
  });

  testWidgets('Enter opens the wallet opened last', (t) async {
    SharedPreferences.setMockInitialValues({
      'wallet_custom_v1_wallet-1': _opened(const Duration(days: 3)),
      'wallet_custom_v1_wallet-2': _opened(const Duration(hours: 2)),
    });
    final appState = await _open(t);
    // It says which one that is, on its row.
    expect(find.textContaining('Last opened'), findsOneWidget);
    expect(
      t.getTopLeft(find.textContaining('Last opened')).dy,
      greaterThan(t.getTopLeft(find.text('Treasury 2-of-3')).dy),
    );

    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(appState.activeWalletId, 'wallet-2');
    expect(find.text('inside the wallet'), findsOneWidget);
  });

  testWidgets('with no wallet opened yet the cursor is on the first row', (
    t,
  ) async {
    final appState = await _open(t);
    expect(find.textContaining('Last opened'), findsNothing);
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(appState.activeWalletId, 'wallet-1');
  });

  testWidgets('the arrows move the cursor and stop at the ends', (t) async {
    final appState = await _open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await t.pumpAndSettle();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    await t.pumpAndSettle();
    expect(appState.activeWalletId, 'wallet-3');
  });

  testWidgets('a digit opens the row that carries it', (t) async {
    final appState = await _open(t);
    await t.sendKeyEvent(LogicalKeyboardKey.digit2);
    await t.pumpAndSettle();
    expect(appState.activeWalletId, 'wallet-2');
  });

  testWidgets('a click opens the row it lands on', (t) async {
    final appState = await _open(t);
    await t.tap(find.text('Cold Storage'));
    await t.pumpAndSettle();
    expect(appState.activeWalletId, 'wallet-3');
  });

  test('stamping a wallet as opened keeps what was saved for it', () async {
    SharedPreferences.setMockInitialValues({
      'wallet_custom_v1_w': json.encode({'name': 'Vault', 'color': 0xFF3B82F6}),
    });
    final store = WalletCustomizationStore.instance;
    await store.markOpened('w');
    final c = await store.load('w');
    expect(c.nameOverride, 'Vault');
    expect(c.accentColor, 0xFF3B82F6);
    expect(c.lastOpenedAt, isNotNull);
  });
}
