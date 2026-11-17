// Joins a running Templar test server from Settings in the real desktop app,
// on the real engine (FfiWalletBridge, never the mock), with a throwaway
// wallet in a throwaway data directory, and checks that the wallet then
// receives on the lab's chains: bcrt1… on Bitcoin, el1… on Liquid.
//
// Opt-in; it needs a lab (templar-testlab `up`) and skips without its URL:
//
//   flutter test integration_test/testlab_join_test.dart -d macos \
//     --dart-define=TESTLAB_URL=http://127.0.0.1:8096
//
// The data directory is a fresh folder in the app's temp directory (inside
// the sandbox container on macOS), handed to the engine before its first
// call; no wallet of an existing install is opened. The app's preferences
// (SharedPreferences) are the bundle's own, so on a Mac that also runs a real
// install, build under a temporary PRODUCT_BUNDLE_IDENTIFIER
// (macos/Runner/Configs/AppInfo.xcconfig, not committed) to keep those apart
// too. The window must be in front: a hidden Flutter window draws no frames.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/router.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/ffi_wallet_bridge.dart';
import 'package:templar_wallet/features/wallet_picker/wallet_picker_screen.dart';
import 'package:templar_wallet/main.dart';

const String _labUrl = String.fromEnvironment('TESTLAB_URL');

Future<void> _wait(WidgetTester tester, [int ms = 700]) async {
  for (var i = 0; i < (ms / 100).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] matches, for engine calls that take a while.
Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  int seconds = 60,
}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  final onScreen = find
      .byWidgetPredicate((w) => _shown(w) != null)
      .evaluate()
      .map((e) => _shown(e.widget)!)
      .where((t) => t.trim().isNotEmpty)
      .take(60)
      .join(' | ');
  fail('timed out waiting for $finder; on screen: $onScreen');
}

/// The text a widget shows: plain, rich, or selectable (addresses are
/// selectable).
String? _shown(Widget w) => switch (w) {
  RichText() => w.text.toPlainText(),
  SelectableText() => w.data ?? w.textSpan?.toPlainText(),
  EditableText() => w.controller.text,
  _ => null,
};

/// Any shown text containing [part].
Finder _textContaining(String part) =>
    find.byWidgetPredicate((w) => _shown(w)?.contains(part) ?? false);

String _firstText(String part) =>
    _shown(_textContaining(part).evaluate().first.widget)!;

/// The wallet's row in the picker (the closing shell's header names it too).
final _inPicker = find.descendant(
  of: find.byType(WalletPickerScreen),
  matching: find.text('Testlab throwaway'),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'join a test server from Settings',
    skip: _labUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 6)),
    (tester) async {
      // Settings › Network & Sync carries an older SwitchListTile on a
      // coloured card, which trips a debug-only ListTile ink assertion that
      // has nothing to do with this flow; everything else still fails.
      final reportError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains(
          'ListTile background color or ink splashes may be invisible',
        )) {
          return;
        }
        reportError?.call(details);
      };
      addTearDown(() => FlutterError.onError = reportError);

      // A throwaway data directory, set before the engine's first call.
      final dataDir = Directory(
        '${Directory.systemTemp.path}/templar-testlab-'
        '${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
      expect(FfiWalletBridge.setDataDir(dataDir.path), 0);
      debugPrint('TESTLAB data dir ${dataDir.path}');

      // The real engine, not the debug fallback.
      expect(
        isMockBridge,
        isFalse,
        reason: 'bridge: ${walletBridge.runtimeType}',
      );
      expect(walletBridge, isA<FfiWalletBridge>());

      // A throwaway vault and wallet (Bitcoin + Liquid).
      debugPrint('TESTLAB step: vault');
      await walletBridge.setupVault('testlab-throwaway-passphrase');
      debugPrint('TESTLAB step: wallet');
      final words = await walletBridge.generateMnemonic(12);
      await walletBridge.createWallet('Testlab throwaway', words, liquid: true);

      debugPrint('TESTLAB step: app state');
      final appState = AppState();
      await appState.loadPrefs();
      appState.setLiquidNetworkInfo(await walletBridge.getLiquidNetwork());
      appState.setTestServerInfo(await walletBridge.getTestServer());
      expect(appState.liquidNetwork!.shortName, 'testnet');
      expect(appState.isBitcoinRegtest, isFalse);

      debugPrint('TESTLAB step: pump app');
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(2560, 1800);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appState,
          child: const TemplarWalletApp(),
        ),
      );
      await _wait(tester, 2500);

      // Settings lives inside a wallet: open the throwaway wallet first.
      debugPrint('TESTLAB step: open wallet');
      appRouter.go(AppRoutes.walletPicker);
      await _until(tester, _inPicker);
      await tester.tap(_inPicker.first);
      await _wait(tester, 3000);
      expect(appState.activeWalletId, isNotNull);

      // Settings › Network & Sync › Test server.
      debugPrint('TESTLAB step: settings');
      appRouter.go(AppRoutes.settingsNetwork);
      await _until(tester, find.byKey(const Key('test-server-url')));
      await tester.enterText(find.byKey(const Key('test-server-url')), _labUrl);
      await _wait(tester, 300);
      await tester.ensureVisible(find.text('Join'));
      await tester.tap(find.text('Join'));
      await _until(tester, find.text('Join this test server?'));
      debugPrint('TESTLAB confirmation shown');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Join').last);
      await _until(tester, find.textContaining('Joined '));
      debugPrint('TESTLAB ${_firstText('Joined ')}');

      // The engine switched Liquid to the lab's regtest, Bitcoin with it.
      expect(appState.liquidNetwork!.shortName, 'regtest');
      expect(appState.liquidNetwork!.testServer, isNotNull);
      expect(appState.isBitcoinRegtest, isTrue);
      final active = appState.testServer!.active;
      debugPrint(
        'TESTLAB joined ${appState.testServerName}; '
        'liquid ${active.liquid.network} ${active.liquid.backendDescription} '
        '(${active.liquid.backendSource}); '
        'bitcoin ${active.bitcoin.network} ${active.bitcoin.electrumUrl} '
        '(${active.bitcoin.source}); '
        'orderbook ${active.orderbook.origin.url} '
        '(${active.orderbook.origin.source})',
      );
      // Joining closed the wallet and went back to the picker: reopen it at
      // once, mid-transition, as a quick tester would (the picker waits for
      // its transition before entering the wallet shell again).
      expect(appState.activeWalletId, isNull);
      await _until(tester, _inPicker);
      await tester.tap(_inPicker.first);
      await _wait(tester, 3000);
      expect(appState.activeWalletId, isNotNull);

      // Settings now names the server and lists what it put in use.
      appRouter.go(AppRoutes.settingsNetwork);
      await _until(tester, find.text('Templar testlab'));
      await _until(
        tester,
        _textContaining('Bitcoin regtest · from test server'),
      );
      expect(_textContaining('Order book · from test server'), findsWidgets);
      debugPrint('TESTLAB settings shows the joined server and its sources');

      appRouter.go(AppRoutes.receive);
      await _until(tester, _textContaining('bcrt1'));
      final btc = _firstText('bcrt1');
      debugPrint('TESTLAB bitcoin receive: $btc');
      expect(_textContaining('tb1q'), findsNothing);

      await tester.tap(find.text('Liquid').last);
      await _until(tester, _textContaining('el1'));
      final lbtc = _firstText('el1');
      debugPrint('TESTLAB liquid receive: $lbtc');
      expect(_textContaining('tlq1'), findsNothing);
    },
  );
}
