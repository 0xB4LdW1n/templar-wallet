// The notes wall keeps every coin in the tray of the address it sits on:
// the address is the parent, the notes are what is in it. Two coins on one
// address share a tray — the fact a list of outpoints never shows — and an
// address carries the label Receive gave it, here as there. Each address is
// a card of its own, and an address is grey until the user colours it.
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/utxos/models/utxo.dart';
import 'package:templar_wallet/features/utxos/utxo_screen.dart';
import 'package:templar_wallet/features/utxos/utxo_wall.dart';
import 'package:templar_wallet/services/address_label_store.dart';
import 'package:templar_wallet/services/utxo_label_store.dart';
import 'package:templar_wallet/shared/widgets/address_tag.dart';
import 'package:templar_wallet/shared/widgets/live_edge.dart';
import 'package:templar_wallet/shared/widgets/utxo_views.dart';
import 'package:templar_wallet/theme/app_scheme.dart';
import 'package:templar_wallet/theme/app_spacing.dart';

const _savings = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';
const _exchange = 'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a';

Utxo _coin(
  String id,
  int sats, {
  String? address,
  UtxoState state = UtxoState.available,
}) => Utxo(
  outpoint: '${id * 64}:0',
  amount: sats,
  displayAmount: '$sats sats',
  confirmations: state == UtxoState.unconfirmed ? 0 : 6,
  state: state,
  ticker: 'BTC',
  address: address,
);

/// Two coins on the savings address, one settled and one arriving on the
/// exchange address.
final _coins = [
  _coin('a', 30000, address: _savings),
  _coin('b', 90000, address: _savings),
  _coin('c', 20000, address: _exchange),
  _coin('d', 5000, address: _exchange, state: UtxoState.unconfirmed),
];

class _Bridge implements WalletBridge {
  /// How many times the coins were read.
  int reads = 0;

