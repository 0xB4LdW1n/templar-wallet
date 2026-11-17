// A native peg-in and peg-out through the Peg screen of the real desktop app,
// on the real engine, against a running Templar test server — starting from
// a wallet with NO coins: the form shows its balances; funding the peg-in
// is refused as "Not enough BTC" with the faucet's BTC beside the refusal;
// that action pays the wallet; funding again works; then confirmations,
// claim, completed; then a peg-out of the claimed L-BTC to completion.
//
// Opt-in; it needs a lab with its native peg and skips without its URL.
// Run it ONLY like this (own sandbox container; window in front):
//
//   FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=dev.templarwallet.testlabverify \
//   flutter test integration_test/testlab_peg_test.dart -d macos \
//     --dart-define=TESTLAB_URL=http://127.0.0.1:8196 \
//     [--dart-define=GUIDE_SHOTS_DIR=/absolute/dir]
//
// NOT through the GUI, on purpose: joining the lab (testlab_join_test.dart
// does it through Settings; here the bridge), the throwaway vault and
// wallet, mining blocks (the lab's admin API on loopback — the lab
// operator's tool, so the run does not wait ten minutes per block), and
// reading balances and order fields for the log (the bridge). Every peg
// step and the faucet are taps in the app, through the confirmation and the
// password gate where something is signed.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/router.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/ffi_wallet_bridge.dart';
import 'package:templar_wallet/features/peg/models/peg_models.dart';

import 'testlab_support.dart';

const _passphrase = 'testlab-peg-throwaway-passphrase';
const _wallet = 'Peg throwaway';

Future<PegOrder> _order(String walletId, String id) async =>
    (await walletBridge.pegList(walletId)).firstWhere((o) => o.orderId == id);

/// Mines with [between], taps the screen's Refresh, and repeats until the
/// order has reached [status].
Future<void> _refreshUntil(
  WidgetTester tester,
  String walletId,
  String orderId,
  String status, {
  Future<void> Function()? between,
  int tries = 30,
}) async {
  for (var i = 0; i < tries; i++) {
    if (between != null) await between();
    await wait(tester, 2500);
    final refresh = find.byTooltip('Refresh');
    if (refresh.evaluate().isNotEmpty) await tester.tap(refresh.first);
    await wait(tester, 3000);
    if ((await _order(walletId, orderId)).status == status) {
      await wait(tester, 3000);
      return;
    }
  }
  fail('the order never reached "$status"');
}

Future<void> _tapRefresh(WidgetTester tester) async {
  await until(tester, find.byTooltip('Refresh'));
  await tester.tap(find.byTooltip('Refresh').first);
  await wait(tester, 3000);
}

