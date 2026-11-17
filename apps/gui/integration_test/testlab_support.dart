// Shared steps of the opt-in test-lab runs (testlab_*_test.dart): pumping
// the real app around a capture boundary, waiting for the engine, tapping,
// the password gate, the lab's admin API on loopback, and the user-guide
// screenshots.
//
// Screenshots: with --dart-define=GUIDE_SHOTS_DIR=<absolute path> every
// [guideShot] writes `<dir>/<name>.png` — the whole app window at 2× —
// and without it nothing is written. Never shoot a recovery phrase or a
// password: the throwaway wallets here are created through the bridge, and
// the password gate is shot only before anything is typed into it.

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/router.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/features/wallet_picker/wallet_picker_screen.dart';
import 'package:templar_wallet/main.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';

const String labUrl = String.fromEnvironment('TESTLAB_URL');
const String guideShotsDir = String.fromEnvironment('GUIDE_SHOTS_DIR');

final GlobalKey _shotKey = GlobalKey();

/// Pumps [ms] of frames, in steps of 100 ms.
Future<void> wait(WidgetTester tester, [int ms = 700]) async {
  for (var i = 0; i < (ms / 100).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The text a widget shows: plain, rich, selectable or typed.
String? shownText(Widget w) => switch (w) {
  Text() => w.data ?? w.textSpan?.toPlainText(),
  RichText() => w.text.toPlainText(),
  SelectableText() => w.data ?? w.textSpan?.toPlainText(),
  EditableText() => w.controller.text,
  _ => null,
};

Finder textContaining(String part) =>
    find.byWidgetPredicate((w) => shownText(w)?.contains(part) ?? false);

String firstTextContaining(String part) =>
    shownText(textContaining(part).evaluate().first.widget)!;

/// What is on screen, for a failure message.
String onScreen() => find
    .byWidgetPredicate((w) => w is Text || w is RichText)
    .evaluate()
    .map((e) => shownText(e.widget) ?? '')
    .where((t) => t.trim().isNotEmpty)
    .take(60)
    .join(' | ');

/// Pumps until [finder] matches at least [atLeast] widgets.
Future<void> until(
  WidgetTester tester,
  Finder finder, {
  int seconds = 90,
  int atLeast = 1,
}) async {
  for (var i = 0; i < seconds * 10; i++) {
    if (finder.evaluate().length >= atLeast) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('timed out waiting for $finder; on screen: ${onScreen()}');
}

/// Scrolls [finder] into view, then taps it.
Future<void> tapOn(WidgetTester tester, Finder finder, {int ms = 800}) async {
  await until(tester, finder);
  await tester.ensureVisible(finder.first);
  await wait(tester, 400);
  await tester.tap(finder.first);
  await wait(tester, ms);
}

Future<void> tapText(WidgetTester tester, String label, {int ms = 800}) =>
    tapOn(tester, find.text(label), ms: ms);

/// A control inside the open dialog or sheet.
Future<void> tapInDialog(WidgetTester tester, String label) async {
  final f = find.descendant(
    of: find.byType(PromptDialog),
    matching: find.text(label),
  );
  await until(tester, f);
  await tester.tap(f.first);
  await wait(tester, 800);
}

/// The app password gate, passed with [passphrase]. With [shot], the gate
/// is captured first — empty, before anything is typed.
Future<void> passGate(
  WidgetTester tester,
  String passphrase, {
  String? shot,
}) async {
  await until(tester, find.text('Confirm with your app password'));
  if (shot != null) await guideShot(tester, shot);
  await tester.enterText(
    find.descendant(
      of: find.byType(PromptDialog),
      matching: find.byType(TextField),
    ),
    passphrase,
  );
  await tester.tap(
    find.descendant(of: find.byType(PromptDialog), matching: find.text('Sign')),
  );
  await wait(tester, 1500);
}

/// The real app, inside the boundary the guide screenshots are taken of,
/// in a 1280 × 900 window drawn at 2×.
Future<void> pumpApp(WidgetTester tester, AppState state) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(2560, 1800);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: ChangeNotifierProvider.value(
        value: state,
        child: const TemplarWalletApp(),
      ),
    ),
  );
  await wait(tester, 2500);
}

