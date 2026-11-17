import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/peg/models/peg_models.dart';

/// Which of a wallet's transactions belong to a peg, so Activity can say
/// "Peg-in deposit" instead of a bare send. Chain data cannot tell; the peg
/// orders can, but reading them contacts servers (seconds per open order),
/// so Activity never asks: the Peg screen records the txids it sees here and
/// Activity reads this small local index.
class PegTxLabelStore {
  PegTxLabelStore._();
  static final instance = PegTxLabelStore._();
  static const _key = 'peg_tx_labels_v1';

  /// `{wallet_id: {txid: label}}`.
  Future<Map<String, Map<String, String>>> _all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>).map(
        (w, m) =>
            MapEntry(w, (m as Map<String, dynamic>).cast<String, String>()),
      );
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, String>> labelsFor(String walletId) async =>
      (await _all())[walletId] ?? const {};

  /// The labels [orders] give their transactions; writes only on a change.
  Future<void> record(String walletId, List<PegOrder> orders) async {
    final labels = pegTxLabels(orders);
    final all = await _all();
    final current = all[walletId] ?? const <String, String>{};
    final merged = {...current, ...labels};
    if (merged.length == current.length &&
        labels.entries.every((e) => current[e.key] == e.value)) {
      return;
    }
    all[walletId] = merged;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(all));
  }
}

/// Activity labels of an order's own transactions (legacy simulated orders
/// have none that are real).
Map<String, String> pegTxLabels(List<PegOrder> orders) => {
  for (final o in orders.where((o) => !o.isLegacySimulated)) ...{
    if (o.txidDeposit != null)
      o.txidDeposit!: o.isPegIn
          ? (o.isSideSwap ? 'SideSwap deposit' : 'Peg-in deposit')
          : (o.isSideSwap ? 'SideSwap deposit' : 'Peg-out'),
    if (o.txidClaim != null) o.txidClaim!: 'Peg-in claim',
    if (o.txidPayout != null && o.txidPayout != o.txidClaim)
      o.txidPayout!: o.isPegIn
          ? (o.isSideSwap ? 'SideSwap payout' : 'Peg-in claim')
          : (o.isSideSwap ? 'SideSwap payout' : 'Peg-out payment'),
  },
};
