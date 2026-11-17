// Freezing coins: the coin screen's selection bar and details sheet ask the
// engine to freeze, and the send wizard's picker shows a frozen coin without
// letting it be picked. Labelling coins: the label action on a row and on a
// note opens the prompt, and the label lands at once and in the store.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/utxos/models/utxo.dart';
import 'package:templar_wallet/features/utxos/utxo_screen.dart';
import 'package:templar_wallet/services/utxo_label_store.dart';
import 'package:templar_wallet/shared/widgets/utxo_details.dart';
import 'package:templar_wallet/shared/widgets/utxo_views.dart';
import 'package:templar_wallet/theme/app_layout.dart';

const _a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:0';
const _b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb:1';

Utxo _coin(
  String outpoint,
  int sats, {
  UtxoState state = UtxoState.available,
}) => Utxo(
  outpoint: outpoint,
  amount: sats,
  displayAmount: '$sats sats',
  confirmations: 6,
  state: state,
  ticker: 'BTC',
);

/// Keeps the frozen set the way the engine does and answers list_utxos
/// from it.
class _FreezeBridge implements WalletBridge {
  final Set<String> frozen = {};
  final List<(List<String>, bool)> calls = [];

  @override
  Future<List<Utxo>> listUtxos(String walletId, String chain) async => [
    for (final u in [_coin(_a, 90000), _coin(_b, 40000)])
      frozen.contains(u.outpoint) ? u.copyWith(state: UtxoState.frozen) : u,
  ];

