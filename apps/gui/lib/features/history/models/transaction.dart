enum TxDirection { incoming, outgoing, self }

enum TxChain { bitcoin, liquid }

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
    this.replacesTxid,
    this.replacedByTxid,
    this.feeBumpMethod,
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
  final String? replacesTxid;
  final String? replacedByTxid;
  final String? feeBumpMethod;
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

  Transaction withFeeBumpLink({
    String? replacesTxid,
    String? replacedByTxid,
    String? feeBumpMethod,
    String? note,
  }) => Transaction(
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
    replacesTxid: replacesTxid ?? this.replacesTxid,
    replacedByTxid: replacedByTxid ?? this.replacedByTxid,
    feeBumpMethod: feeBumpMethod ?? this.feeBumpMethod,
    note: note ?? this.note,
    counterparty: counterparty,
    fiatEstimate: fiatEstimate,
  );
}