  @override
  Future<List<Utxo>> listUtxos(String walletId, String chain) async {
    reads++;
    return _coins;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen({_Bridge? bridge, AppState? state}) =>
    ChangeNotifierProvider<AppState>.value(
      value:
          state ??
          (AppState()..setActiveWallet('w1', name: 'W', type: 'Software')),
      child: MaterialApp(home: UtxoScreen(bridge: bridge ?? _Bridge())),
    );

/// One coin of the set is still arriving, and its note's spinner is live: the
/// tree never settles. A few frames across the longest transition is enough.
Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _open(
  WidgetTester t, {
  _Bridge? bridge,
  AppState? state,
  Size size = const Size(1400, 1000),
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  // The coin-label store reads a real file, which only completes outside
  // the test's fake clock.
  await t.runAsync(() => UtxoLabelStore.instance.getAllLabels());
  await t.pumpWidget(_screen(bridge: bridge, state: state));
  await _settle(t);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddressLabelStore.instance.debugReset();
  });

  group('groupCoinsByAddress', () {
    test('one group per address, the fullest first', () {
      final groups = groupCoinsByAddress(_coins);
      expect(groups.map((g) => g.address), [_savings, _exchange]);
      expect(groups.first.total, 120000);
      expect(groups.last.total, 25000);
    });

    test('inside a group: settled coins by size, then what is arriving', () {
      final groups = groupCoinsByAddress(_coins);
      // Savings: 90000 (index 1) before 30000 (index 0).
      expect(groups.first.indices, [1, 0]);
      // Exchange: the settled 20000 before the pending 5000.
      expect(groups.last.indices, [2, 3]);
    });

    test(
      'coins the engine named no address for share a group of their own',
      () {
        final groups = groupCoinsByAddress([
          _coin('a', 1000),
          _coin('b', 5000, address: _savings),
          _coin('c', 2000, address: ''),
        ]);
        expect(groups.map((g) => g.address), [_savings, null]);
        expect(groups.last.indices, [2, 0]);
      },
    );
  });

  group('the wall', () {
    testWidgets('every address is a card, and coins on one address share it', (
      t,
    ) async {
      await _open(t);
      expect(find.byType(AddressTray), findsNWidgets(2));
      // Three settled coins are banknotes; the one arriving is provisional.
      expect(find.byType(UtxoBanknote), findsNWidgets(3));
      expect(find.byType(PendingCoinNote), findsOneWidget);
      // A card says how many coins it holds and what they add up to.
      expect(find.text('2 coins'), findsNWidgets(2));
      expect(find.text('0.00120000 BTC'), findsOneWidget);
      expect(find.text('0.00025000 BTC'), findsOneWidget);
      // Each tray is named by its address until the user names it.
      expect(find.text(shortCoinAddress(_savings)), findsOneWidget);
      expect(find.text(shortCoinAddress(_exchange)), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('both notes of an address sit inside its card', (t) async {
      await _open(t);
      final tray = find.ancestor(
        of: find.text('0.00120000 BTC'),
        matching: find.byType(AddressTray),
      );
      expect(
        find.descendant(of: tray, matching: find.byType(UtxoBanknote)),
        findsNWidgets(2),
      );
      // The bigger coin's note is the longer one: same height, more paper.
      final notes = t
          .widgetList<UtxoBanknote>(
            find.descendant(of: tray, matching: find.byType(UtxoBanknote)),
          )
          .toList();
      expect(notes.first.utxo.amount, 90000);
      expect(
        notes.first.tier.size.width,
        greaterThan(notes.last.tier.size.width),
      );
      expect(notes.first.tier.size.height, notes.last.tier.size.height);
    });

    testWidgets('a tray is named by the label Receive gave its address', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        'address_labels_v1': json.encode({_savings: 'Savings'}),
      });
      await _open(t);
      expect(find.textContaining('Savings'), findsOneWidget);
      // The address stays beside its name.
      expect(find.textContaining(shortCoinAddress(_savings)), findsOneWidget);
    });

    testWidgets('the card labels its address from its head', (t) async {
      await _open(t);
      final tray = find.ancestor(
        of: find.text('0.00120000 BTC'),
        matching: find.byType(AddressTray),
      );
      // The head's controls come with the pointer.
      final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(t.getCenter(tray));
      await _settle(t);

      await t.tap(
        find.descendant(of: tray, matching: find.byIcon(Icons.label_outlined)),
      );
      await _settle(t);
      await t.enterText(find.byType(TextField), 'Rent');
      await t.tap(find.text('Save'));
      await _settle(t);

      expect(AddressLabelStore.instance.labelFor(_savings), 'Rent');
      expect(find.textContaining('Rent'), findsOneWidget);
      // Labelling an address picks no coin.
      expect(find.textContaining('selected'), findsNothing);
    });
  });

  group('the card of an address', () {
    testWidgets('its label is a tag in the colour the user picked, and its '
        'swatch wears it', (t) async {
      SharedPreferences.setMockInitialValues({
        'address_labels_v1': json.encode({_savings: 'Savings'}),
        'address_label_hues_v1': json.encode({_savings: 3}),
      });
      await _open(t);
      final s = AppScheme.of(t.element(find.byType(UtxoScreen)));
      final hue = tagHue(s, 3);

      final tray = find.ancestor(
        of: find.text('Savings'),
        matching: find.byType(AddressTray),
      );
      final tag = t.widget<AddressTag>(
        find.descendant(of: tray, matching: find.byType(AddressTag)),
      );
      expect(tag.label, 'Savings');
      expect(tag.hue, hue);
      final swatch = t.widget<AddressSwatch>(
        find.descendant(of: tray, matching: find.byType(AddressSwatch)),
      );
      expect(swatch.hue, hue);
    });

    testWidgets('an address nobody coloured is grey, labelled or not', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        'address_labels_v1': json.encode({_savings: 'Savings'}),
      });
      await _open(t);
      final s = AppScheme.of(t.element(find.byType(UtxoScreen)));
      final grey = tagHue(s, AddressLabelStore.greyHue);
      expect(grey, s.hueSlate);
      for (final tray in t.widgetList<AddressTray>(find.byType(AddressTray))) {
        final swatch = t.widget<AddressSwatch>(
          find.descendant(
            of: find.byWidget(tray),
            matching: find.byType(AddressSwatch),
          ),
        );
        expect(swatch.hue, grey);
      }
      // The label is a grey tag; the unlabelled address is printed as it is.
      expect(t.widget<AddressTag>(find.byType(AddressTag)).hue, grey);
      expect(find.text(shortCoinAddress(_exchange)), findsOneWidget);
    });

