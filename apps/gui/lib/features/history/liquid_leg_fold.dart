// A Liquid transaction is one row, whatever it moved.
//
// The engine lists a Liquid transaction once per asset whose balance it
// changed. Sending a token therefore came out as two rows with one txid:
// the token that left, and "Sent 33 sats" of L-BTC — which is the network
// fee, not a second payment. This folds the rows of one txid into one
// transaction: it leads with what was really moved, the other assets ride
// along as [Transaction.legs], and an L-BTC row that was nothing but the fee
// becomes the fee of that one row ([Transaction.feeLegFolded]).

import '../../shared/amount_units.dart';
import 'models/transaction.dart';

/// The sats of an engine amount in a bitcoin unit (`-0.00000033 LBTC`,
/// `33 sats`), sign dropped; null for any other asset — only the engine
/// knows an issued asset's precision.
int? bitcoinAmountSats(String amount) {
  var raw = amount.trim();
  while (raw.isNotEmpty && '~+-−'.contains(raw[0])) {
    raw = raw.substring(1).trim();
  }
  final space = raw.lastIndexOf(' ');
  if (space < 0) return null;
  final number = raw.substring(0, space).trim().replaceAll(',', '');
  return switch (raw.substring(space + 1).trim().toUpperCase()) {
    'SAT' || 'SATS' => int.tryParse(number),
    'BTC' || 'TBTC' || 'LBTC' || 'L-BTC' => AmountUnits.satsFromCoin(number),
    _ => null,
  };
}

/// [txs] with the Liquid rows of one txid folded into one transaction.
/// Order is kept (the folded row stands where the first of its rows stood);
/// nothing is invented, and a transaction listed once is left as it is.
List<Transaction> foldLiquidLegs(List<Transaction> txs) {
  final rows = <String, List<Transaction>>{};
  for (final tx in txs) {
    if (tx.chain == TxChain.liquid) (rows[tx.txid] ??= []).add(tx);
  }
  if (rows.values.every((r) => r.length < 2)) return txs;
  final folded = <String>{};
  return [
    for (final tx in txs)
      if (tx.chain != TxChain.liquid || rows[tx.txid]!.length < 2)
        tx
      else if (folded.add(tx.txid))
        _fold(rows[tx.txid]!),
  ];
}

Transaction _fold(List<Transaction> rows) {
  // The engine states the fee on one row of the transaction only.
  final withFee = rows.firstWhere(
    (r) => r.feeSats != null,
    orElse: () => rows.first,
  );
  final feeSats = withFee.feeSats;
  // The row that is the fee and nothing else: L-BTC out, exactly the fee.
  Transaction? feeRow;
  if (feeSats != null) {
    for (final r in rows) {
      if (r.direction == TxDirection.outgoing &&
          bitcoinAmountSats(r.amount) == feeSats) {
        feeRow = r;
        break;
      }
    }
  }
  final moved = [
    for (final r in rows)
      if (!identical(r, feeRow)) r,
  ];
  final lead = moved.first;
  String? firstOf(String? Function(Transaction) field) {
    for (final r in rows) {
      final v = field(r);
      if (v != null) return v;
    }
    return null;
  }

  return Transaction(
    txid: lead.txid,
    direction: lead.direction,
    chain: lead.chain,
    amount: lead.amount,
    ticker: lead.ticker,
    timestamp: lead.timestamp,
    confirmations: lead.confirmations,
    fee: withFee.fee,
    feeSats: feeSats,
    feeRate: withFee.feeRate,
    vsize: withFee.vsize,
    feeBumpUnavailableReason: lead.feeBumpUnavailableReason,
    legs: [
      for (final r in moved.skip(1))
        TxLeg(direction: r.direction, amount: r.amount, ticker: r.ticker),
    ],
    feeLegFolded: feeRow != null,
    note: firstOf((r) => r.note),
    counterparty: firstOf((r) => r.counterparty),
    fiatEstimate: lead.fiatEstimate,
  );
}
