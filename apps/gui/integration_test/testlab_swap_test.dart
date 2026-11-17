// A token issued and sold, and the lab's USDt swapped, through the app's
// own screens on the real engine against a running Templar test server:
// two throwaway software wallets in one app, A the issuer and maker, B the
// buyer and taker. Everything they spend comes from the in-wallet faucet.
//
// 1. A and B get L-BTC (and A the lab's USDt) from Test coins on the
//    Dashboard.
// 2. A issues "Templar Token" (precision 2, supply 10000.00) on the Issue
//    screen: no domain, the order book names it.
// 3. A makes an exact coin of 100.00 of it and offers it for 0.05 L-BTC
//    (New offer: coin, want, review, sign, publish).
// 4. B finds the offer in the market under the token's ticker and 100.00,
//    checks, reviews and takes it, and holds 100.00 of it after the block.
// 5. A offers its 100 USDt for L-BTC; B takes it.
//
// The ticker: the lab's order book keeps one asset per ticker, and `TMPL`
// is already registered on a lab that has been used before (the book then
// refuses the name — the refusal and its retry are covered by
// test/issue_on_lab_test.dart). So the run issues `TMPL` followed by four
// digits of its own, e.g. `TMPL4821`, which the book names.
//
// Opt-in; it needs a lab with its order book and faucet and skips without
// its URL. Run it ONLY like this (own sandbox container; window in front):
//
//   FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=dev.templarwallet.testlabverify \
//   flutter test integration_test/testlab_swap_test.dart -d macos \
//     --dart-define=TESTLAB_URL=http://127.0.0.1:8196 \
//     [--dart-define=GUIDE_SHOTS_DIR=/absolute/dir]
//
// NOT through the GUI, on purpose: joining the lab (testlab_join_test.dart
// does it through Settings; here the bridge), the throwaway vault and
// wallets, mining a block after each step (the lab's admin API — so the
// run does not wait for the lab's own timer), and reading balances for the
// log and the assertions (the bridge).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/router.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/ffi_wallet_bridge.dart';
import 'package:templar_wallet/features/liquid/form_parts.dart';
import 'package:templar_wallet/features/test_coins/test_coins.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';
import 'package:templar_wallet/shared/widgets/buttons.dart';
import 'package:templar_wallet/shared/widgets/code_box.dart';
import 'package:templar_wallet/shared/widgets/utxo_views.dart';

import 'testlab_support.dart';

const _passphrase = 'testlab-swap-throwaway-passphrase';
const _maker = 'Token issuer';
const _taker = 'Token buyer';

final _run = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;

/// On a lab whose order book has no `TMPL` yet (a fresh chain), pass
/// `--dart-define=TESTLAB_TICKER=TMPL` to issue the plain ticker.
const _tickerOverride = String.fromEnvironment('TESTLAB_TICKER');
final _ticker = _tickerOverride.isNotEmpty ? _tickerOverride : 'TMPL$_run';

/// L-BTC asked for the lab's USDt: unique to this run, so the market row is
/// this run's.
final _usdtWant = '0.0010$_run';

/// The TextField under a form label.
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(FieldBlock)),
  matching: find.byType(TextField),
);

/// A coin of [assetId] in the offer step's picker (list rows or notes),
/// of exactly [amount] base units when given.
Finder _coin(String assetId, {int? amount}) => find.byWidgetPredicate((w) {
  final utxo = switch (w) {
    CoinRow() => w.utxo,
    UtxoBanknote() => w.utxo,
    _ => null,
  };
  return utxo != null &&
      utxo.assetId == assetId &&
      (amount == null || utxo.amount == amount);
});

