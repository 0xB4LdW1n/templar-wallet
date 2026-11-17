// A native peg-in and peg-out through the Peg screen of the real desktop app,
// on the real engine, against a running Templar test server: start, fund
// (confirmation + app password), wait for confirmations, claim, completed.
//
// Opt-in; it needs a lab with its native peg and skips without its URL:
//
//   flutter test integration_test/testlab_peg_test.dart -d macos \
//     --dart-define=TESTLAB_URL=http://127.0.0.1:8096
//
// What is NOT driven through the GUI, on purpose: joining the lab (proven
// by testlab_join_test.dart; done here through the bridge), funding the
// throwaway wallet and mining blocks (the lab's admin API on loopback — a
// lab operator's tools, not the wallet's), and reading balances and order
// fields for the log (the bridge). Every peg step — start, fund, claim — is
// a tap in the app, through its confirmation and its password gate.
//
// Same isolation as testlab_join_test.dart: a fresh data directory, and a
// temporary bundle id when a real install shares the Mac. The window must be
// in front.

import 'dart:convert';
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
import 'package:templar_wallet/features/peg/models/peg_models.dart';
import 'package:templar_wallet/features/wallet_picker/wallet_picker_screen.dart';
import 'package:templar_wallet/main.dart';
import 'package:templar_wallet/shared/widgets/glass_dialog.dart';

const String _labUrl = String.fromEnvironment('TESTLAB_URL');
const _passphrase = 'testlab-peg-throwaway-passphrase';

