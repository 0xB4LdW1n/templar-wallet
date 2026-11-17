import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/history/activity_rows.dart';
import 'package:templar_wallet/features/history/activity_sources.dart';
import 'package:templar_wallet/features/history/history_screen.dart';
import 'package:templar_wallet/features/history/models/activity_entry.dart';
import 'package:templar_wallet/features/history/models/transaction.dart';
import 'package:templar_wallet/features/peg/models/peg_models.dart';
import 'package:templar_wallet/features/protocol/models/protocol_portfolio.dart';
import 'package:templar_wallet/features/swap/models/swap_offer.dart';
import 'package:templar_wallet/shared/widgets/list_rows.dart';

const _depositTxid =
    'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';

Transaction _tx(
  String txid, {
  required DateTime at,
  int confirmations = 6,
  TxChain chain = TxChain.bitcoin,
  String? note,
}) => Transaction(
  txid: txid,
  direction: TxDirection.outgoing,
  chain: chain,
  amount: '-0.001 BTC',
  ticker: 'BTC',
  timestamp: at,
  confirmations: confirmations,
  note: note,
);

PegOrder _peg({
  required DateTime created,
  String status = 'completed',
  String? deposit,
}) => PegOrder.fromJson({
  'order_id': 'pg_1',
  'wallet_id': 'w1',
  'direction': 'in',
  'status': status,
  'deposit_expected_sats': 500000,
  'payout_expected_sats': 499250,
  'created_at': created.millisecondsSinceEpoch ~/ 1000,
  'updated_at': created.millisecondsSinceEpoch ~/ 1000,
  'txid_deposit': deposit,
  'simulated': true,
});

MyOffer _offer({required DateTime created, String status = 'open'}) =>
    MyOffer.fromJson({
      'offer_id': 'of_1',
      'status': status,
      'created_at': created.millisecondsSinceEpoch ~/ 1000,
      'offers': {
        'asset_id': 'l',
        'ticker': 'L-BTC',
        'amount_sats': 25000,
        'display_amount': '0.00025000',
      },
      'wants': {
        'asset_id': 'u',
        'ticker': 'USDT',
        'amount_sats': 2500000000,
        'display_amount': '25.00',
      },
    });

class _Bridge implements WalletBridge {
  _Bridge({this.failPegs = false});
  final bool failPegs;
  final DateTime now = DateTime.now();

  @override
  Future<List<Transaction>> listActivity(
    String walletId, {
    String? chain,
    String? asset,
  }) async => [
    _tx('a' * 64, at: now.subtract(const Duration(hours: 1)), note: 'Rent'),
    // The peg's deposit: the same event as the peg, folded into it.
    _tx(_depositTxid, at: now.subtract(const Duration(days: 2))),
  ];

  @override
  Future<List<PegOrder>> pegList(String walletId) async {
    if (failPegs) throw Exception('peg provider down');
    return [
      _peg(
        created: now.subtract(const Duration(days: 2)),
        deposit: _depositTxid,
      ),
    ];
  }

  @override
  Future<List<MyOffer>> listMyOffers(String walletId) async => [
    _offer(created: now.subtract(const Duration(days: 9))),
  ];

