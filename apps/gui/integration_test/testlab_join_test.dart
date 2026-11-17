// Joins a running Templar test server from Settings in the real desktop app,
// on the real engine (FfiWalletBridge, never the mock), with a throwaway
// wallet in a throwaway data directory; then, through the app's own
// screens: the Test server card says what the lab provides, the Dashboard
// offers the faucet's coins, BTC and L-BTC are asked for there and show in
// the balance after the lab's next block, Receive hands out the lab's
// addresses (bcrt1… / el1…), and Loans offers the lab's lending site.
//
// Opt-in; it needs a lab (templar-testlab `up`) and skips without its URL.
// Run it ONLY like this, so a real install's vault is never opened (its own
// sandbox container through the bundle id override; the window must be in
// front):
//
//   FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=dev.templarwallet.testlabverify \
//   flutter test integration_test/testlab_join_test.dart -d macos \
//     --dart-define=TESTLAB_URL=http://127.0.0.1:8196 \
//     [--dart-define=GUIDE_SHOTS_DIR=/absolute/dir]
//
// NOT through the GUI, on purpose: the throwaway vault and wallet (the
// bridge; the recovery phrase is never on screen), and the balances read
// for the log and the assertions (the bridge).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/router.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/ffi_wallet_bridge.dart';
import 'package:templar_wallet/features/test_coins/test_coins.dart';
import 'package:templar_wallet/features/wallet_picker/wallet_picker_screen.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';

import 'testlab_support.dart';

const _passphrase = 'testlab-throwaway-passphrase';
const _wallet = 'Testlab throwaway';