    testWidgets('every address is a card of the kit: panel, hairline, no '
        'colour of its own', (t) async {
      await _open(t);
      final s = AppScheme.of(t.element(find.byType(UtxoScreen)));
      expect(find.byType(AddressCards), findsOneWidget);
      for (final tray in t.widgetList<AddressTray>(find.byType(AddressTray))) {
        final card =
            t
                    .widget<Container>(
                      find
                          .descendant(
                            of: find.byWidget(tray),
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration!
                as BoxDecoration;
        expect(card.color, s.panel);
        expect((card.border! as Border).top.color, s.edge);
        expect(card.borderRadius, BorderRadius.circular(AppSpacing.radiusLg));
        // No coloured spine or band: nothing solid in the card.
        expect(
          find.descendant(
            of: find.byWidget(tray),
            matching: find.byType(ColoredBox),
          ),
          findsNothing,
        );
      }
    });

    testWidgets('the cards stack: one width, the addresses and the first '
        'notes on one line', (t) async {
      await _open(t);
      final trays = t
          .widgetList<AddressTray>(find.byType(AddressTray))
          .map(find.byWidget)
          .toList();
      expect(trays, hasLength(2));
      // Every card is the page's whole width, one under the other, apart.
      expect(trays.map((f) => t.getSize(f).width).toSet(), hasLength(1));
      expect(trays.map((f) => t.getTopLeft(f).dx).toSet(), hasLength(1));
      expect(
        t.getTopLeft(trays.last).dy,
        greaterThanOrEqualTo(
          t.getBottomLeft(trays.first).dy + AddressCards.gap,
        ),
      );
      // The addresses start on one line, and so do the first notes.
      final names = [
        _savings,
        _exchange,
      ].map((a) => t.getTopLeft(find.text(shortCoinAddress(a))).dx);
      expect(names.toSet(), hasLength(1));
      final firstNotes = trays.map(
        (f) => t
            .getTopLeft(
              find.descendant(of: f, matching: find.byType(UtxoBanknote)).first,
            )
            .dx,
      );
      expect(firstNotes.toSet(), hasLength(1));
    });

    test('a note\'s seal stands clear of its figures', () {
      for (final tier in BanknoteTier.values) {
        final width = tier.size.width;
        final column = NoteFace.columnOf(width, min: tier.column);
        final seal = NoteFace.sealOf(width, min: tier.column);
        // Edge, inset, the writing, a gap, the seal, its inset from the
        // frame and the frame's from the edge: never more than the paper.
        expect(1 + NoteFace.inset + column, lessThan(width));
        expect(
          1 +
              NoteFace.inset +
              column +
              NoteFace.gap +
              seal +
              2 * NoteFace.frame,
          lessThanOrEqualTo(width),
        );
        // Every note carries one, and a longer note never a smaller one.
        expect(seal, greaterThanOrEqualTo(32));
        expect(seal, lessThanOrEqualTo(NoteFace.sealMax));
      }
      final seals = [
        for (final tier in BanknoteTier.values)
          NoteFace.sealOf(tier.size.width, min: tier.column),
      ];
      expect(seals, [...seals]..sort());
    });

    testWidgets('a coin on its way is a grey note with a running edge', (
      t,
    ) async {
      await _open(t);
      final note = find.byType(ProvisionalNote);
      expect(note, findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('Waiting for confirmation'), findsOneWidget);
      final edge = t.widget<LiveEdge>(
        find.descendant(of: note, matching: find.byType(LiveEdge)),
      );
      expect(edge.mode, LiveEdgeMode.working);
      final s = AppScheme.of(t.element(note));
      final paper = t
          .widgetList<Container>(
            find.descendant(of: note, matching: find.byType(Container)),
          )
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .first;
      // Drained to iron: the raised grey, not a tier's hue.
      expect(paper.color, s.panelInset);
    });
  });

  group('after a sync', () {
    testWidgets('the coins are read again, and a selection survives it', (
      t,
    ) async {
      final bridge = _Bridge();
      final state = AppState()
        ..setActiveWallet('w1', name: 'W', type: 'Software');
      await _open(t, bridge: bridge, state: state);
      expect(bridge.reads, 1);

      // Pick the 90,000 sat coin, then a sync finishes.
      await t.tap(find.text('90000 sats'));
      await _settle(t);
      expect(find.textContaining('1 selected'), findsWidgets);

      state.bumpSync();
      await t.runAsync(() => UtxoLabelStore.instance.getAllLabels());
      await _settle(t);

      expect(bridge.reads, 2);
      expect(find.textContaining('1 selected'), findsWidgets);
    });
  });

  group('on a phone', () {
    setUp(() => AppLayout.debugMobileOverride = true);
    tearDown(() => AppLayout.debugMobileOverride = null);

    testWidgets('the coins are grouped under their address, a card each', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({
        'address_labels_v1': json.encode({_savings: 'Savings'}),
      });
      await _open(t, size: const Size(411, 2000));

      expect(find.byType(AddressCards), findsOneWidget);
      expect(find.byType(AddressCoinGroup), findsNWidgets(2));
      final savings = find.ancestor(
        of: find.text('Savings'),
        matching: find.byType(AddressCoinGroup),
      );
      // Both coins of the address are rows of its section, under its head.
      expect(
        find.descendant(of: savings, matching: find.byType(CoinRow)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: savings,
          matching: find.text(
            '${shortCoinAddress(_savings)} · 2 coins · 0.00120000 BTC',
          ),
        ),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('the head of a section labels its address', (t) async {
      await _open(t, size: const Size(411, 2000));
      await t.tap(find.text(shortCoinAddress(_exchange)));
      await _settle(t);
      await t.enterText(find.byType(TextField), 'Exchange');
      await t.tap(find.text('Save'));
      await _settle(t);

      expect(AddressLabelStore.instance.labelFor(_exchange), 'Exchange');
      expect(find.text('Exchange'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('names each coin\'s address and sorts coins by it', (t) async {
      SharedPreferences.setMockInitialValues({
        'address_labels_v1': json.encode({_exchange: 'Exchange'}),
      });
      await _open(t);
      await t.tap(find.text('List'));
      await _settle(t);

      // The label over the address, once per coin on it.
      expect(find.text('Exchange'), findsNWidgets(2));
      expect(find.text(shortCoinAddress(_savings)), findsNWidgets(2));

      // Sorting by address brings a named address's coins together, first.
      await t.tap(find.text('Address'));
      await _settle(t);
      await t.tap(find.text('Address'));
      await _settle(t);
      final rows = t.widgetList<CoinRow>(find.byType(CoinRow)).toList();
      // Pending coins lead whatever the sort; then the named address.
      expect(rows.map((r) => r.utxo.amount), [5000, 20000, 90000, 30000]);
    });
  });
}
