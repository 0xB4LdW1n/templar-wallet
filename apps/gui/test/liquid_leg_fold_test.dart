// A Liquid transaction is one row, whatever it moved: the engine lists it
// once per asset, and the rows of one txid are folded into one transaction.
// An L-BTC row that is nothing but the network fee becomes that
// transaction's fee instead of a payment of its own.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/history/history_screen.dart';
import 'package:templar_wallet/features/history/liquid_leg_fold.dart';
import 'package:templar_wallet/features/history/models/transaction.dart';

final _a = '775407${'a' * 52}0a4a7d';
final _b = 'b' * 64;

Transaction _row(
  String txid,
  String amount,
  String ticker, {
  TxDirection direction = TxDirection.outgoing,
  TxChain chain = TxChain.liquid,
  int? feeSats,
  int confirmations = 1,
}) => Transaction(
  txid: txid,
  direction: direction,
  chain: chain,
  amount: amount,
  ticker: ticker,
  timestamp: DateTime.fromMillisecondsSinceEpoch(1790000000000),
  confirmations: confirmations,
  fee: feeSats == null ? null : '$feeSats sats',
  feeSats: feeSats,
);

/// A token sent, as the engine lists it: the L-BTC that paid the fee first
/// (the fee rides on the first row), then the token.
List<Transaction> _tokenSend() => [
  _row(_a, '-0.00000033 LBTC', 'LBTC', feeSats: 33),
  _row(_a, '-0.00004000 38fca2d9', '38fca2d9'),
];

class _Bridge implements WalletBridge {
  @override
  Future<List<Transaction>> listActivity(
    String walletId, {
    String? chain,
    String? asset,
  }) async => _tokenSend();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('a transaction listed once is left as it is', () {
    final txs = [
      _row(_a, '-0.00100033 LBTC', 'LBTC', feeSats: 33),
      _row(_b, '-0.00040141 BTC', 'BTC', chain: TxChain.bitcoin),
    ];
    expect(foldLiquidLegs(txs), same(txs));
  });

  test('a token sent is one row: the token, and the fee it cost', () {
    final folded = foldLiquidLegs(_tokenSend());
    expect(folded, hasLength(1));
    final tx = folded.single;
    expect(tx.amount, '-0.00004000 38fca2d9');
    expect(tx.ticker, '38fca2d9');
    expect(tx.title, 'Sent');
    expect(tx.feeSats, 33);
    expect(tx.fee, '33 sats');
    expect(tx.feeLegFolded, isTrue);
    expect(tx.legs, isEmpty);
  });

  test('an asset issued is one row: the asset received, the fee paid', () {
    final tx = foldLiquidLegs([
      _row(_a, '-0.00000041 LBTC', 'LBTC', feeSats: 41),
      _row(_a, '+1000 TMPL', 'TMPL', direction: TxDirection.incoming),
    ]).single;
    expect(tx.amount, '+1000 TMPL');
    expect(tx.title, 'Received');
    expect(tx.feeLegFolded, isTrue);
  });

  test('L-BTC paid for a token is a swap: both figures, one row', () {
    final tx = foldLiquidLegs([
      // More than the fee left: this row is a payment, and stays.
      _row(_a, '-0.00010033 LBTC', 'LBTC', feeSats: 33),
      _row(_a, '+5.00 TMPL', 'TMPL', direction: TxDirection.incoming),
    ]).single;
    expect(tx.amount, '-0.00010033 LBTC');
    expect(tx.feeLegFolded, isFalse);
    expect(tx.legs.single.amount, '+5.00 TMPL');
    expect(tx.legs.single.direction, TxDirection.incoming);
    expect(tx.isExchange, isTrue);
    expect(tx.title, 'Swap');
  });

  test('a token received is not charged the sender\'s fee', () {
    // One row, and it carries the transaction's fee — which this wallet did
    // not pay. Nothing to fold, nothing marked.
    final txs = [
      _row(
        _a,
        '+12 TMPL',
        'TMPL',
        direction: TxDirection.incoming,
        feeSats: 33,
      ),
    ];
    expect(foldLiquidLegs(txs).single.feeLegFolded, isFalse);
  });

  test(
    'order is kept, and a Bitcoin txid is never folded with a Liquid one',
    () {
      final btc = _row(_a, '-0.00000033 BTC', 'BTC', chain: TxChain.bitcoin);
      final other = _row(
        _b,
        '+0.00200000 LBTC',
        'LBTC',
        direction: TxDirection.incoming,
      );
      final folded = foldLiquidLegs([btc, ..._tokenSend(), other]);
      expect(folded.map((t) => t.chain), [
        TxChain.bitcoin,
        TxChain.liquid,
        TxChain.liquid,
      ]);
      expect(folded[0], same(btc));
      expect(folded[1].ticker, '38fca2d9');
      expect(folded[2], same(other));
    },
  );

  group('Activity', () {
    setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('lists a token sent once, with its fee beside the amount', (
      t,
    ) async {
      t.view.physicalSize = const Size(1400, 1400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) =>
              AppState()
                ..setActiveWallet('w1', name: 'Wallet', type: 'Software'),
          child: MaterialApp(home: HistoryScreen(bridge: _Bridge())),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Sent'), findsOneWidget);
      expect(find.textContaining('0.00004000 38fca2d9'), findsOneWidget);
      // The 33 sats are the fee of that row, not a second payment.
      expect(find.textContaining('Fee '), findsOneWidget);

      await t.tap(find.text('Sent'));
      await t.pumpAndSettle();
      expect(find.text('Network fee'), findsOneWidget);
    });
  });
}