  @override
  Future<void> setUtxosFrozen({
    required String walletId,
    required String chain,
    required List<String> outpoints,
    required bool frozen,
  }) async {
    calls.add((outpoints, frozen));
    frozen ? this.frozen.addAll(outpoints) : this.frozen.removeAll(outpoints);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(WalletBridge bridge) => ChangeNotifierProvider<AppState>(
  create: (_) => AppState()..setActiveWallet('w1', name: 'W', type: 'Software'),
  child: MaterialApp(home: UtxoScreen(bridge: bridge)),
);

/// Pumps the screen once its label store is warm: the store reads a real
/// file, which only completes outside the test's fake clock — so it is read
/// here, before any widget (and any font load) exists.
Future<void> _open(WidgetTester t, WalletBridge bridge) async {
  await t.runAsync(() => UtxoLabelStore.instance.getAllLabels());
  await t.pumpWidget(_screen(bridge));
  await t.pumpAndSettle();
}

void _desktopWindow(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 1000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  // The screen reads its view mode and the pending-consolidation list from
  // SharedPreferences, which has no platform side in a widget test.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'the selection bar freezes the selected coin, then unfreezes it',
    (t) async {
      _desktopWindow(t);
      final bridge = _FreezeBridge();
      await _open(t, bridge);

      // List view: rows are easier to target than banknotes.
      await t.tap(find.text('List'));
      await t.pumpAndSettle();
      await t.tap(find.text('90000 sats'));
      await t.pumpAndSettle();
      expect(find.text('Freeze'), findsOneWidget);

      await t.tap(find.text('Freeze'));
      await t.pumpAndSettle();
      expect(bridge.calls.single.$1, [_a]);
      expect(bridge.calls.single.$2, isTrue);
      // Reloaded from the engine: the row wears the tag, the summary line
      // counts it, and the selection is gone.
      expect(find.text('Frozen'), findsOneWidget);
      expect(find.textContaining('1 frozen'), findsOneWidget);
      expect(find.text('Freeze'), findsNothing);
      // Let the confirmation snackbar go: it floats over the bar.
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();

      await t.tap(find.text('90000 sats'));
      await t.pumpAndSettle();
      expect(find.text('Unfreeze'), findsOneWidget);
      await t.tap(find.text('Unfreeze'));
      await t.pumpAndSettle();
      expect(bridge.calls.last.$1, [_a]);
      expect(bridge.calls.last.$2, isFalse);
      expect(find.text('Frozen'), findsNothing);
    },
  );

  testWidgets('the details sheet freezes the one coin it shows', (t) async {
    _desktopWindow(t);
    final bridge = _FreezeBridge();
    await _open(t, bridge);
    await t.tap(find.text('List'));
    await t.pumpAndSettle();

    await t.tap(find.byIcon(Icons.info_outline).last);
    await t.pumpAndSettle();
    expect(find.byType(UtxoDetailsDialog), findsOneWidget);
    await t.tap(find.text('Freeze'));
    await t.pumpAndSettle();
    expect(find.byType(UtxoDetailsDialog), findsNothing);
    expect(bridge.calls.single.$2, isTrue);
    expect(bridge.calls.single.$1, hasLength(1));
  });

  testWidgets('phone: the checkbox selects, the bar freezes, the row opens '
      'the sheet', (t) async {
    AppLayout.debugMobileOverride = true;
    addTearDown(() => AppLayout.debugMobileOverride = null);
    t.view.physicalSize = const Size(411, 914);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final semantics = t.ensureSemantics();
    final bridge = _FreezeBridge();
    await _open(t, bridge);

    expect(find.text('Coins'), findsOneWidget);
    expect(find.text('Notes'), findsNothing);
    expect(find.text('Freeze'), findsNothing);

    await t.tap(find.bySemanticsLabel('Select').first);
    await t.pumpAndSettle();
    expect(find.textContaining('1 selected'), findsOneWidget);
    expect(find.text('Freeze'), findsOneWidget);
    await t.tap(find.text('Freeze'));
    await t.pumpAndSettle();
    expect(bridge.calls.single.$1, [_a]);
    expect(bridge.calls.single.$2, isTrue);

    await t.pump(const Duration(seconds: 5));
    await t.pumpAndSettle();
    await t.tap(find.text('40000 sats'));
    await t.pumpAndSettle();
    expect(find.byType(UtxoDetailsDialog), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the send picker shows a frozen coin but will not pick it', (
    t,
  ) async {
    final picked = <int>[];
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>(
        create: (_) => AppState(),
        child: MaterialApp(
          home: Scaffold(
            body: UtxoPicker(
              utxos: [
                _coin(_a, 90000, state: UtxoState.frozen),
                _coin(_b, 40000),
              ],
              onToggle: picked.add,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('2 coins · 1 frozen'), findsOneWidget);
    expect(find.text('Frozen'), findsOneWidget);
    expect(find.byIcon(kFrozenIcon), findsWidgets);

    await t.tap(find.text('90000 sats'));
    await t.tap(find.text('40000 sats'));
    await t.pump();
    expect(picked, [1], reason: 'only the unfrozen coin is pickable');
  });

  // ── Labels ─────────────────────────────────────────────────────────────────

  group('labels', () {
    late Directory support;
    const channel = MethodChannel('plugins.flutter.io/path_provider');

    setUp(() async {
      support = Directory.systemTemp.createTempSync('utxo_labels_test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => support.path);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      support.deleteSync(recursive: true);
    });

    /// Lets the store's real file write finish outside the fake clock.
    Future<String?> stored(WidgetTester t, String outpoint) async {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      return t.runAsync<String?>(
        () => UtxoLabelStore.instance.getLabel(outpoint),
      );
    }

    testWidgets('a row labels its coin, the note shows it and clears it', (
      t,
    ) async {
      _desktopWindow(t);
      await _open(t, _FreezeBridge());
      await t.tap(find.text('List'));
      await t.pumpAndSettle();

      // Biggest first: the first row's label action is coin _a's.
      await t.tap(find.byTooltip('Add label').first);
      await t.pumpAndSettle();
      expect(find.byType(UtxoLabelPrompt), findsOneWidget);
      await t.enterText(find.byType(TextField), '  Cold storage ');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();

      // On the row at once, trimmed, and the coin was not selected by it.
      expect(find.byType(UtxoLabelPrompt), findsNothing);
      expect(find.text('Cold storage'), findsOneWidget);
      expect(find.text('Freeze'), findsNothing);
      expect(find.textContaining('Could not save'), findsNothing);
      expect(await stored(t, _a), 'Cold storage');

      // The same label on the note; its text is the way back into it.
      await t.tap(find.text('Notes'));
      await t.pumpAndSettle();
      expect(find.text('Cold storage'), findsOneWidget);
      await t.tap(find.text('Cold storage'));
      await t.pumpAndSettle();
      expect(find.text('Edit label'), findsWidgets);
      expect(find.text('Freeze'), findsNothing);
      await t.tap(find.text('Clear label'));
      await t.pumpAndSettle();
      expect(find.text('Cold storage'), findsNothing);
      expect(await stored(t, _a), isNull);
    });

    testWidgets('phone: a row\'s label action opens the prompt', (t) async {
      AppLayout.debugMobileOverride = true;
      addTearDown(() => AppLayout.debugMobileOverride = null);
      t.view.physicalSize = const Size(411, 914);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await _open(t, _FreezeBridge());

      await t.tap(find.byTooltip('Add label').last);
      await t.pumpAndSettle();
      // The details sheet did not open: the label action is its own target.
      expect(find.byType(UtxoDetailsDialog), findsNothing);
      await t.enterText(find.byType(TextField), 'Rent');
      await t.tap(find.text('Save'));
      await t.pumpAndSettle();
      expect(find.text('Rent'), findsOneWidget);
      expect(await stored(t, _b), 'Rent');
      await t.runAsync(() => UtxoLabelStore.instance.setLabel(_b, ''));
    });
  });
}
