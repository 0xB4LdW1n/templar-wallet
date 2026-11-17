// A fee bump is one payment whose fee was changed, not two payments: the
// child of a CPFP and the loser of a replacement are folded into the one
// transaction the user means, which then carries what was done to it.
import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/features/history/fee_bump_fold.dart';
import 'package:templar_wallet/features/history/models/transaction.dart';
import 'package:templar_wallet/services/fee_bump_store.dart';

final _a = 'a' * 64;
final _b = 'b' * 64;
final _c = 'c' * 64;
final _other = 'f' * 64;

Transaction _tx(
  String txid, {
  TxDirection direction = TxDirection.outgoing,
  int confirmations = 0,
  String amount = '-0.00040141 BTC',
  int? feeSats,
}) => Transaction(
  txid: txid,
  direction: direction,
  chain: TxChain.bitcoin,
  amount: amount,
  ticker: 'BTC',
  timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  confirmations: confirmations,
  feeSats: feeSats,
);

FeeBumpRecord _record(
  String original,
  String replacement,
  String method, {
  int fee = 1128,
  double rate = 8,
}) => FeeBumpRecord(
  walletId: 'w1',
  originalTxid: original,
  replacementTxid: replacement,
  method: method,
  targetFeeRate: rate,
  newFeeSats: fee,
  newFeeRate: rate,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  test('no records: the list is left as it is', () {
    final txs = [_tx(_a), _tx(_b)];
    expect(foldFeeBumps(txs, const []), same(txs));
  });

  group('CPFP', () {
    test('an incoming payment and its child are one row: the payment', () {
      final parent = _tx(
        _a,
        direction: TxDirection.incoming,
        amount: '+0.00141193 BTC',
      );
      // The child is a transfer to oneself whose "amount" is its fee.
      final child = _tx(
        _b,
        direction: TxDirection.self,
        amount: '-0.00001787 BTC',
        feeSats: 1787,
      );
      final folded = foldFeeBumps(
        [child, parent, _tx(_other)],
        [_record(_a, _b, 'cpfp', fee: 1787, rate: 12.5)],
      );

      expect(folded.map((t) => t.txid), [_a, _other]);
      final bump = folded.first.bump!;
      expect(bump.isCpfp, isTrue);
      expect(bump.otherTxid, _b);
      expect(bump.feeSats, 1787);
      expect(bump.feeRate, 12.5);
      expect(bump.otherConfirmed, isFalse);
      // The payment is still the payment.
      expect(folded.first.amount, '+0.00141193 BTC');
      expect(folded.first.title, 'Received');
      expect(folded.last.bump, isNull);
    });

    test('still one row once both have confirmed', () {
      final folded = foldFeeBumps(
        [
          _tx(_a, direction: TxDirection.incoming, confirmations: 3),
          _tx(_b, direction: TxDirection.self, confirmations: 3),
        ],
        [_record(_a, _b, 'cpfp')],
      );
      expect(folded, hasLength(1));
      expect(folded.single.txid, _a);
      expect(folded.single.bump!.otherConfirmed, isTrue);
    });

    test('a child no sync has listed yet is still told from the record', () {
      final folded = foldFeeBumps(
        [_tx(_a, direction: TxDirection.incoming)],
        [_record(_a, _b, 'cpfp', fee: 1000)],
      );
      expect(folded.single.bump!.otherTxid, _b);
      expect(folded.single.bump!.feeSats, 1000);
    });

    test('a child whose parent is not listed keeps its own row', () {
      final folded = foldFeeBumps([_tx(_b)], [_record(_a, _b, 'cpfp')]);
      expect(folded.single.txid, _b);
      expect(folded.single.bump, isNull);
    });
  });

  group('RBF', () {
    test('the replaced transaction goes; the replacement carries the bump', () {
      final folded = foldFeeBumps(
        [_tx(_b), _tx(_a)],
        [_record(_a, _b, 'rbf', fee: 1128, rate: 8)],
      );
      expect(folded.map((t) => t.txid), [_b]);
      final bump = folded.single.bump!;
      expect(bump.method, 'rbf');
      expect(bump.otherTxid, _a);
      expect(bump.feeSats, 1128);
      expect(bump.awaitingSync, isFalse);
    });

    test('before a sync lists the replacement, the original stands for it', () {
      final folded = foldFeeBumps([_tx(_a)], [_record(_a, _b, 'rbf')]);
      expect(folded.single.txid, _a);
      final bump = folded.single.bump!;
      expect(bump.awaitingSync, isTrue);
      expect(bump.otherTxid, _b);
    });

    test('a chain of replacements is one row: the latest listed', () {
      final folded = foldFeeBumps(
        [_tx(_c), _tx(_b), _tx(_a)],
        [_record(_a, _b, 'rbf'), _record(_b, _c, 'rbf', fee: 2000)],
      );
      expect(folded.map((t) => t.txid), [_c]);
      expect(folded.single.bump!.otherTxid, _b);
      expect(folded.single.bump!.feeSats, 2000);
    });

    test('whichever confirmed is the one that stays', () {
      // The original confirmed first: the replacement lost the race.
      final folded = foldFeeBumps(
        [_tx(_b), _tx(_a, confirmations: 2)],
        [_record(_a, _b, 'rbf')],
      );
      expect(folded.single.txid, _a);
      expect(folded.single.bump, isNull);
    });
  });

  test('a list of bare txids loses the same rows (the Dashboard)', () {
    final hidden = feeBumpHiddenTxids(
      {_a: false, _b: false, _c: true, _other: false},
      [_record(_a, _b, 'cpfp'), _record(_other, _c, 'rbf')],
    );
    // The CPFP child, and the original a confirmed replacement beat.
    expect(hidden, {_b, _other});
    expect(feeBumpHiddenTxids({_a: false}, const []), isEmpty);
  });

  group('cancel', () {
    test('the cancelling transaction is the row, and says what it is', () {
      final folded = foldFeeBumps(
        [_tx(_b, direction: TxDirection.self), _tx(_a)],
        [_record(_a, _b, 'cancel')],
      );
      expect(folded.single.txid, _b);
      expect(folded.single.bump!.isCancel, isTrue);
      expect(folded.single.title, 'Cancellation');
    });

    test('confirmed, it is a cancelled payment', () {
      final folded = foldFeeBumps(
        [_tx(_b, direction: TxDirection.self, confirmations: 1)],
        [_record(_a, _b, 'cancel')],
      );
      expect(folded.single.title, 'Cancelled payment');
    });
  });
}