  @override
  Future<List<AtomicSwap>> atomicSwapList(String walletId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<List<ActivityEntry>> _loans(String walletId, String? name) async => [
  LoanEntry(
    siteName: 'Templar Protocol demo',
    loan: ProtocolLoan(
      id: 42,
      ref: 'SQ-42',
      role: 'borrower',
      state: ProtocolLoanState.active,
      rawState: 'active',
      principal: const ProtocolMoney(ticker: 'USDT', amount: '600'),
      openedAt: DateTime.now().toUtc().subtract(const Duration(days: 5)),
      repaymentPlan: const ProtocolRepaymentPlan(
        kind: 'installments',
        nTotal: 6,
        nPaid: 2,
      ),
    ),
  ),
];

Widget _screen(WalletBridge bridge) => ChangeNotifierProvider<AppState>(
  create: (_) {
    final st = AppState()
      ..setActiveWallet(
        'w1',
        name: 'Wallet',
        type: 'Software',
        liquid: true,
        bitcoin: true,
      );
    st.setPegEnabled(true);
    st.setLiquidDexEnabled(true);
    st.setLoansEnabled(true);
    return st;
  },
  child: MaterialApp(
    home: HistoryScreen(bridge: bridge, loans: _loans),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ActivitySources.clearCache();
  });

  group('merged timeline', () {
    final now = DateTime(2026, 11, 13, 12);

    test('pending first, newest first, undated last, grouped by day', () {
      final timeline = mergeActivity(
        [
          _tx('1' * 64, at: DateTime(2026, 11, 12, 9)),
          _tx(
            '2' * 64,
            at: DateTime.fromMillisecondsSinceEpoch(0),
            confirmations: 0,
          ),
        ],
        [
          PegEntry(_peg(created: DateTime(2026, 11, 13, 8))),
          LiquidexSwapEntry(_offer(created: DateTime(2026, 11, 13, 10))),
          LiquidexSwapEntry(
            _offer(created: DateTime(2026, 11, 1), status: 'closed'),
          ),
        ],
      );
      final groups = groupActivity(timeline.entries, now: now);
      expect(groups.map((g) => g.label), [
        'Pending',
        'Today',
        'Yesterday',
        '1 Nov 2026',
      ]);
      // The unconfirmed payment (no block time) leads the pending group,
      // ahead of the open offer.
      expect(groups[0].entries.map((e) => e.kind), [
        ActivityKind.payment,
        ActivityKind.swap,
      ]);
      expect(groups[1].entries.single.kind, ActivityKind.peg);
      expect(groups[2].entries.single.kind, ActivityKind.payment);
    });

    test('an entry without a date sinks to "Undated"', () {
      final sorted = sortActivity([
        PegEntry(_peg(created: DateTime.fromMillisecondsSinceEpoch(0))),
        LiquidexSwapEntry(_offer(created: now, status: 'cancelled')),
      ]);
      expect(sorted.last, isA<PegEntry>());
      expect(activityGroupLabel(sorted.last, now: now), 'Undated');
    });

    test('a transaction a peg owns is folded into the peg', () {
      final timeline = mergeActivity(
        [_tx(_depositTxid, at: now), _tx('e' * 64, at: now)],
        [PegEntry(_peg(created: now, deposit: _depositTxid))],
      );
      expect(timeline.entries.length, 2);
      expect(timeline.entries.whereType<PaymentEntry>().map((e) => e.tx.txid), [
        'e' * 64,
      ]);
      expect(timeline.linked.keys, [_depositTxid]);
      final peg = timeline.entries.whereType<PegEntry>().single;
      expect(peg.txids, [_depositTxid]);
    });

    test('filters by chain, kind and search together', () {
      final entries = mergeActivity(
        [_tx('f' * 64, at: now, chain: TxChain.liquid)],
        [PegEntry(_peg(created: now)), LiquidexSwapEntry(_offer(created: now))],
      ).entries;
      expect(filterActivity(entries, chain: 'bitcoin').map((e) => e.kind), [
        ActivityKind.peg,
      ]);
      expect(
        filterActivity(entries, kind: ActivityKind.swap).single,
        isA<LiquidexSwapEntry>(),
      );
      expect(filterActivity(entries, query: 'peg-in').single, isA<PegEntry>());
    });

    test('a peg states its step and never a confirmation count', () {
      final peg = PegEntry(_peg(created: now, status: 'confirming'));
      expect(peg.isPending, isTrue);
      expect(peg.facts, contains('step 3 of 5'));
      expect(peg.status.tone, ActivityTone.wait);
      expect(peg.facts.join(' '), isNot(contains('confirmation')));
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, WalletBridge bridge) async {
      tester.view.physicalSize = const Size(1400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_screen(bridge));
      await tester.pumpAndSettle();
    }

    testWidgets('payments, loans, swaps and pegs share one list', (
      tester,
    ) async {
      await pump(tester, _Bridge());
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Peg-in'), findsOneWidget);
      expect(find.text('LiquiDEX swap'), findsOneWidget);
      expect(find.text('Loan SQ-42'), findsOneWidget);
      // The peg's deposit is not listed a second time as a payment.
      expect(find.text('Sent'), findsNothing);
    });

    testWidgets('a loan, a swap and a peg wear the payment\'s iron tile', (
      tester,
    ) async {
      await pump(tester, _Bridge());
      final glyphs = find.byType(ActivityKindGlyph);
      expect(glyphs, findsWidgets);
      // Every kind's glyph sits on the list's neutral tile: the kind is told
      // by the glyph and the title, not by a colour.
      for (final e in glyphs.evaluate()) {
        expect(
          find.descendant(
            of: find.byWidget(e.widget),
            matching: find.byType(ListIconTile),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('the kind filter keeps one kind', (tester) async {
      await pump(tester, _Bridge());
      await tester.tap(find.text('Pegs'));
      await tester.pumpAndSettle();
      expect(find.text('Peg-in'), findsOneWidget);
      expect(find.text('Rent'), findsNothing);
      expect(find.text('Loan SQ-42'), findsNothing);

      await tester.tap(find.text('Loans'));
      await tester.pumpAndSettle();
      expect(find.text('Loan SQ-42'), findsOneWidget);
      expect(find.text('Peg-in'), findsNothing);
    });

    testWidgets('a failing source does not blank the list', (tester) async {
      await pump(tester, _Bridge(failPegs: true));
      expect(find.text('Rent'), findsOneWidget);
      expect(find.text('Loan SQ-42'), findsOneWidget);
      expect(find.text('Peg-in'), findsNothing);
      expect(find.text('Could not load pegs'), findsOneWidget);
      // Without its peg, the deposit is an ordinary payment again.
      expect(find.text('Sent'), findsOneWidget);
    });

    testWidgets('a peg opens its detail with its txid', (tester) async {
      await pump(tester, _Bridge());
      await tester.tap(find.text('Peg-in'));
      await tester.pumpAndSettle();
      expect(find.text('Open Peg'), findsOneWidget);
      expect(find.text('View in explorer'), findsOneWidget);
      expect(find.textContaining('dddddd'), findsWidgets);
    });
  });
}
