enum TxDirection { incoming, outgoing, self }

enum TxChain { bitcoin, liquid }

/// How a transaction's fee was raised after it was broadcast.
///
/// A fee bump puts a second transaction on the chain — a CPFP child, an RBF
/// replacement, a cancellation — and the engine lists each txid on its own.
/// To the user it is one payment whose fee was changed, so Activity folds
/// the second transaction into the first (`foldFeeBumps`) and the one row
/// that remains carries this: what was done, with which other transaction,
/// and what it cost.
class FeeBump {
  const FeeBump({
    required this.method,
    required this.otherTxid,
    this.feeSats,
    this.feeRate,
    this.otherConfirmed = false,
    this.awaitingSync = false,
  });

  /// `cpfp`, `rbf` or `cancel`.
  final String method;

  /// CPFP: the child that pays for this transaction. RBF / cancel: the
  /// transaction this one replaced — or, while [awaitingSync], the
  /// replacement that was broadcast for it.
  final String otherTxid;

  /// CPFP: what the child pays. RBF / cancel: the fee after the bump.
  final int? feeSats;

  /// The rate after the bump, in sat/vB (CPFP: of parent and child together).
  final double? feeRate;

  /// CPFP: the child has a block of its own.
  final bool otherConfirmed;

  /// RBF / cancel: the replacement was broadcast and no sync has listed it
  /// yet, so the row on screen is still the original.
  final bool awaitingSync;

  bool get isCpfp => method == 'cpfp';
  bool get isCancel => method == 'cancel';

  /// The method as a word: `CPFP`, `RBF`, `Cancellation`.
  String get label => switch (method) {
    'cpfp' => 'CPFP',
    'cancel' => 'Cancellation',
    _ => 'RBF',
  };
}

class Transaction {
  const Transaction({
    required this.txid,
    required this.direction,
    required this.chain,
    required this.amount,
    required this.ticker,
    required this.timestamp,
    required this.confirmations,
    this.fee,
    this.feeSats,
    this.feeRate,
    this.vsize = 0,
    this.isReplaceable = false,
    this.canRbf = false,
    this.canCpfp = false,
    this.canCancel = false,
    this.feeBumpUnavailableReason,
    this.bump,
    this.note,
    this.counterparty,
    this.fiatEstimate,
  });

  final String txid;
  final TxDirection direction;
  final TxChain chain;
  final String amount;
  final String ticker;
  final DateTime timestamp;
  final int confirmations;
  final String? fee;
  final int? feeSats;
  final double? feeRate;
  final int vsize;
  final bool isReplaceable;
  final bool canRbf;
  final bool canCpfp;
  final bool canCancel;
  final String? feeBumpUnavailableReason;

  /// The fee bump folded into this transaction, when it had one.
  final FeeBump? bump;
  final String? note;
  final String? counterparty;
  final String? fiatEstimate;

  bool get isConfirmed => confirmations > 0;
  bool get canSpeedUp => canRbf || canCpfp;

  String get shortTxid =>
      '${txid.substring(0, 8)}…${txid.substring(txid.length - 8)}';

  /// Six characters each side — the txid as it fits a phone row next to a
  /// chain badge and an amount column.
  String get shortTxidCompact => txid.length <= 13
      ? txid
      : '${txid.substring(0, 6)}…${txid.substring(txid.length - 6)}';

  /// 'Received' / 'Sent' / 'Self-transfer'.
  String get directionLabel => switch (direction) {
    TxDirection.incoming => 'Received',
    TxDirection.outgoing => 'Sent',
    TxDirection.self => 'Self-transfer',
  };

  /// What the row and the detail call this transaction: the user's note,
  /// else its direction — and a cancellation says it is one, because what
  /// the engine lists for it is a transfer to oneself.
  String get title {
    final b = bump;
    if (b != null && b.isCancel && !b.awaitingSync) {
      return isConfirmed ? 'Cancelled payment' : 'Cancellation';
    }
    return note ?? directionLabel;
  }

  /// This transaction with [bump] folded into it.
  Transaction withBump(FeeBump bump) => Transaction(
    txid: txid,
    direction: direction,
    chain: chain,
    amount: amount,
    ticker: ticker,
    timestamp: timestamp,
    confirmations: confirmations,
    fee: fee,
    feeSats: feeSats,
    feeRate: feeRate,
    vsize: vsize,
    isReplaceable: isReplaceable,
    canRbf: canRbf,
    canCpfp: canCpfp,
    canCancel: canCancel,
    feeBumpUnavailableReason: feeBumpUnavailableReason,
    bump: bump,
    note: note,
    counterparty: counterparty,
    fiatEstimate: fiatEstimate,
  );
}
