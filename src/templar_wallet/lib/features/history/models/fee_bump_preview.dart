class FeeBumpPreview {
  const FeeBumpPreview({
    required this.method,
    required this.originalTxid,
    required this.psbtBase64,
    required this.oldFeeSats,
    required this.oldFeeRate,
    required this.oldVsize,
    required this.newFeeSats,
    required this.newFeeRate,
    required this.newVsize,
    required this.extraFeeSats,
    required this.effectiveFeeRate,
    required this.totalFeeSats,
  });

  final String method;
  final String originalTxid;
  final String psbtBase64;
  final int oldFeeSats;
  final double oldFeeRate;
  final int oldVsize;
  final int newFeeSats;
  final double newFeeRate;
  final int newVsize;
  final int extraFeeSats;
  final double effectiveFeeRate;
  final int totalFeeSats;

  bool get isCpfp => method == 'cpfp';
  bool get isCancel => method == 'cancel';

  factory FeeBumpPreview.fromJson(Map<String, dynamic> j) => FeeBumpPreview(
    method: j['method'] as String,
    originalTxid: j['original_txid'] as String,
    psbtBase64: j['psbt_base64'] as String,
    oldFeeSats: j['old_fee_sats'] as int,
    oldFeeRate: (j['old_fee_rate'] as num).toDouble(),
    oldVsize: j['old_vsize'] as int,
    newFeeSats: j['new_fee_sats'] as int,
    newFeeRate: (j['new_fee_rate'] as num).toDouble(),
    newVsize: j['new_vsize'] as int,
    extraFeeSats: j['extra_fee_sats'] as int,
    effectiveFeeRate: (j['effective_fee_rate'] as num).toDouble(),
    totalFeeSats: j['total_fee_sats'] as int,
  );
}
