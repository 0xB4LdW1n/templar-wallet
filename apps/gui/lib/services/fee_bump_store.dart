import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class FeeBumpRecord {
  const FeeBumpRecord({
    required this.walletId,
    required this.originalTxid,
    required this.replacementTxid,
    required this.method,
    required this.targetFeeRate,
    required this.newFeeSats,
    required this.newFeeRate,
    required this.createdAt,
  });

  final String walletId;
  final String originalTxid;
  final String replacementTxid;
  final String method;
  final double targetFeeRate;
  final int newFeeSats;
  final double newFeeRate;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'wallet_id': walletId,
    'original_txid': originalTxid,
    'replacement_txid': replacementTxid,
    'method': method,
    'target_fee_rate': targetFeeRate,
    'new_fee_sats': newFeeSats,
    'new_fee_rate': newFeeRate,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory FeeBumpRecord.fromJson(Map<String, dynamic> j) => FeeBumpRecord(
    walletId: j['wallet_id'] as String,
    originalTxid: j['original_txid'] as String,
    replacementTxid: j['replacement_txid'] as String,
    method: j['method'] as String,
    targetFeeRate: (j['target_fee_rate'] as num).toDouble(),
    newFeeSats: j['new_fee_sats'] as int? ?? 0,
    newFeeRate: (j['new_fee_rate'] as num?)?.toDouble() ?? 0,
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['created_at'] as int),
  );
}

/// Local relationship index for replacements and CPFP children. Chain data
/// knows each txid separately; this small store preserves why the second one
/// was created so Activity can link it back to its parent after a restart.
class FeeBumpStore {
  FeeBumpStore._();
  static final instance = FeeBumpStore._();
  static const _key = 'fee_bump_records_v1';

  Future<List<FeeBumpRecord>> listFor(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final rows = jsonDecode(raw) as List<dynamic>;
      return rows
          .map((e) => FeeBumpRecord.fromJson(e as Map<String, dynamic>))
          .where((e) => e.walletId == walletId)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(FeeBumpRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    List<FeeBumpRecord> all = [];
    if (raw != null && raw.isNotEmpty) {
      try {
        all = (jsonDecode(raw) as List<dynamic>)
            .map((e) => FeeBumpRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        all = [];
      }
    }
    all.removeWhere(
      (e) =>
          e.walletId == record.walletId &&
          e.originalTxid == record.originalTxid &&
          e.method == record.method,
    );
    all.add(record);
    await prefs.setString(
      _key,
      jsonEncode(all.map((e) => e.toJson()).toList()),
    );
  }
}