Future<void> _wait(WidgetTester tester, [int ms = 700]) async {
  for (var i = 0; i < (ms / 100).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _until(
  WidgetTester tester,
  Finder finder, {
  int seconds = 90,
}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $finder');
}

/// The lab's admin API (open on loopback).
Future<Map<String, dynamic>> _admin(
  String path,
  Map<String, Object> body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$_labUrl/admin/api/$path'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) fail('admin $path: ${res.statusCode} $text');
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

Future<void> _mine(String chain, int blocks) =>
    _admin('mine', {'chain': chain, 'blocks': blocks});

/// (BTC, L-BTC) in sats after a sync; retried until [ok] holds (Electrum
/// servers index a new block a moment after it is mined).
Future<(int, int)> _balances(
  String walletId, {
  bool Function((int, int))? ok,
}) async {
  var last = (0, 0);
  for (var i = 0; i < 20; i++) {
    final sync = await walletBridge.syncWallet(walletId);
    final d = await walletBridge.getWalletSummary(walletId);
    int of(String t) =>
        d.assets.where((a) => a.ticker == t).fold(0, (n, a) => n + a.amount);
    last = (of('BTC'), of('LBTC'));
    if (ok == null || ok(last)) return last;
    if (i == 0) {
      debugPrint(
        'PEG waiting for the sync: $sync; assets '
        '${d.assets.map((a) => '${a.ticker}=${a.amount}').join(', ')}',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  return last;
}

Future<PegOrder> _order(String walletId, String id) async =>
    (await walletBridge.pegList(walletId)).firstWhere((o) => o.orderId == id);

/// Mines with [between], taps "Check the chains now" in the app, and repeats
/// until the order has reached [status] (the stepper names every step, so
/// the engine's answer is the gate; the screen is then checked for it).
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
    await _wait(tester, 2500);
    final refresh = find.byTooltip('Check the chains now');
    if (refresh.evaluate().isNotEmpty) {
      await tester.tap(refresh.first);
    }
    await _wait(tester, 3000);
    if ((await _order(walletId, orderId)).status == status) {
      await _wait(tester, 3000);
      return;
    }
  }
  fail('the order never reached "$status"');
}

/// Scrolls [label] into view, then taps it.
Future<void> _tapText(WidgetTester tester, String label) async {
  final f = find.text(label).first;
  await tester.ensureVisible(f);
  await _wait(tester, 400);
  await tester.tap(f);
  await _wait(tester, 600);
}

Future<void> _tapDialog(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(GlassDialog), matching: find.text(label)),
  );
  await _wait(tester, 800);
}

/// What will be signed, then the app password.
Future<void> _confirmAndSign(WidgetTester tester) async {
  await _until(tester, find.text('Continue'));
  await _tapDialog(tester, 'Continue');
  await _until(tester, find.text('Confirm with your app password'));
  await tester.enterText(
    find.descendant(
      of: find.byType(GlassDialog),
      matching: find.byType(TextField),
    ),
    _passphrase,
  );
  await _tapDialog(tester, 'Sign');
}

/// The wallet's row in the picker (the closing shell's header names it too).
final _inPicker = find.descendant(
  of: find.byType(WalletPickerScreen),
  matching: find.text('Peg throwaway'),
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'native peg-in and peg-out from the Peg screen',
    skip: _labUrl.isEmpty,
    timeout: const Timeout(Duration(minutes: 15)),
    (tester) async {
      // An older SwitchListTile on a coloured card trips a debug-only ink
      // assertion on some screens; it has nothing to do with this flow.
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

      final dataDir = Directory(
        '${Directory.systemTemp.path}/templar-peg-'
        '${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
      expect(FfiWalletBridge.setDataDir(dataDir.path), 0);
      expect(walletBridge, isA<FfiWalletBridge>());
      debugPrint('PEG data dir ${dataDir.path}');

      // Throwaway vault, joined to the lab, then the wallet.
      await walletBridge.setupVault(_passphrase);
      await walletBridge.setTestServer(_labUrl);
      final words = await walletBridge.generateMnemonic(12);
      final walletId = await walletBridge.createWallet(
        'Peg throwaway',
        words,
        liquid: true,
      );
      final net = await walletBridge.getLiquidNetwork();
      expect(net.pegProvider, 'native');

      // Coins from the lab's admin API: BTC to peg in, L-BTC for fees.
      await walletBridge.openWallet(walletId);
      final btcAddr = (await walletBridge.generateReceiveAddress(
        walletId,
        'BTC',
      )).address;
      final lbtcAddr = (await walletBridge.generateReceiveAddress(
        walletId,
        'LBTC',
      )).address;
      final sentBtc = await _admin('send', {
        'network': 'bitcoin-regtest',
        'address': btcAddr,
        'amount': '0.01',
      });
      final sentLbtc = await _admin('send', {
        'network': 'liquid-regtest',
        'address': lbtcAddr,
        'asset': 'lbtc',
        'amount': '0.001',
      });
      debugPrint(
        'PEG funded: btc ${sentBtc['txid']}, lbtc ${sentLbtc['txid']}',
      );
      await _mine('bitcoin', 1);
      await _mine('liquid', 1);
      await Future<void>.delayed(const Duration(seconds: 3));
      final start = await _balances(walletId, ok: (b) => b.$1 > 0 && b.$2 > 0);
      debugPrint(
        'PEG balances before: BTC ${start.$1} sat, L-BTC ${start.$2} sat',
      );
      expect(start.$1, greaterThan(0));

      final appState = AppState();
      await appState.loadPrefs();
      await appState.setPegEnabled(true);
      appState.setLiquidNetworkInfo(net);
      appState.setTestServerInfo(await walletBridge.getTestServer());

      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(2560, 2000);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: appState,
          child: const TemplarWalletApp(),
        ),
      );
      await _wait(tester, 2500);
      appRouter.go(AppRoutes.walletPicker);
      await _until(tester, _inPicker);
      await _wait(tester, 1000);
      await tester.tap(_inPicker.first);
      await _wait(tester, 3000);

      // ── Peg-in ────────────────────────────────────────────────────────────
      appRouter.go(AppRoutes.peg);
      await _until(tester, find.textContaining('Native peg'));
      await tester.enterText(find.byType(TextField).first, '0.002');
      await _until(tester, find.text('2 Bitcoin confirmations'));
      await _wait(tester, 1500); // the payout address prefill
      await _tapText(tester, 'Start peg-in');
      await _until(tester, find.text('Fund from this wallet'));
      final pegIn = (await walletBridge.pegList(walletId)).first;
      debugPrint(
        'PEG in ${pegIn.orderId}: deposit ${pegIn.depositAddress} '
        '(valid through Liquid ${pegIn.validUntilLiquidHeight})',
      );

      await _tapText(tester, 'Fund from this wallet');
      await _confirmAndSign(tester);
      await _until(tester, find.textContaining('Deposit sent'));
      debugPrint(
        'PEG in deposit tx ${(await _order(walletId, pegIn.orderId)).txidDeposit}',
      );

      await _refreshUntil(
        tester,
        walletId,
        pegIn.orderId,
        'claimable',
        between: () => _mine('bitcoin', 1),
      );
      await _until(tester, find.text('Claim'));
      await _tapText(tester, 'Claim');
      await _confirmAndSign(tester);
      await _until(tester, find.textContaining('Claim sent'));
      await _refreshUntil(
        tester,
        walletId,
        pegIn.orderId,
        'completed',
        between: () => _mine('liquid', 1),
      );
      // The badge beside the stepper's own "Completed" label.
      expect(find.text('Completed'), findsAtLeastNWidgets(2));
      final inDone = await _order(walletId, pegIn.orderId);
      debugPrint(
        'PEG in ${inDone.status}: deposit ${inDone.txidDeposit}, claim '
        '${inDone.txidClaim}, received ${inDone.payoutExpectedSats} sat',
      );
      expect(inDone.status, 'completed');
      final afterIn = await _balances(walletId, ok: (b) => b.$2 > start.$2);
      debugPrint(
        'PEG balances after peg-in: BTC ${afterIn.$1} sat, L-BTC ${afterIn.$2} sat',
      );
      expect(afterIn.$2, greaterThan(start.$2));

      // ── Peg-out ───────────────────────────────────────────────────────────
      await _tapText(tester, 'Peg-out');
      await _wait(tester, 1500);
      await tester.enterText(find.byType(TextField).first, '0.001');
      await _until(tester, find.text('2 Liquid confirmations'));
      await _wait(tester, 1500);
      await _tapText(tester, 'Start peg-out');
      await _until(tester, find.textContaining('no address to pay by hand'));
      final pegOut = (await walletBridge.pegList(walletId)).first;
      expect(pegOut.isPegIn, isFalse);

      await _tapText(tester, 'Fund from this wallet');
      await _confirmAndSign(tester);
      await _until(tester, find.textContaining('Deposit sent'));
      debugPrint(
        'PEG out ${pegOut.orderId}: peg-out tx '
        '${(await _order(walletId, pegOut.orderId)).txidDeposit}',
      );

      // Liquid confirmations, then the lab's federation bot pays; its
      // payment completes the order once it is in a Bitcoin block.
      await _refreshUntil(
        tester,
        walletId,
        pegOut.orderId,
        'completed',
        tries: 40,
        between: () async {
          final o = await _order(walletId, pegOut.orderId);
          await _mine(o.status == 'settling' ? 'bitcoin' : 'liquid', 1);
        },
      );
      final outDone = await _order(walletId, pegOut.orderId);
      debugPrint(
        'PEG out ${outDone.status}: peg-out ${outDone.txidDeposit}, '
        'federation payment ${outDone.txidPayout}',
      );
      expect(outDone.status, 'completed');
      await Future<void>.delayed(const Duration(seconds: 3));
      final end = await _balances(walletId, ok: (b) => b.$1 > afterIn.$1);
      debugPrint(
        'PEG balances after peg-out: BTC ${end.$1} sat, L-BTC ${end.$2} sat',
      );
      expect(end.$1, greaterThan(afterIn.$1));
    },
  );
}
