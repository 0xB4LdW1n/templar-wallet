// Headless screenshot tour — every screen of the app, desktop or phone, in
// seconds and without a device. Not a test of anything: each step is
// best-effort and logs a MISS instead of failing. Skipped unless asked for:
//
//   flutter test test/tour/tour_test.dart --dart-define=TOUR=/abs/out/dir
//     [--dart-define=TOUR_FORM=phone]      desktop (default) | phone
//     [--dart-define=TOUR_THEME=light]     dark (default) | light
//     [--dart-define=TOUR_SCENES=send,utxos]
//     [--dart-define=TOUR_TALL=true]       a tall window, to see whole pages
//     [--dart-define=TOUR_WIDTH=1024]      the desktop window's width (1280)
//
// Runs on the mock bridge (every widget test does). The phone form reaches
// the `AppLayout.isPhone` trees through `AppLayout.debugMobileOverride`.
// `integration_test/screenshots_test.dart` stays the source of the manuals'
// pictures: it drives the real desktop runner.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/app/router.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/bridge/bridge_provider.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/create_wallet/models/new_wallet_draft.dart';
import 'package:templar_wallet/main.dart';
import 'package:templar_wallet/services/fee_bump_store.dart';
import 'package:templar_wallet/services/issued_asset_store.dart';
import 'package:templar_wallet/services/price_service.dart';
import 'package:templar_wallet/theme/app_layout.dart';
import 'package:templar_wallet/theme/app_typography.dart';

import '../test_fonts.dart';

const String _out = String.fromEnvironment('TOUR');
const String _form = String.fromEnvironment(
  'TOUR_FORM',
  defaultValue: 'desktop',
);
const String _theme = String.fromEnvironment(
  'TOUR_THEME',
  defaultValue: 'dark',
);
const String _scenes = String.fromEnvironment(
  'TOUR_SCENES',
  defaultValue: 'all',
);
const bool _tall = bool.fromEnvironment('TOUR_TALL');

/// The desktop window's width: 1280 unless `TOUR_WIDTH` says otherwise.
const int _width = int.fromEnvironment('TOUR_WIDTH', defaultValue: 1280);

bool get _phone => _form == 'phone';
bool _want(String scene) =>
    _scenes == 'all' || _scenes.split(',').contains(scene);

final GlobalKey _shotKey = GlobalKey();
const double _dpr = 2;
int _seq = 0;