/// What will be signed, then the app password.
Future<void> _confirmAndSign(WidgetTester tester, {String? shot}) async {
  await until(tester, find.text('Continue'));
  await tapInDialog(tester, 'Continue');
  await passGate(tester, _passphrase, shot: shot);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'peg-in funded from the in-wallet faucet, then a peg-out',
    skip: labUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 20)),
    (tester) async {
      ignoreInkAssertion();
      final dataDir = throwawayDataDir('templar-peg');
      expect(FfiWalletBridge.setDataDir(dataDir), 0);
      expect(walletBridge, isA<FfiWalletBridge>());
      debugPrint('PEG data dir $dataDir');

      await walletBridge.setupVault(_passphrase);
      final joined = await walletBridge.setTestServer(labUrl);
      expect(joined.active.bitcoin.isRegtest, isTrue);
      final walletId = await walletBridge.createWallet(
        _wallet,
        await walletBridge.generateMnemonic(12),
        liquid: true,
      );
      final start = await balances(walletId);
      debugPrint('PEG start: $start');
      expect(start['BTC'] ?? 0, 0);

      final appState = AppState();
      await appState.loadPrefs();
      appState.setLiquidNetworkInfo(await walletBridge.getLiquidNetwork());
      appState.setTestServerInfo(await walletBridge.getTestServer());
      expect(appState.liquidNetwork!.pegProvider, 'native');

      await pumpApp(tester, appState);
      await openWallet(tester, _wallet);
      await enableFeature(tester, 'advanced-peg');

      // ── Peg-in: the form, with this wallet's balances ──────────────────
      appRouter.go(AppRoutes.peg);
      await until(tester, textContaining('Native peg'));
      await until(tester, find.byKey(const Key('peg-balances')));
      await tester.enterText(find.byType(TextField).first, '0.005');
      await until(tester, find.text('2 Bitcoin confirmations'));
      await wait(tester, 1500); // the payout address prefill
      expect(textContaining('In this wallet: 0.00000000 BTC'), findsWidgets);
      await guideShot(tester, '20-peg-in-form');
      await tapText(tester, 'Start peg-in');
      await until(tester, find.text('Fund from this wallet'));
      final pegIn = (await walletBridge.pegList(walletId)).first;
      debugPrint(
        'PEG in ${pegIn.orderId}: deposit ${pegIn.depositAddress} '
        '(valid through Liquid ${pegIn.validUntilLiquidHeight})',
      );
      await tester.ensureVisible(find.text('Fund from this wallet'));
      await guideShot(tester, '21-peg-in-awaiting-deposit');

      // ── Funding with no BTC: the refusal and the faucet beside it ──────
      await tapText(tester, 'Fund from this wallet');
      await _confirmAndSign(tester, shot: '22-peg-password-gate');
      await until(tester, find.text('Not enough BTC'));
      debugPrint('PEG refusal: ${firstTextContaining('sat of BTC on')}');
      expect(textContaining('Transaction build failed'), findsNothing);
      await tester.ensureVisible(find.text('Get test BTC'));
      await guideShot(tester, '23-peg-insufficient-funds');
      await tapText(tester, 'Get test BTC');
      await until(tester, textContaining('BTC on its way'), seconds: 40);
      debugPrint('PEG faucet: ${firstTextContaining('BTC on its way')}');
      await guideShot(tester, '24-peg-faucet-btc');

      // The lab confirms the faucet's payment in its next block; mined here
      // so the run does not wait for the lab's own timer.
      await mine('bitcoin');
      final funded = await balances(walletId, ok: (m) => (m['BTC'] ?? 0) > 0);
      debugPrint('PEG after the faucet: BTC ${funded['BTC']} sat');
      expect(funded['BTC'], greaterThan(500000));
      // The screen's balances follow the app's own sync (35 s after the
      // faucet), so the next tap waits for it.
      await until(
        tester,
        textContaining('In this wallet: 0.01000000 BTC'),
        seconds: 90,
      );

      // ── Fund again: it goes through ────────────────────────────────────
      await tapText(tester, 'Fund from this wallet');
      await _confirmAndSign(tester);
      await until(tester, textContaining('Deposit sent'));
      debugPrint(
        'PEG in deposit tx '
        '${(await _order(walletId, pegIn.orderId)).txidDeposit}',
      );
      await _refreshUntil(
        tester,
        walletId,
        pegIn.orderId,
        'claimable',
        between: () => mine('bitcoin'),
      );
      await until(tester, find.text('Claim'));
      await tester.ensureVisible(find.text('Claim'));
      await guideShot(tester, '25-peg-in-ready-to-claim');
      await tapText(tester, 'Claim');
      await _confirmAndSign(tester);
      await until(tester, textContaining('Claim sent'));
      await _refreshUntil(
        tester,
        walletId,
        pegIn.orderId,
        'completed',
        between: () => mine('liquid'),
      );
      await _tapRefresh(tester);
      await until(tester, find.text('Completed'), atLeast: 2);
      final inDone = await _order(walletId, pegIn.orderId);
      debugPrint(
        'PEG in ${inDone.status}: deposit ${inDone.txidDeposit}, claim '
        '${inDone.txidClaim}, received ${inDone.payoutExpectedSats} sat',
      );
      expect(inDone.status, 'completed');
      await guideShot(tester, '26-peg-in-completed');
      final afterIn = await balances(walletId, ok: (m) => (m['LBTC'] ?? 0) > 0);
      debugPrint(
        'PEG after peg-in: BTC ${afterIn['BTC']} sat, L-BTC ${afterIn['LBTC']}',
      );

      // ── Peg-out of the claimed L-BTC ───────────────────────────────────
      await tapText(tester, 'Peg out');
      await wait(tester, 1500);
      await tester.enterText(find.byType(TextField).first, '0.002');
      await until(tester, find.text('2 Liquid confirmations'));
      await wait(tester, 1500);
      await guideShot(tester, '27-peg-out-form');
      await tapText(tester, 'Start peg-out');
      await until(tester, textContaining('no address to pay by hand'));
      final pegOut = (await walletBridge.pegList(walletId)).first;
      expect(pegOut.isPegIn, isFalse);
      await guideShot(tester, '28-peg-out-order');
      await tapText(tester, 'Fund from this wallet');
      await _confirmAndSign(tester);
      await until(tester, textContaining('Deposit sent'));
      debugPrint(
        'PEG out ${pegOut.orderId}: peg-out tx '
        '${(await _order(walletId, pegOut.orderId)).txidDeposit}',
      );
      await _refreshUntil(
        tester,
        walletId,
        pegOut.orderId,
        'completed',
        tries: 40,
        between: () async {
          final o = await _order(walletId, pegOut.orderId);
          await mine(o.status == 'settling' ? 'bitcoin' : 'liquid');
        },
      );
      await _tapRefresh(tester);
      await until(tester, find.text('Completed'), atLeast: 3);
      final outDone = await _order(walletId, pegOut.orderId);
      debugPrint(
        'PEG out ${outDone.status}: peg-out ${outDone.txidDeposit}, '
        'federation payment ${outDone.txidPayout}',
      );
      expect(outDone.status, 'completed');
      await guideShot(tester, '29-peg-out-completed');
      final end = await balances(
        walletId,
        ok: (m) => (m['BTC'] ?? 0) > (afterIn['BTC'] ?? 0),
      );
      debugPrint(
        'PEG after peg-out: BTC ${end['BTC']} sat, L-BTC ${end['LBTC']}',
      );
      expect(end['BTC'], greaterThan(afterIn['BTC'] ?? 0));
    },
  );
}