/// The whole window as `<GUIDE_SHOTS_DIR>/<name>.png`, when a directory was
/// given; nothing otherwise.
Future<void> guideShot(
  WidgetTester tester,
  String name, {
  int settle = 900,
}) async {
  if (guideShotsDir.isEmpty) return;
  await wait(tester, settle);
  final boundary =
      _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${_shotsDir()}/$name.png');
  file.writeAsBytesSync(data!.buffer.asUint8List());
  debugPrint('GUIDE SHOT ${file.path}');
}

String? _resolvedShotsDir;

/// [guideShotsDir] when the app may write there; else — the macOS app runs
/// sandboxed — a folder in its own temp directory, whose path is printed so
/// the files can be copied out after the run.
String _shotsDir() {
  final known = _resolvedShotsDir;
  if (known != null) return known;
  for (final candidate in [
    guideShotsDir,
    '${Directory.systemTemp.path}/templar-guide-shots',
  ]) {
    try {
      final dir = Directory(candidate)..createSync(recursive: true);
      File('${dir.path}/.probe')
        ..writeAsStringSync('ok')
        ..deleteSync();
      debugPrint('GUIDE SHOTS DIR ${dir.path}');
      return _resolvedShotsDir = dir.path;
    } catch (_) {
      continue;
    }
  }
  fail('no writable directory for the guide screenshots');
}

/// Opens [name] from the wallet picker (its own row, not the closing
/// shell's header).
Future<void> openWallet(WidgetTester tester, String name) async {
  appRouter.go(AppRoutes.walletPicker);
  final row = find.descendant(
    of: find.byType(WalletPickerScreen),
    matching: find.text(name),
  );
  await until(tester, row);
  await wait(tester, 800);
  await tester.tap(row.first);
  await wait(tester, 3000);
}

/// Turns an optional feature on in Settings › Advanced, as a user does
/// (`advanced-liquiddex`, `advanced-peg`, `advanced-loans`).
Future<void> enableFeature(WidgetTester tester, String key) async {
  appRouter.go(AppRoutes.settingsAdvanced);
  final sw = find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(Switch),
  );
  await until(tester, sw);
  if (!tester.widget<Switch>(sw).value) await tapOn(tester, sw);
}

/// The lab's admin API (open on loopback).
Future<Map<String, dynamic>> labAdmin(
  String path,
  Map<String, Object> body,
) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(Uri.parse('$labUrl/admin/api/$path'));
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

Future<void> mine(String chain, [int blocks = 1]) =>
    labAdmin('mine', {'chain': chain, 'blocks': blocks});

/// The balance of each asset of [walletId] by ticker, in base units, after
/// a sync; retried until [ok] holds (the Electrum index trails a block).
Future<Map<String, int>> balances(
  String walletId, {
  bool Function(Map<String, int>)? ok,
  int tries = 20,
}) async {
  var last = <String, int>{};
  for (var i = 0; i < tries; i++) {
    await walletBridge.syncWallet(walletId);
    final d = await walletBridge.getWalletSummary(walletId);
    last = {};
    for (final a in d.assets) {
      last[a.ticker] = (last[a.ticker] ?? 0) + a.amount;
    }
    if (ok == null || ok(last)) return last;
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  return last;
}

/// Ignores a debug-only ink assertion an older SwitchListTile on a
/// coloured card trips; everything else still fails.
void ignoreInkAssertion() {
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
}

/// A fresh throwaway data directory, handed to the engine before its first
/// call. Returns its path.
String throwawayDataDir(String prefix) {
  final dir = Directory(
    '${Directory.systemTemp.path}/$prefix-'
    '${DateTime.now().millisecondsSinceEpoch}',
  )..createSync(recursive: true);
  return dir.path;
}