/// Taps a faucet coin's action [times] times, each after the last answered.
Future<void> _faucet(
  WidgetTester tester,
  AppState state,
  String label,
  String asset, {
  int times = 1,
}) async {
  final coin = testCoinsFor(state).firstWhere((a) => a.asset == asset);
  for (var i = 0; i < times; i++) {
    await tapText(tester, label);
    for (var j = 0; j < 400; j++) {
      final r = TestCoins.instance.requestOf(state.activeWalletId, coin);
      if (r != null && !r.busy) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    final r = TestCoins.instance.requestOf(state.activeWalletId, coin);
    if (r?.payment == null) fail('faucet $asset: ${r?.error?.message}');
    debugPrint('SWAP faucet $asset: ${r!.payment!.txid}');
  }
}

/// The make flow from the coin already picked: wanted L-BTC, review, sign,
/// publish. Returns the order book's id.
Future<int> _wantSignPublish(
  WidgetTester tester,
  String want, {
  String? shots,
}) async {
  await tapText(tester, 'Continue');
  await tapOn(tester, find.byType(DropdownButtonFormField<String>));
  await tapOn(tester, find.text('LBTC').last);
  await tester.enterText(find.byKey(const Key('want-amount')), want);
  await wait(tester, 600);
  if (shots != null) await guideShot(tester, '$shots-want');
  await tapText(tester, 'Continue');
  if (shots != null) await guideShot(tester, '$shots-review');
  await tapText(tester, 'Sign and create offer');
  await passGate(tester, _passphrase);
  await until(tester, find.text('Offer created'));
  if (shots != null) await guideShot(tester, '$shots-created');
  await tapOn(
    tester,
    find.descendant(of: find.byType(AppDialog), matching: find.text('Publish')),
  );
  await until(tester, textContaining('Published as order #'));
  if (shots != null) await guideShot(tester, '$shots-published');
  final text = firstTextContaining('Published as order #');
  final id = int.parse(RegExp(r'#(\d+)').firstMatch(text)!.group(1)!);
  await tapText(tester, 'Done');
  await wait(tester, 1500);
  return id;
}

/// B takes the market row [row]: check, review, sign.
Future<String> _take(WidgetTester tester, Finder row, {String? shots}) async {
  appRouter.go(AppRoutes.swap);
  await until(tester, row, seconds: 120);
  if (shots != null) {
    await tester.ensureVisible(row.first);
    await guideShot(tester, '$shots-market');
  }
  await tapOn(tester, row);
  if (shots != null) await guideShot(tester, '$shots-offer');
  await tapText(tester, 'Review and take');
  final cont = find.widgetWithText(PrimaryButton, 'Continue');
  await until(tester, cont);
  for (var i = 0; i < 300; i++) {
    if (tester.widget<PrimaryButton>(cont).onPressed != null) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (shots != null) await guideShot(tester, '$shots-check');
  await tapOn(tester, cont);
  final take = find.widgetWithText(PrimaryButton, 'Take swap');
  await until(tester, take);
  for (var i = 0; i < 300; i++) {
    if (tester.widget<PrimaryButton>(take).onPressed != null) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (shots != null) await guideShot(tester, '$shots-review');
  await tapOn(tester, take);
  await tapText(tester, 'Sign and broadcast');
  await passGate(tester, _passphrase);
  await until(tester, find.text('Swap broadcast'));
  if (shots != null) await guideShot(tester, '$shots-broadcast');
  final txid = tester
      .widget<CodeBox>(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(CodeBox),
        ),
      )
      .value;
  await tapText(tester, 'Done');
  await wait(tester, 2000);
  return txid;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'issue a token and sell it, swap the lab USDt, all from the app',
    skip: labUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 25)),
    (tester) async {
      ignoreInkAssertion();
      final dataDir = throwawayDataDir('templar-swap');
      expect(FfiWalletBridge.setDataDir(dataDir), 0);
      expect(walletBridge, isA<FfiWalletBridge>());
      debugPrint('SWAP data dir $dataDir; token ticker $_ticker');

      await walletBridge.setupVault(_passphrase);
      await walletBridge.setTestServer(labUrl);
      final a = await walletBridge.createWallet(
        _maker,
        await walletBridge.generateMnemonic(12),
        liquid: true,
      );
      final b = await walletBridge.createWallet(
        _taker,
        await walletBridge.generateMnemonic(12),
        liquid: true,
      );

      final appState = AppState();
      await appState.loadPrefs();
      appState.setLiquidNetworkInfo(await walletBridge.getLiquidNetwork());
      appState.setTestServerInfo(await walletBridge.getTestServer());
      final usdtId = appState.testServer!.faucet!.assets
          .firstWhere((x) => x.ticker.toUpperCase() == 'USDT')
          .assetId!;

      await pumpApp(tester, appState);

      // ── 1. Test coins from the Dashboard, for both wallets ──────────────
      await openWallet(tester, _maker);
      await enableFeature(tester, 'advanced-liquiddex');
      appRouter.go(AppRoutes.dashboard);
      await until(tester, find.byKey(const Key('test-coins-card')));
      await _faucet(tester, appState, 'Get L-BTC', 'lbtc');
      await _faucet(tester, appState, 'Get USDt', 'USDt');
      await openWallet(tester, _taker);
      appRouter.go(AppRoutes.dashboard);
      await until(tester, find.byKey(const Key('test-coins-card')));
      // 0.05 L-BTC for the token, the USDt's price and the fees.
      await _faucet(tester, appState, 'Get L-BTC', 'lbtc', times: 6);
      await mine('liquid');
      final aStart = await balances(
        a,
        ok: (m) => (m['LBTC'] ?? 0) > 0 && (m['USDT'] ?? 0) > 0,
      );
      final bStart = await balances(b, ok: (m) => (m['LBTC'] ?? 0) >= 6000000);
      debugPrint('SWAP start: A $aStart; B $bStart');
      expect(bStart['LBTC'], 6000000);

      // ── 2. A issues the token ───────────────────────────────────────────
      await openWallet(tester, _maker);
      appRouter.go(AppRoutes.issueAsset);
      await until(tester, find.text('Token name'));
      expect(find.text('Domain'), findsNothing);
      await tester.enterText(_field('Token name'), 'Templar Token');
      await tester.enterText(_field('Ticker'), _ticker);
      await wait(tester, 500);
      await guideShot(tester, '30-issue-define');
      await tapText(tester, 'Continue');
      await tester.enterText(find.byKey(const Key('issue-supply')), '10000.00');
      await wait(tester, 500);
      expect(textContaining('= 1,000,000 base units'), findsWidgets);
      await guideShot(tester, '31-issue-supply');
      await tapText(tester, 'Continue');
      expect(find.text('10,000.00 $_ticker'), findsWidgets);
      await guideShot(tester, '32-issue-review');
      await tapText(tester, 'Issue asset');
      await passGate(tester, _passphrase);
      await until(tester, find.text('Asset issued'), seconds: 120);
      await until(tester, find.text('Named on the order book'), seconds: 10);
      final tokenId = tester
          .widget<CodeBox>(
            find.ancestor(
              of: find.text('Asset ID'),
              matching: find.byType(CodeBox),
            ),
          )
          .value;
      debugPrint('SWAP issued $_ticker: $tokenId');
      await guideShot(tester, '33-issue-result');
      await tapText(tester, 'Done');
      await mine('liquid');
      await balances(a, ok: (m) => (m[_ticker] ?? 0) == 1000000);
      appRouter.go(AppRoutes.dashboard);
      await wait(tester, 1000);
      appRouter.go(AppRoutes.liquid);
      await until(tester, textContaining(_ticker), seconds: 60);
      await guideShot(tester, '34-liquid-assets');

      // ── 3. A: an exact coin of 100.00 and the offer ────────────────────
      appRouter.go(AppRoutes.swap);
      await until(tester, find.text('New offer'));
      expect(find.text('BTC routes'), findsNothing);
      await tapText(tester, 'New offer');
      expect(find.text('Choose settlement'), findsNothing);
      await tapText(tester, 'Create exact coin');
      await tapOn(tester, find.byType(DropdownButtonFormField<String>).first);
      await tapOn(tester, find.text(_ticker).last);
      await tester.enterText(
        find.byKey(const Key('exact-coin-amount')),
        '100.00',
      );
      await wait(tester, 500);
      expect(textContaining('= 10,000 base units'), findsWidgets);
      await guideShot(tester, '35-new-offer-exact-coin');
      await tapText(tester, 'Create coin');
      await passGate(tester, _passphrase);
      await mine('liquid');
      await until(tester, _coin(tokenId, amount: 10000), seconds: 120);
      await tapOn(tester, _coin(tokenId, amount: 10000));
      await guideShot(tester, '36-new-offer-coin');
      final tokenOffer = await _wantSignPublish(
        tester,
        '0.05',
        shots: '37-new-offer',
      );
      debugPrint('SWAP $_ticker offer published as #$tokenOffer');
      appRouter.go(AppRoutes.dashboard);
      await wait(tester, 800);
      appRouter.go(AppRoutes.swap);
      await until(tester, find.text('My swaps'));
      await until(tester, textContaining('→ 0.05000000 LBTC'), seconds: 60);
      await tester.ensureVisible(find.text('My swaps'));
      await guideShot(tester, '38-my-swaps');

      // ── 4. B takes it, seeing the ticker and 100.00 ─────────────────────
      await openWallet(tester, _taker);
      final tokenRow = textContaining('Receive 100.00 $_ticker');
      final takeTxid = await _take(tester, tokenRow, shots: '39-take');
      debugPrint('SWAP B took #$tokenOffer: $takeTxid');
      await mine('liquid');
      final bAfter = await balances(b, ok: (m) => (m[_ticker] ?? 0) == 10000);
      final aAfter = await balances(
        a,
        ok: (m) => (m['LBTC'] ?? 0) >= (aStart['LBTC'] ?? 0) + 5000000 - 1000,
      );
      debugPrint('SWAP after the take: A $aAfter; B $bAfter');
      expect(bAfter[_ticker], 10000);
      appRouter.go(AppRoutes.dashboard);
      await wait(tester, 800);
      appRouter.go(AppRoutes.liquid);
      await until(tester, textContaining('100.00'), seconds: 60);
      expect(textContaining(_ticker), findsWidgets);
      await guideShot(tester, '40-buyer-liquid-assets');

      // ── 5. The lab's USDt for L-BTC ─────────────────────────────────────
      await openWallet(tester, _maker);
      appRouter.go(AppRoutes.swap);
      await until(tester, find.text('New offer'));
      await tapText(tester, 'New offer');
      await tapOn(tester, _coin(usdtId));
      final usdtOffer = await _wantSignPublish(tester, _usdtWant);
      debugPrint('SWAP USDt offer published as #$usdtOffer for $_usdtWant');
      await openWallet(tester, _taker);
      final usdtTxid = await _take(
        tester,
        textContaining('Pay $_usdtWant'),
        shots: '41-usdt',
      );
      debugPrint('SWAP B took the USDt offer: $usdtTxid');
      await mine('liquid');
      final bEnd = await balances(b, ok: (m) => (m['USDT'] ?? 0) > 0);
      debugPrint('SWAP end: B $bEnd');
      expect(bEnd['USDT'], aStart['USDT']);
    },
  );
}
