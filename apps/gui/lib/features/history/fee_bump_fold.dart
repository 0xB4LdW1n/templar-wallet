// A fee bump is one payment whose fee was changed, not two payments.
//
// The engine lists every txid on its own: an RBF replacement beside the
// transaction it replaced (which lingers, unconfirmed, for as long as the
// wallet remembers it), a CPFP child beside its parent. Shown as they come,
// a sped-up payment is two rows — and a child whose "amount" is its fee
// reads as money that left. This folds each bump into the one transaction
// the user means, using the record the app kept when it made the bump
// ([FeeBumpStore]); the other txid, and what the bump cost, go into
// [Transaction.bump], which the row marks and the detail spells out.

import '../../services/fee_bump_store.dart';
import 'models/transaction.dart';

/// What a fold decides for a set of listed transactions: which rows go,
/// and what the rows that stay carry.
typedef _Fold = ({Set<String> dropped, Map<String, FeeBump> bumps});

/// Folds [records] over the transactions the engine lists: [listed] maps
/// each txid to whether it has a block and to its fee, when known.
///
/// - **CPFP**: the parent stays and carries the bump; the child's row goes.
/// - **RBF / cancel**: a chain of replacements is one row — the one that
///   confirmed, else the latest the engine lists. The others go: they are
///   the same coins, and at most one of them can ever confirm.
_Fold _fold(
  Map<String, ({bool confirmed, int? feeSats})> listed,
  List<FeeBumpRecord> records,
) {
  final dropped = <String>{};
  final bumps = <String, FeeBump>{};

  // Replacements: original → replacement → its replacement …
  final step = {
    for (final r in records)
      if (r.method != 'cpfp') r.originalTxid: r,
  };
  final replacements = {for (final r in step.values) r.replacementTxid};
  for (final root in step.keys.where((id) => !replacements.contains(id))) {
    final chain = [root];
    final steps = <FeeBumpRecord>[];
    for (var r = step[root]; r != null; r = step[r.replacementTxid]) {
      // A record that points back into its own chain ends it.
      if (chain.contains(r.replacementTxid)) break;
      chain.add(r.replacementTxid);
      steps.add(r);
    }
    final present = chain.where(listed.containsKey).toList();
    if (present.isEmpty) continue;
    final winner = present.firstWhere(
      (id) => listed[id]!.confirmed,
      orElse: () => present.last,
    );
    dropped.addAll(present.where((id) => id != winner));
    final at = chain.indexOf(winner);
    if (at > 0) {
      // The row is a replacement: it took the place of the one before it.
      final r = steps[at - 1];
      bumps[winner] = FeeBump(
        method: r.method,
        otherTxid: r.originalTxid,
        feeSats: r.newFeeSats > 0 ? r.newFeeSats : null,
        feeRate: r.newFeeRate > 0 ? r.newFeeRate : null,
      );
    } else if (!listed[winner]!.confirmed) {
      // Still the original: its replacement is out, and no sync has listed
      // it yet. (A confirmed original won the race; there is nothing to
      // mark — the replacement can no longer happen.)
      final r = steps.first;
      bumps[winner] = FeeBump(
        method: r.method,
        otherTxid: r.replacementTxid,
        feeSats: r.newFeeSats > 0 ? r.newFeeSats : null,
        feeRate: r.newFeeRate > 0 ? r.newFeeRate : null,
        awaitingSync: true,
      );
    }
  }

  // Children: the parent keeps the row.
  for (final r in records.where((r) => r.method == 'cpfp')) {
    final parent = listed[r.originalTxid];
    if (parent == null || dropped.contains(r.originalTxid)) continue;
    final child = listed[r.replacementTxid];
    if (child != null) dropped.add(r.replacementTxid);
    bumps[r.originalTxid] = FeeBump(
      method: 'cpfp',
      otherTxid: r.replacementTxid,
      feeSats: child?.feeSats ?? (r.newFeeSats > 0 ? r.newFeeSats : null),
      // The record's target is the rate of the pair, which is the point.
      feeRate: r.targetFeeRate > 0 ? r.targetFeeRate : null,
      otherConfirmed: child?.confirmed ?? false,
    );
  }
  return (dropped: dropped, bumps: bumps);
}

/// [txs] with every fee bump in [records] folded into the transaction it
/// was done to. Order is kept; nothing is invented — a row is only ever
/// removed, or given a [FeeBump].
List<Transaction> foldFeeBumps(
  List<Transaction> txs,
  List<FeeBumpRecord> records,
) {
  if (records.isEmpty || txs.isEmpty) return txs;
  final fold = _fold({
    for (final tx in txs)
      tx.txid: (confirmed: tx.isConfirmed, feeSats: tx.feeSats),
  }, records);
  return [
    for (final tx in txs)
      if (!fold.dropped.contains(tx.txid))
        switch (fold.bumps[tx.txid]) {
          final bump? => tx.withBump(bump),
          null => tx,
        },
  ];
}

/// The txids a fold takes out of a list — for a list that is not made of
/// [Transaction]s (the Dashboard's recent activity) and only has to stop
/// showing a bump's second transaction as a payment of its own.
/// [confirmedById] maps each listed txid to whether it has a block.
Set<String> feeBumpHiddenTxids(
  Map<String, bool> confirmedById,
  List<FeeBumpRecord> records,
) {
  if (records.isEmpty || confirmedById.isEmpty) return const {};
  return _fold({
    for (final e in confirmedById.entries)
      e.key: (confirmed: e.value, feeSats: null),
  }, records).dropped;
}