/// The wallet's row in the picker (the closing shell's header names it too).
final _inPicker = find.descendant(
  of: find.byType(WalletPickerScreen),
  matching: find.text(_wallet),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'join a test server from Settings, get test coins, receive on the lab',
    skip: labUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 10)),
    (tester) async {
      ignoreInkAssertion();

      // A throwaway data directory, set before the engine's first call.
      final dataDir = throwawayDataDir('templar-testlab');
      expect(FfiWalletBridge.setDataDir(dataDir), 0);
      debugPrint('TESTLAB data dir $dataDir');

      // The real engine, not the debug fallback.
      expect(
        isMockBridge,
        isFalse,
        reason: 'bridge: ${walletBridge.runtimeType}',
      );
      expect(walletBridge, isA<FfiWalletBridge>());

      // A throwaway vault and wallet (Bitcoin + Liquid).
      await walletBridge.setupVault(_passphrase);
      final words = await walletBridge.generateMnemonic(12);
      final walletId = await walletBridge.createWallet(
        _wallet,
        words,
        liquid: true,
      );

      final appState = AppState();
      await appState.loadPrefs();
      appState.setLiquidNetworkInfo(await walletBridge.getLiquidNetwork());
      appState.setTestServerInfo(await walletBridge.getTestServer());
      expect(appState.liquidNetwork!.shortName, 'testnet');
      expect(appState.isBitcoinRegtest, isFalse);

      await pumpApp(tester, appState);

      // Settings lives inside a wallet: open the throwaway wallet first.
      appRouter.go(AppRoutes.walletPicker);
      await until(tester, _inPicker);
      await tester.tap(_inPicker.first);
      await wait(tester, 3000);
      expect(appState.activeWalletId, isNotNull);

      // ── Settings › Network › Nodes and explorers › Test server ──────────
      appRouter.go(AppRoutes.settingsNetwork);
      await until(tester, find.byKey(const Key('test-server-url')));
      await tester.enterText(find.byKey(const Key('test-server-url')), labUrl);
      await wait(tester, 300);
      await tester.ensureVisible(find.byKey(const Key('test-server-url')));
      await guideShot(tester, '01-join-test-server');
      await tester.ensureVisible(find.text('Join'));
      await tester.tap(find.text('Join'));
      await until(tester, find.text('Join this test server?'));
      await guideShot(tester, '02-join-confirm');
      await tester.tap(
        find.descendant(
          of: find.byType(PromptDialog),
          matching: find.text('Join'),
        ),
      );
      await until(tester, textContaining('Joined '));
      debugPrint('TESTLAB ${firstTextContaining('Joined ')}');

      // The engine switched Liquid to the lab's regtest, Bitcoin with it.
      expect(appState.liquidNetwork!.shortName, 'regtest');
      expect(appState.isBitcoinRegtest, isTrue);
      expect(appState.testServer!.faucetAvailable, isTrue);
      final lab = appState.testServerName!;
      debugPrint(
        'TESTLAB joined $lab; faucet pays '
        '${appState.testServer!.faucet!.assets.map((a) => a.ticker).join(', ')}; '
        'lending site ${appState.testServer!.protocolUrl}',
      );
      // Joining closed the wallet and went back to the picker: reopen it.
      expect(appState.activeWalletId, isNull);
      await until(tester, _inPicker);
      await tester.tap(_inPicker.first);
      await wait(tester, 3000);
      expect(appState.activeWalletId, walletId);

      // The card now says what the lab provides.
      appRouter.go(AppRoutes.settingsNetwork);
      await until(tester, find.byKey(const Key('test-server-faucet')));
      await until(tester, textContaining('Bitcoin regtest · from test server'));
      // The card from its head: the server's name, then what it provides.
      await Scrollable.ensureVisible(
        tester.element(find.text(lab).first),
        alignment: 0.05,
      );
      await wait(tester, 500);
      expect(textContaining('Pays BTC, L-BTC'), findsWidgets);
      expect(find.byKey(const Key('test-server-lending')), findsOneWidget);
      await guideShot(tester, '03-test-server-joined');

      // ── Dashboard: the faucet's coins, one action each ──────────────────
      appRouter.go(AppRoutes.dashboard);
      await until(tester, find.byKey(const Key('test-coins-card')));
      await guideShot(tester, '04-dashboard-regtest-strip');
      await tester.ensureVisible(find.byKey(const Key('test-coins-card')));
      expect(find.text('Get BTC'), findsOneWidget);
      expect(find.text('Get L-BTC'), findsOneWidget);
      await guideShot(tester, '05-dashboard-test-coins');

      await tapText(tester, 'Get BTC');
      await until(tester, textContaining('BTC on its way'), seconds: 40);
      await tapText(tester, 'Get L-BTC');
      await until(tester, textContaining('L-BTC on its way'), seconds: 40);
      await tester.ensureVisible(find.byKey(const Key('test-coins-card')));
      await guideShot(tester, '06-faucet-success');
      debugPrint(
        'TESTLAB faucet: ${firstTextContaining('BTC on its way')} / '
        '${firstTextContaining('L-BTC on its way')}',
      );

      // The app syncs once after the lab's next block by itself; nothing
      // is tapped here. The balance then shows on the Dashboard.
      final sw = Stopwatch()..start();
      for (var i = 0; i < 900; i++) {
        if (appState.syncVersion > 0 &&
            appState.syncState != SyncState.syncing &&
            sw.elapsed > TestCoins.syncDelay) {
          break;
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      debugPrint(
        'TESTLAB the app synced by itself after ${sw.elapsed.inSeconds} s '
        '(${appState.syncState})',
      );
      final b = await balances(
        walletId,
        ok: (m) => (m['BTC'] ?? 0) > 0 && (m['LBTC'] ?? 0) > 0,
      );
      debugPrint('TESTLAB balances: BTC ${b['BTC']} sat, L-BTC ${b['LBTC']}');
      expect(b['BTC'], greaterThan(0));
      expect(b['LBTC'], greaterThan(0));
      appRouter.go(AppRoutes.receive);
      await wait(tester, 800);
      appRouter.go(AppRoutes.dashboard);
      await until(tester, textContaining('0.01000000'), seconds: 60);
      await guideShot(tester, '07-dashboard-balances');

      // ── Receive: the lab's addresses ────────────────────────────────────
      appRouter.go(AppRoutes.receive);
      await until(tester, textContaining('bcrt1'));
      debugPrint('TESTLAB bitcoin receive: ${firstTextContaining('bcrt1')}');
      expect(textContaining('tb1q'), findsNothing);
      await guideShot(tester, '08-receive-btc');

      await tester.tap(find.text('Liquid').last);
      await until(tester, textContaining('el1'));
      debugPrint('TESTLAB liquid receive: ${firstTextContaining('el1')}');
      expect(textContaining('tlq1'), findsNothing);
      expect(find.text('Get test L-BTC'), findsOneWidget);
      await guideShot(tester, '09-receive-lbtc');

      // ── Loans: the lab's lending site ───────────────────────────────────
      await enableFeature(tester, 'advanced-loans');
      appRouter.go(AppRoutes.loans);
      await until(tester, find.byKey(const Key('loans-open-lending-site')));
      await guideShot(tester, '10-loans-lending-site');
      appRouter.go(AppRoutes.settingsProtocol);
      await until(tester, find.byKey(const Key('protocol-lab-lending-site')));
      await guideShot(tester, '11-protocol-lending-site');
    },
  );
}
