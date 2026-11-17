// A LiquiDEX swap through the app's own screens, on the real engine, against
// a running Templar test server: two throwaway software wallets in one app,
// A the maker and B the taker.
//
// Opt-in; it needs a lab with its order book and skips without its URL:
//
//   FLUTTER_XCODE_PRODUCT_BUNDLE_IDENTIFIER=dev.templarwallet.testlabverify \
//   flutter test integration_test/testlab_swap_test.dart -d macos \
//     --dart-define=TESTLAB_URL=http://127.0.0.1:8096
//
// (The bundle id override keeps the run in a sandbox container of its own,
// away from a real install's vault; the window must be in front.)
//
// Taps in the app: enabling LiquiDEX in Settings › Advanced; A's two offers
// (coin, wanted asset and amount, sign behind the app password, publish);
// B opening A's first offer from the market and taking it (review, sign
// behind the app password); A cancelling the second offer (confirmation,
// app password); B importing that cancelled proposal and finding it cannot
// be taken; switching wallets through the wallet picker.
//
// NOT through the GUI, on purpose: joining the lab (proven by
// testlab_join_test.dart), creating the two wallets, funding them and
// mining (the lab's admin API — the lab operator's tools), and reading
// balances and the order book's record for the log and the assertions (the
// bridge).

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
import 'package:templar_wallet/features/swap/models/swap_offer.dart';
import 'package:templar_wallet/features/wallet_picker/wallet_picker_screen.dart';
import 'package:templar_wallet/main.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';
import 'package:templar_wallet/shared/widgets/buttons.dart';
import 'package:templar_wallet/shared/widgets/code_box.dart';
import 'package:templar_wallet/shared/widgets/utxo_views.dart';

const String _labUrl = String.fromEnvironment('TESTLAB_URL');
const _passphrase = 'testlab-swap-throwaway-passphrase';

/// "Live Swap Token", issued on the lab (precision 2).
const _lst = 'a50efb22ec6b9d994d114aeeb82f2ac1cb0d8abb1c2660c35b9a51f66de574ee';

// Amounts unique to this run, so the market rows are this run's and no
// one else's (an earlier run's offers can still be open in the book).
final _tag = DateTime.now().millisecondsSinceEpoch % 9000 + 1000;
final _want1 = '0.0005$_tag';
final _want1Sats = 50000 + _tag;
final _want2 = '0.0006$_tag';

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
  final shown = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((t) => t.trim().isNotEmpty)
      .take(50)
      .join(' | ');
  fail('timed out waiting for $finder; on screen: $shown');
}

/// Scrolls [finder] into view, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.ensureVisible(finder.first);
  await _wait(tester, 400);
  await tester.tap(finder.first);
  await _wait(tester, 800);
}

Future<void> _tapText(WidgetTester tester, String label) =>
    _tap(tester, find.text(label));