/// A plausible 30-day BTC/EUR walk, seeded so every run draws the same chart.
String _priceSeries(int days) {
  final rnd = math.Random(7);
  final now = DateTime.now();
  final n = days <= 1 ? 48 : (days <= 0 ? 400 : math.min(days * 4, 360));
  final span = Duration(days: days <= 0 ? 900 : days);
  var price = 52000.0;
  final points = <List<num>>[];
  for (var i = 0; i < n; i++) {
    price *= 1 + (rnd.nextDouble() - 0.46) * 0.022;
    final t = now.subtract(span * ((n - 1 - i) / (n - 1)));
    points.add([t.millisecondsSinceEpoch, price]);
  }
  final scale = 68210.0 / price;
  return json.encode({
    'fetched_at': now.millisecondsSinceEpoch,
    'points': [
      for (final p in points) [p[0], p[1] * scale],
    ],
  });
}

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _wait(WidgetTester tester, [int ms = 600]) async {
  for (var i = 0; i < (ms / 100).ceil(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final e = tester.takeException();
  if (e != null) debugPrint('EXC ${e.toString().split('\n').first}');
}

Future<void> _shot(WidgetTester tester, String name, {int settle = 500}) async {
  await _wait(tester, settle);
  final boundary =
      _shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
  _seq++;
  debugPrint('SHOT $name');
}

Future<bool> _tapText(
  WidgetTester tester,
  String label, {
  int ms = 800,
  bool last = false,
}) async {
  final finder = find.text(label).hitTestable();
  if (finder.evaluate().isEmpty) {
    debugPrint('MISS text "$label"');
    return false;
  }
  await tester.tap(last ? finder.last : finder.first, warnIfMissed: false);
  await _wait(tester, ms);
  return true;
}

Future<bool> _tapIcon(
  WidgetTester tester,
  IconData icon, {
  int ms = 800,
}) async {
  final finder = find.byIcon(icon).hitTestable();
  if (finder.evaluate().isEmpty) {
    debugPrint('MISS icon $icon');
    return false;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await _wait(tester, ms);
  return true;
}

/// Taps the control whose tooltip is [message] (an icon button is named by
/// its tooltip, and the same glyph can sit in the sidebar too).
Future<bool> _tapTooltip(
  WidgetTester tester,
  String message, {
  int ms = 800,
}) async {
  final finder = find.byTooltip(message).hitTestable();
  if (finder.evaluate().isEmpty) {
    debugPrint('MISS tooltip "$message"');
    return false;
  }
  await tester.tap(finder.first, warnIfMissed: false);
  await _wait(tester, ms);
  return true;
}

Future<void> _go(WidgetTester tester, String route, {int ms = 1200}) async {
  appRouter.go(route);
  await _wait(tester, ms);
}

Future<bool> _type(WidgetTester tester, String hint, String text) async {
  var field = find.ancestor(
    of: find.text(hint),
    matching: find.byType(TextField),
  );
  if (field.evaluate().isEmpty && find.text(hint).evaluate().isNotEmpty) {
    // A label above its field (design.md): the field shares its column.
    field = find.descendant(
      of: find
          .ancestor(of: find.text(hint).first, matching: find.byType(Column))
          .first,
      matching: find.byType(TextField),
    );
  }
  if (field.evaluate().isEmpty) {
    debugPrint('MISS field "$hint"');
    return false;
  }
  await tester.enterText(field.first, text);
  await _wait(tester, 400);
  return true;
}

/// Scroll the page until [label] is on screen (a form taller than the
/// window). False when it does not exist.
Future<bool> _reveal(WidgetTester tester, String label) async {
  final finder = find.text(label);
  if (finder.evaluate().isEmpty) {
    debugPrint('MISS text "$label"');
    return false;
  }
  await tester.ensureVisible(finder.first);
  await _wait(tester, 400);
  return true;
}

Future<void> _scroll(WidgetTester tester, double dy) async {
  final scrollable = find.byType(Scrollable).hitTestable();
  if (scrollable.evaluate().isEmpty) return;
  await tester.drag(scrollable.first, Offset(0, dy), warnIfMissed: false);
  await _wait(tester, 500);
}

void main() {
  testWidgets('tour', (tester) async {
    Directory(_out).createSync(recursive: true);
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    AppLayout.debugMobileOverride = _phone ? true : null;
    addTearDown(() => AppLayout.debugMobileOverride = null);

    await loadTestFonts();
    await _loadIcons();
    // google_fonts registers each vendored face on first use, off the frame.
    // Ask for every one up front, so no shot is taken with a face missing.
    final faces = [
      AppTypography.body,
      AppTypography.label,
      AppTypography.mono,
      AppTypography.monoLarge,
    ];
    await tester.runAsync(() => GoogleFonts.pendingFonts(faces));

    SharedPreferences.setMockInitialValues({
      'pref_fiat_currency': 'EUR',
      'pref_first_run_seen': true,
      'pref_theme_mode': _theme,
      'pref_advanced_liquiddex_enabled': true,
      'pref_advanced_peg_enabled': true,
      'pref_advanced_loans_enabled': true,
      // What this device remembers about the mock wallets: when each was
      // last opened, and the colour the multisig was given in Settings.
      'wallet_custom_v1_wallet-1': json.encode({
        'opened_at': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      }),
      'wallet_custom_v1_wallet-2': json.encode({
        'color': 0xFF3B82F6,
        'opened_at': DateTime.now()
            .subtract(const Duration(days: 3))
            .millisecondsSinceEpoch,
      }),
      // Two of the mock wallet's addresses carry a label the user wrote
      // (Receive writes them; the coin wall and list read them).
      'address_labels_v1': json.encode({
        'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx': 'Savings',
        'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a': 'Exchange withdrawals',
      }),
      // One of them was given a colour of its own (gold); the other is
      // grey, as every address is until it is coloured.
      'address_label_hues_v1': json.encode({
        'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a': 2,
      }),
      for (final d in const [1, 7, 30, 90, 365, 0])
        'price_history_v1_EUR_${d > 0 ? d : 'max'}': _priceSeries(d),
    });
    PriceService.instance.debugSetPrice(68210, currency: 'EUR');

    final size = _phone
        ? const Size(411, 914)
        : Size(_width.toDouble(), _tall ? 2200 : 800);
    tester.view.devicePixelRatio = _dpr;
    tester.view.physicalSize = size * _dpr;
    if (_phone) {
      const insets = FakeViewPadding(top: 24 * _dpr, bottom: 24 * _dpr);
      tester.view.padding = insets;
      tester.view.viewPadding = insets;
    }
    addTearDown(tester.view.reset);

    final appState = AppState();
    await tester.runAsync(() async {
      await appState.loadPrefs();
      try {
        appState.setLiquidNetworkInfo(await walletBridge.getLiquidNetwork());
      } catch (_) {}
    });
    if ((_theme == 'light') != (appState.themeMode == ThemeMode.light)) {
      appState.toggleTheme();
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: ChangeNotifierProvider.value(
          value: appState,
          child: const TemplarWalletApp(),
        ),
      ),
    );
    await _wait(tester, 2500);

    if (_want('welcome')) {
      await _go(tester, AppRoutes.welcome, ms: 1500);
      // The brand mark is the first image the app decodes, and a decode
      // needs real time, which pumping does not give it.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await _shot(tester, 'welcome');
      await _go(tester, AppRoutes.walletPicker, ms: 1500);
    }
    if (_want('picker')) await _shot(tester, 'picker');

    // "Primary" is the mock wallet with Bitcoin and Liquid.
    await _tapText(tester, 'Primary', ms: 2500);

    if (_want('dashboard')) {
      await _shot(tester, 'dashboard', settle: 1500);
      // The chain switch narrows the whole hero: figure, label and chart.
      if (await _tapText(tester, 'BTC', ms: 900)) {
        await _shot(tester, 'dashboard-btc');
        await _tapText(tester, 'All', ms: 900);
      }
      if (!_tall) {
        await _scroll(tester, -520);
        await _shot(tester, 'dashboard-2');
        await _scroll(tester, -520);
        await _shot(tester, 'dashboard-3');
      }
      // A token opens in the detail dialog, the one a transaction opens in.
      if (await _reveal(tester, 'Tether USD (Liquid)') &&
          await _tapText(tester, 'Tether USD (Liquid)', ms: 1200)) {
        await _shot(tester, 'dashboard-token');
        await _tapText(tester, 'Close', ms: 800);
      }
    }

    if (_want('receive')) {
      await _go(tester, AppRoutes.receive, ms: 1600);
      await _shot(tester, 'receive');
      // The label prompt: the tag as it will be drawn, the field, the hues.
      if (await _tapText(tester, 'Add label', ms: 1000)) {
        await _type(tester, 'Rent, exchange, a name', 'Rent');
        await _shot(tester, 'receive-label');
        await _tapText(tester, 'Cancel', ms: 600);
      }
      await _go(tester, AppRoutes.receiveAddresses, ms: 1400);
      await _shot(tester, 'receive-addresses');
    }

    if (_want('send')) {
      await _go(tester, AppRoutes.send, ms: 1600);
      await _shot(tester, 'send-1-compose');
      // "Use my own address": one window, the addresses under their labels.
      if (await _tapTooltip(tester, 'Use my own address', ms: 1500) ||
          await _tapText(tester, 'My address', ms: 1500)) {
        await _shot(tester, 'send-1b-own-address');
        await _tapText(tester, 'Close', ms: 600);
      }
      await _type(
        tester,
        'Paste, scan or type',
        'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      );
      await _type(tester, '0.00000000', '0.0025');
      await _shot(tester, 'send-2-compose-filled');
      // The coin picker opens inline in the Coins card.
      if (await _reveal(tester, 'Choose coins') &&
          await _tapText(tester, 'Choose coins', ms: 1600)) {
        await _reveal(tester, 'Back to automatic');
        await _shot(tester, 'send-2a-coins');
        // The same coins as notes, in the trays of their addresses.
        if (await _tapText(tester, 'Notes', ms: 800)) {
          await _shot(tester, 'send-2a-coins-notes');
          await _tapText(tester, 'List', ms: 600);
        }
        await _tapText(tester, 'Back to automatic', ms: 800);
      }
      // A custom rate reveals its field inline in the Fee card.
      if (await _reveal(tester, 'Custom') &&
          await _tapText(tester, 'Custom', ms: 800)) {
        await _shot(tester, 'send-2b-fee-custom');
        await _tapText(tester, 'Normal', ms: 600);
      }
      await _reveal(tester, 'Review');
      await _tapText(tester, 'Review', ms: 2500);
      await _shot(tester, 'send-3-review');
      // Sign and send: the PSBT's review, its signed copy, the receipt.
      if (await _reveal(tester, 'Sign and send') &&
          await _tapText(tester, 'Sign and send', ms: 1800)) {
        await _shot(tester, 'send-4-sign');
        // Signing asks for the app password first (the mock takes any).
        if (await _tapText(tester, 'Sign', ms: 1200, last: true) &&
            await _type(tester, 'Password', 'correct horse') &&
            await _tapText(tester, 'Sign', ms: 2200, last: true)) {
          await _shot(tester, 'send-5-signed');
          if (await _tapText(tester, 'Broadcast', ms: 2200, last: true)) {
            await _shot(tester, 'send-6-sent');
            await _tapText(tester, 'Done', ms: 800);
          } else {
            await _tapText(tester, 'Cancel', ms: 600);
          }
        } else {
          await _tapText(tester, 'Cancel', ms: 600);
        }
      }
    }

    for (final scene in const <List<String>>[
      ['activity', AppRoutes.history],
      ['utxos', AppRoutes.utxos],
      ['liquid', AppRoutes.liquid],
      ['liquidex', AppRoutes.swap],
      ['peg', AppRoutes.peg],
      ['loans', AppRoutes.loans],
      // The templar:// request screen with no link: its paste phase.
      ['protocol', AppRoutes.protocol],
      ['asset-ops', AppRoutes.assetOperations],
      ['issue', AppRoutes.issueAsset],
      ['wallet-info', AppRoutes.walletInfo],
      ['cosign', AppRoutes.cosign],
      ['settings', AppRoutes.settings],
      ['settings-network', AppRoutes.settingsNetwork],
      ['settings-security', AppRoutes.settingsSecurity],
      ['settings-appearance', AppRoutes.settingsAppearance],
      ['settings-advanced', AppRoutes.settingsAdvanced],
      ['settings-protocol', AppRoutes.settingsProtocol],
      ['settings-about', AppRoutes.settingsAbout],
    ]) {
      if (!_want(scene[0].split('-').first)) continue;
      await _go(tester, scene[1], ms: 1800);
      await _shot(tester, scene[0]);
      if (scene[0] == 'activity') {
        // A swap, a peg and a loan from the list, then the kind filter.
        for (final (row, name) in const [
          ('LiquiDEX swap', 'activity-swap'),
          ('Peg-in', 'activity-peg'),
          ('Loan SQ-42', 'activity-loan'),
        ]) {
          if (await _reveal(tester, row) && await _tapText(tester, row)) {
            await _shot(tester, name);
            await _tapText(tester, 'Close', last: true);
          }
        }
        // Back to the top of the page (the content column, not the
        // sidebar), where the filters are.
        await tester.dragFrom(
          Offset(_phone ? 200 : 900, 400),
          const Offset(0, 4000),
        );
        await _wait(tester, 600);
        if (await _tapText(tester, 'Pegs')) {
          await _shot(tester, 'activity-kind-pegs');
          await _tapText(tester, 'All', last: true);
        }
      }
      if (scene[0] == 'utxos') {
        if (await _tapText(tester, 'List') ||
            await _tapIcon(tester, Icons.view_list_outlined)) {
          await _shot(tester, 'utxos-list');
        }
        if (await _tapText(tester, 'Notes')) await _shot(tester, 'utxos-notes');
        // Desktop: a tray under the pointer shows its two controls, and so
        // does the note the pointer is on.
        final savings = find.text('Savings');
        if (!_phone && savings.evaluate().isNotEmpty) {
          final mouse = await tester.createGesture(
            kind: ui.PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          await mouse.moveTo(tester.getCenter(savings.first));
          await _shot(tester, 'utxos-tray-hover');
          // The tour taps like a finger, which turns hover highlights off:
          // a note only lights under a pointer in the mouse's own mode.
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.alwaysTraditional;
          await mouse.moveTo(
            tester.getCenter(savings.first) + const Offset(260, 0),
          );
          await _shot(tester, 'utxos-note-hover');
          await mouse.removePointer();
          FocusManager.instance.highlightStrategy =
              FocusHighlightStrategy.automatic;
          // The other chain's coins on the same wall (the switch is the
          // last "Liquid" on the page; the first is the sidebar's group).
          if (await _tapText(tester, 'Liquid', ms: 1500, last: true)) {
            await _shot(tester, 'utxos-notes-liquid');
            await _tapText(tester, 'Bitcoin', ms: 1500, last: true);
          }
        }
        // Desktop: selects the coin (the bar rises); phone: opens its sheet.
        await _wait(tester, 1500);
        // The label prompt, from a coin's own tag button (a note on the
        // desktop wall, a row on the phone).
        if (await _tapIcon(tester, Icons.sell_outlined)) {
          await _shot(tester, 'utxos-label');
          await _tapText(tester, 'Cancel');
        }
        if (await _tapText(tester, '0.00600000 BTC')) {
          await _shot(tester, 'utxos-coin');
          await _tapText(tester, _phone ? 'Close' : 'Clear');
        }
        // Phone: the checkbox selects and the bar rises over the list.
        final check = find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Select',
        );
        if (_phone && check.evaluate().isNotEmpty) {
          await tester.tap(check.first, warnIfMissed: false);
          await _shot(tester, 'utxos-selected');
          await _tapText(tester, 'Clear');
        }
      }
      if (scene[0] == 'liquid') {
        // Record the mock wallet's issued token on this "device", so the
        // Issued assets block has a row, then come back to the page.
        await tester.runAsync(
          () => IssuedAssetStore.instance.saveIssuedAsset(
            'wallet-1',
            const IssuedAssetEntry(
              assetId: MockWalletBridge.mockIssuedAssetId,
              name: 'Templar test note',
              ticker: 'TMPL',
              tokenId: MockWalletBridge.mockIssuedTokenId,
              domain: 'templarwallet.dev',
            ),
          ),
        );
        await _go(tester, AppRoutes.dashboard, ms: 600);
        await _go(tester, AppRoutes.liquid, ms: 1800);
        await _shot(tester, 'liquid-issued');
        // Hover-free selection: tap a legend row of the split.
        await _reveal(tester, '100%');
        // The share is printed only in the legend, so it is a safe target.
        if (await _tapText(tester, '100%', ms: 600)) {
          await _shot(tester, 'liquid-split-selected');
          await _tapText(tester, '100%', ms: 400, last: true);
        }
        // The Issued assets block, then a token row opens the detail
        // dialog (a sheet on a phone).
        if (await _reveal(tester, 'Reissue')) {
          if (_phone) await _shot(tester, 'liquid-issued-block');
        }
        if (await _tapText(tester, 'Templar test note', last: true)) {
          await _shot(tester, 'liquid-detail');
          await _tapText(tester, 'Close', last: true);
        }
        await _reveal(tester, 'Tether USD (Liquid)');
        if (await _tapText(tester, 'Tether USD (Liquid)', last: true)) {
          await _shot(tester, 'liquid-detail-usdt');
          await _tapText(tester, 'Close', last: true);
        }
      }
      if (!_tall && !scene[0].startsWith('settings-')) {
        await _scroll(tester, -520);
        await _shot(tester, '${scene[0]}-2');
      }
    }

    if (_want('cosign')) {
      // The co-sign flow, state by state. The mock reads one signature per
      // `~sig` mark in the blob, so a copy carrying one mark opens as
      // "Needs 1 more signature" and signing it completes the 2-of-2.
      await _go(tester, AppRoutes.cosign, ms: 1800);
      await _tapText(tester, 'Bitcoin', ms: 1200);
      await _shot(tester, 'cosign-load');
      await _tapText(tester, 'Paste', ms: 800);
      await _type(tester, 'Base64 PSBT', 'cHNidP8BAH0CAAAAAcosigntour~sig');
      await _shot(tester, 'cosign-paste');
      await _tapText(tester, 'Load and inspect', ms: 1800);
      await _shot(tester, 'cosign-inspect');
      if (!_tall) {
        await _scroll(tester, -520);
        await _shot(tester, 'cosign-inspect-2');
      }
      await _tapText(tester, 'Sign', ms: 1800);
      await _shot(tester, 'cosign-signed');
      if (!_tall) {
        await _scroll(tester, -520);
        await _shot(tester, 'cosign-signed-2');
      }
      // The multisig mock wallet: its keys on the dashboard and wallet info.
      await _go(tester, AppRoutes.walletPicker, ms: 1200);
      if (await _tapText(tester, 'Treasury 2-of-3', ms: 2500)) {
        await _shot(tester, 'cosign-treasury-dashboard', settle: 1500);
        await _go(tester, AppRoutes.walletInfo, ms: 1800);
        await _shot(tester, 'cosign-treasury-info');
      }
    }

    if (_want('rbf')) {
      // The fee-bump dialog on the mock's pending payment: the form, then
      // the priced bump with its before and after.
      await _go(tester, AppRoutes.walletPicker, ms: 1200);
      await _tapText(tester, 'Primary', ms: 2500);
      await _go(tester, AppRoutes.history, ms: 1800);
      if (await _tapText(tester, 'Speed up', ms: 1200)) {
        await _shot(tester, 'rbf-1-form');
        await _tapText(tester, 'Preview fee bump', ms: 1800);
        await _shot(tester, 'rbf-2-before-after');
        await tester.drag(
          find.byType(Scrollable).hitTestable().last,
          const Offset(0, -400),
          warnIfMissed: false,
        );
        await _shot(tester, 'rbf-3-fees');
        await _tapText(tester, 'Back', ms: 800);
      }
      // The same payment sped up by a child: the pair again.
      if (await _tapText(tester, 'Speed up', ms: 1200)) {
        await _tapText(tester, 'CPFP', ms: 600);
        await _tapText(tester, 'Preview fee bump', ms: 1800);
        await _shot(tester, 'rbf-5-cpfp');
        await _tapText(tester, 'Back', ms: 800);
      }
      if (await _tapText(tester, 'Cancel', ms: 1200)) {
        await _tapText(tester, 'Preview fee bump', ms: 1800);
        await _shot(tester, 'rbf-4-cancel');
        await _tapText(tester, 'Back', ms: 800);
      }
    }

    if (_want('rbf')) {
      // A payment whose fee was raised by a child: one row, the filled
      // yellow "Sped up", and the one window that spells the bump out.
      await tester.runAsync(
        () => FeeBumpStore.instance.add(
          FeeBumpRecord(
            walletId: 'wallet-1',
            originalTxid: '9' * 64,
            replacementTxid: '95b0fa${'c' * 52}8b5fa2',
            method: 'cpfp',
            targetFeeRate: 8,
            newFeeSats: 1000,
            newFeeRate: 8,
            createdAt: DateTime.now(),
          ),
        ),
      );
      await _go(tester, AppRoutes.dashboard, ms: 600);
      await _go(tester, AppRoutes.history, ms: 1800);
      await _shot(tester, 'activity-sped-up');
      if (await _tapText(tester, 'Sped up', ms: 1000)) {
        await _shot(tester, 'activity-sped-up-detail');
        await _tapText(tester, 'Close', last: true);
      }
    }

    if (_want('wizard')) {
      await _go(tester, AppRoutes.walletType, ms: 1500);
      await _shot(tester, 'wizard-1');
      await _tapText(tester, 'One key');
      await _tapText(tester, 'Continue');
      await _shot(tester, 'wizard-2');
      await _tapText(tester, _phone ? 'On this phone' : 'On this computer');
      await _tapText(tester, 'Continue');
      await _shot(tester, 'wizard-3');
      await _tapText(tester, 'Bitcoin + Liquid');
      await _tapText(tester, 'Continue');
      await _shot(tester, 'wizard-4');
      await _type(tester, 'App password', 'correct horse battery staple');
      await _type(tester, 'Confirm password', 'correct horse battery staple');
      for (var i = 5; i <= 8; i++) {
        if (find.text('Continue').hitTestable().evaluate().isEmpty) break;
        await _tapText(tester, 'Continue', ms: 1400);
        await _shot(tester, 'wizard-$i');
      }
    }

    if (_want('create')) {
      await _tapText(tester, 'Start setup', ms: 2200);
      await _shot(tester, 'create-1');
      await _type(tester, 'Wallet name', 'Savings');
      await _tapText(tester, 'Continue', ms: 3000);
      await _shot(tester, 'create-2');
      await _tapText(tester, 'Continue', ms: 1800);
      await _shot(tester, 'create-3');
    }

    if (_want('multisig')) {
      newWalletDraft.liquidEnabled = false;
      newWalletDraft.path = WalletPath.multisig;
      newWalletDraft.watchOnlyFromCosigners = false;
      await _go(tester, AppRoutes.walletPicker, ms: 600);
      await _go(tester, AppRoutes.multisigSetup, ms: 1600);
      await _shot(tester, 'multisig-1');
      await _tapText(tester, 'Continue', ms: 1600);
      await _shot(tester, 'multisig-2');
      // Every key pasted and checked: the next one opens on its own.
      for (final fp in const ['a1b2c3d4', 'b2c3d4e5', 'c3d4e5f6']) {
        await _type(tester, 'Cosigner xpub', "[$fp/48'/1'/0'/2']tpubDMock$fp");
        await _reveal(tester, 'Done with this key');
        await _tapText(tester, 'Done with this key');
        if (fp == 'a1b2c3d4') await _shot(tester, 'multisig-3-one-imported');
      }
      await _shot(tester, 'multisig-4-all-imported');
      await _tapText(tester, 'Continue', ms: 1600);
      await _shot(tester, 'multisig-5-review');
      await _tapText(tester, 'Create wallet', ms: 2500);
      await _shot(tester, 'multisig-6-created');
      // The co-signer role: Key 1 is created and backed up here first.
      await _go(tester, AppRoutes.walletPicker, ms: 600);
      await _go(tester, AppRoutes.multisigSetup, ms: 1600);
      final holds = find.byType(Switch).hitTestable();
      if (holds.evaluate().isNotEmpty) {
        await tester.tap(holds.first, warnIfMissed: false);
        await _wait(tester, 400);
      }
      await _shot(tester, 'multisig-7-holds-key');
      await _tapText(tester, 'Continue', ms: 1600);
      await _shot(tester, 'multisig-8-seed-length');
      await _tapText(tester, 'Continue', ms: 2000);
      await _shot(tester, 'multisig-9-backup');
      await _tapText(tester, 'Continue', ms: 1400);
      await _shot(tester, 'multisig-10-verify');
    }

    for (final scene in const <List<String>>[
      ['import', AppRoutes.importWallet],
      ['watchonly', AppRoutes.watchOnlySetup],
      ['hardware', AppRoutes.hardwareSetup],
      ['airgap', AppRoutes.airgapSetup],
      ['design', AppRoutes.designSystem],
    ]) {
      if (!_want(scene[0])) continue;
      await _go(tester, AppRoutes.walletPicker, ms: 600);
      await _go(tester, scene[1], ms: 1600);
      await _shot(tester, scene[0]);
      if (scene[0] == 'hardware') {
        await _tapText(tester, 'Identify', ms: 2800);
        await _shot(tester, 'hardware-1-identified');
        await _tapText(tester, 'Continue', ms: 1200);
        await _shot(tester, 'hardware-2');
        await _tapText(tester, 'Continue', ms: 1200);
        await _shot(tester, 'hardware-3');
        await _tapText(tester, 'Pair device', ms: 3500);
        await _shot(tester, 'hardware-4');
      }
      if (scene[0] == 'airgap') {
        await _tapText(tester, 'SeedSigner');
        await _shot(tester, 'airgap-1-chosen');
        await _tapText(tester, 'Continue', ms: 1200);
        await _shot(tester, 'airgap-2');
        await _tapText(tester, 'Continue', ms: 1200);
        await _type(
          tester,
          "wpkh([fingerprint/84'/1'/0']tpub…/0/*)",
          "wpkh([a1b2c3d4/84'/1'/0']tpubDMockAirgap/0/*)",
        );
        await _shot(tester, 'airgap-3');
        await _tapText(tester, 'Create wallet', ms: 2500);
        await _shot(tester, 'airgap-4');
      }
    }

    debugPrint('TOUR DONE — $_seq shots in $_out');
    // Unmount so no timer outlives the test.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 30));
    tester.takeException();
  }, skip: _out.isEmpty);
}