/// The app password gate, passed.
Future<void> _passGate(WidgetTester tester) async {
  await _until(tester, find.text('Confirm with your app password'));
  await tester.enterText(
    find.descendant(
      of: find.byType(PromptDialog),
      matching: find.byType(TextField),
    ),
    _passphrase,
  );
  await tester.tap(
    find.descendant(of: find.byType(PromptDialog), matching: find.text('Sign')),
  );
  await _wait(tester, 1500);
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

Future<void> _mineLiquid() => _admin('mine', {'chain': 'liquid', 'blocks': 1});

/// (L-BTC, LST) in base units after a sync, retried until [ok] holds (the
/// Electrum index trails a mined block by a few seconds).
Future<(int, int)> _balances(
  String walletId, {
  bool Function((int, int))? ok,
}) async {
  var last = (0, 0);
  for (var i = 0; i < 20; i++) {
    await walletBridge.syncWallet(walletId);
    final d = await walletBridge.getWalletSummary(walletId);
    int of(bool Function(String id, String t) pick) => d.assets
        .where((a) => pick(a.assetId, a.ticker))
        .fold(0, (n, a) => n + a.amount);
    last = (of((_, t) => t == 'LBTC'), of((id, _) => id == _lst));
    if (ok == null || ok(last)) return last;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  return last;
}

/// Opens [name] from the wallet picker (its own row, not the closing
/// shell's header).
Future<void> _openWallet(WidgetTester tester, String name) async {
  appRouter.go(AppRoutes.walletPicker);
  final row = find.descendant(
    of: find.byType(WalletPickerScreen),
    matching: find.text(name),
  );
  await _until(tester, row);
  await _wait(tester, 800);
  await tester.tap(row.first);
  await _wait(tester, 3000);
}

/// An LST coin in the offer step's picker (list rows or notes), other than
/// [except].
Finder _lstCoin({String? except}) => find.byWidgetPredicate((w) {
  final utxo = switch (w) {
    CoinRow() => w.utxo,
    UtxoBanknote() => w.utxo,
    _ => null,
  };
  return utxo != null && utxo.assetId == _lst && utxo.outpoint != except;
});

/// A's offer through the make flow: coin, wanted L-BTC, sign, publish.
/// Returns (the order book's id, the offered coin, the proposal JSON).
Future<(int, String, String)> _makeOffer(
  WidgetTester tester,
  String want, {
  String? exceptCoin,
}) async {
  await _tapText(tester, 'New offer');
  await _tapText(tester, 'Liquid · LiquiDEX');
  await _tap(tester, _lstCoin(except: exceptCoin));
  // The coin now picked; kept to offer a different one next time.
  final coin = find
      .byWidgetPredicate(
        (w) => switch (w) {
          CoinRow() => w.utxo.isSelected,
          UtxoBanknote() => w.utxo.isSelected,
          _ => false,
        },
      )
      .evaluate()
      .map(
        (e) => switch (e.widget) {
          final CoinRow r => r.utxo.outpoint,
          final UtxoBanknote n => n.utxo.outpoint,
          _ => '',
        },
      )
      .first;
  await _tapText(tester, 'Continue');
  // What is wanted: L-BTC, from the asset menu.
  await _tap(tester, find.byType(DropdownButtonFormField<String>));
  await _tap(tester, find.text('LBTC').last);
  await tester.enterText(find.byType(TextField).last, want);
  await _wait(tester, 500);
  await _tapText(tester, 'Continue');
  await _tapText(tester, 'Sign and create offer');
  await _passGate(tester);
  await _until(tester, find.text('Offer created'));
  final proposal = tester.widget<CodeBox>(find.byType(CodeBox).first).value;
  await _tap(
    tester,
    find.descendant(of: find.byType(AppDialog), matching: find.text('Publish')),
  );
  await _until(tester, find.textContaining('Published as order #'));
  final text = tester
      .widget<Text>(find.textContaining('Published as order #'))
      .data!;
  final id = int.parse(RegExp(r'#(\d+)').firstMatch(text)!.group(1)!);
  await _tapText(tester, 'Done');
  await _wait(tester, 1500);
  return (id, coin, proposal);
}

/// The order book's rows for its offer [id], read until none is available
/// any more. Its watcher looks at the chain once a minute, so this waits up
/// to three.
Future<List<MarketOffer>> _bookUntilClosed(int id) async {
  var rows = <MarketOffer>[];
  for (var i = 0; i < 60; i++) {
    rows = (await walletBridge.listMarkets(
      includeUnavailable: true,
    )).where((m) => m.sourceId == id).toList();
    // A closed offer leaves the market feed (or stays as unavailable).
    if (rows.every((m) => !m.available)) {
      debugPrint('SWAP order book #$id closed after ${i * 3} s');
      return rows;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  return rows;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'LiquiDEX: make, publish, take, cancel through the app',
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
        '${Directory.systemTemp.path}/templar-swap-'
        '${DateTime.now().millisecondsSinceEpoch}',
      )..createSync(recursive: true);
      expect(FfiWalletBridge.setDataDir(dataDir.path), 0);
      expect(walletBridge, isA<FfiWalletBridge>());
      debugPrint('SWAP data dir ${dataDir.path}');

      // Throwaway vault joined to the lab, then the two wallets.
      await walletBridge.setupVault(_passphrase);
      await walletBridge.setTestServer(_labUrl);
      final a = await walletBridge.createWallet(
        'Swap maker',
        await walletBridge.generateMnemonic(12),
        liquid: true,
      );
      final b = await walletBridge.createWallet(
        'Swap taker',
        await walletBridge.generateMnemonic(12),
        liquid: true,
      );

      // Coins from the lab's admin API: two LST coins and L-BTC for A,
      // L-BTC for B.
      await walletBridge.openWallet(a);
      final aAddr = (await walletBridge.generateReceiveAddress(
        a,
        'LBTC',
      )).address;
      await walletBridge.openWallet(b);
      final bAddr = (await walletBridge.generateReceiveAddress(
        b,
        'LBTC',
      )).address;
      for (final (addr, asset, amount) in [
        (aAddr, _lst, '10'),
        (aAddr, _lst, '10'),
        (aAddr, 'lbtc', '0.001'),
        (bAddr, 'lbtc', '0.002'),
      ]) {
        final r = await _admin('send', {
          'network': 'liquid-regtest',
          'address': addr,
          'asset': asset,
          'amount': amount,
        });
        debugPrint(
          'SWAP funded ${addr.substring(0, 12)}… $amount $asset: ${r['txid']}',
        );
      }
      await _mineLiquid();
      final aBefore = await _balances(a, ok: (x) => x.$1 > 0 && x.$2 >= 2000);
      final bBefore = await _balances(b, ok: (x) => x.$1 > 0);
      debugPrint(
        'SWAP before: A L-BTC ${aBefore.$1}, LST ${aBefore.$2}; '
        'B L-BTC ${bBefore.$1}, LST ${bBefore.$2}',
      );
      expect(aBefore.$2, 2000);

      final appState = AppState();
      await appState.loadPrefs();
      appState.setLiquidNetworkInfo(await walletBridge.getLiquidNetwork());
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

      // ── A: LiquiDEX on, as a user turns it on ───────────────────────────
      await _openWallet(tester, 'Swap maker');
      appRouter.go(AppRoutes.settingsAdvanced);
      final dexSwitch = find.descendant(
        of: find.byKey(const Key('advanced-liquiddex')),
        matching: find.byType(Switch),
      );
      await _until(tester, dexSwitch);
      // The preference outlives a run in the same test container: flip the
      // switch only when it is off.
      if (!tester.widget<Switch>(dexSwitch).value) {
        await _tap(tester, dexSwitch);
      }
      expect(appState.liquidDexEnabled, isTrue);

      // ── A: two offers, both published ──────────────────────────────────
      appRouter.go(AppRoutes.swap);
      await _until(tester, find.text('New offer'));
      final (id1, coin1, _) = await _makeOffer(tester, _want1);
      debugPrint('SWAP offer 1 #$id1: coin $coin1 for $_want1 L-BTC');
      final (id2, coin2, proposal2) = await _makeOffer(
        tester,
        _want2,
        exceptCoin: coin1,
      );
      debugPrint('SWAP offer 2 #$id2: coin $coin2 for $_want2 L-BTC');

      // ── B: the market, the row, review and take ────────────────────────
      await _openWallet(tester, 'Swap taker');
      appRouter.go(AppRoutes.swap);
      final row1 = find.textContaining('Pay $_want1');
      await _until(tester, row1);
      await _tap(tester, row1);
      await _tapText(tester, 'Review and take');
      // The deep check against the chain, then the preview.
      final cont = find.widgetWithText(PrimaryButton, 'Continue');
      await _until(tester, cont);
      for (var i = 0; i < 300; i++) {
        if (tester.widget<PrimaryButton>(cont).onPressed != null) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _tap(tester, cont);
      final take = find.widgetWithText(PrimaryButton, 'Take swap');
      await _until(tester, take);
      for (var i = 0; i < 300; i++) {
        if (tester.widget<PrimaryButton>(take).onPressed != null) break;
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _tap(tester, take);
      await _tapText(tester, 'Sign and broadcast');
      await _passGate(tester);
      await _until(tester, find.text('Swap broadcast'));
      final takeTxid = tester
          .widget<CodeBox>(
            find.descendant(
              of: find.byType(AppDialog),
              matching: find.byType(CodeBox),
            ),
          )
          .value;
      debugPrint('SWAP taken by B: txid $takeTxid');
      await _tapText(tester, 'Done');
      await _wait(tester, 2000);

      // ── Mined: both wallets see the swap ───────────────────────────────
      await _mineLiquid();
      final aAfter = await _balances(
        a,
        ok: (x) => x.$1 >= aBefore.$1 + _want1Sats,
      );
      final bAfter = await _balances(b, ok: (x) => x.$2 >= 1000);
      debugPrint(
        'SWAP after the take: A L-BTC ${aAfter.$1}, LST ${aAfter.$2}; '
        'B L-BTC ${bAfter.$1}, LST ${bAfter.$2}',
      );
      // A sees the L-BTC it was paid, and its LST coin is gone.
      expect(aAfter.$1, aBefore.$1 + _want1Sats);
      expect(aAfter.$2, aBefore.$2 - 1000);
      // B has the LST and paid the L-BTC plus the fee.
      expect(bAfter.$2, 1000);
      expect(bAfter.$1, lessThan(bBefore.$1 - _want1Sats));

      // The order book's watcher notices the spent coin on its own round.
      final book1 = await _bookUntilClosed(id1);
      debugPrint(
        'SWAP order book #$id1 after the take: '
        '${book1.map((m) => '${m.status} available=${m.available}').join(', ')}',
      );
      expect(book1.every((m) => !m.available), isTrue);

      // ── A: cancel the second offer ─────────────────────────────────────
      await _openWallet(tester, 'Swap maker');
      appRouter.go(AppRoutes.swap);
      // A's own row under "My swaps" ("<amount> <asset> → 0.0006… LBTC"),
      // not the market's row of the same offer ("Pay 0.0006… LBTC · …"). The
      // offered leg is printed as the engine's list_my_offers gives it (for
      // LST: "0.00001000 a50efb22"), so only the wanted side is matched;
      // the rows on screen are logged.
      final ownTitle = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').contains('→ $_want2 ') &&
            !(w.data ?? '').startsWith('Pay '),
      );
      await _until(tester, find.text('My swaps'));
      await _wait(tester, 3000);
      for (final e in find.textContaining(_want2).evaluate()) {
        debugPrint('SWAP on screen: "${(e.widget as Text).data}"');
      }
      final row2 = find.ancestor(
        of: ownTitle,
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_SwapRow',
        ),
      );
      await _until(tester, row2);
      await _tap(
        tester,
        find.descendant(of: row2.first, matching: find.text('Cancel')),
      );
      await _until(tester, find.text('Cancel this offer?'));
      await _tapText(tester, 'Cancel offer');
      await _passGate(tester);
      await _until(tester, find.textContaining('Offer cancelled — txid'));
      final cancelTxid = RegExp(r'txid (\w+)')
          .firstMatch(
            tester
                .widget<Text>(find.textContaining('Offer cancelled — txid'))
                .data!,
          )!
          .group(1);
      debugPrint('SWAP offer 2 cancelled by A: txid $cancelTxid');
      await _mineLiquid();
      await _wait(tester, 4000);

      // ── B: the cancelled proposal cannot be taken ──────────────────────
      await _openWallet(tester, 'Swap taker');
      appRouter.go(AppRoutes.swap);
      await _tap(tester, find.byTooltip('Import proposal'));
      await tester.enterText(
        find.descendant(
          of: find.byType(AppDialog),
          matching: find.byType(TextField),
        ),
        proposal2,
      );
      await _tapText(tester, 'Verify proposal');
      await _until(
        tester,
        find.text('This order cannot be taken'),
        seconds: 60,
      );
      final reason = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((t) => t.isNotEmpty)
          .skipWhile((t) => t != 'This order cannot be taken')
          .skip(1)
          .firstOrNull;
      debugPrint('SWAP B on the cancelled proposal: "$reason"');
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Continue'),
            )
            .onPressed,
        isNull,
      );
      final book2 = await _bookUntilClosed(id2);
      debugPrint(
        'SWAP order book #$id2 after the cancel: '
        '${book2.map((m) => '${m.status} available=${m.available}').join(', ')}',
      );
      expect(book2.every((m) => !m.available), isTrue);
    },
  );
}
