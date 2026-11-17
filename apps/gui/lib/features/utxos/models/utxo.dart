enum UtxoState { available, frozen, dusty, unconfirmed }

/// `tb1qw508…xpjzsx` — enough of both ends of an address to tell two apart
/// on a tight line.
String shortCoinAddress(String address) => address.length <= 16
    ? address
    : '${address.substring(0, 8)}…${address.substring(address.length - 6)}';

class Utxo {
  const Utxo({
    required this.outpoint,
    required this.amount,
    required this.displayAmount,
    required this.confirmations,
    required this.state,
    this.label,
    this.address,
    this.ticker,
    this.assetId,
    this.isSelected = false,
  });

  final String outpoint;
  final int amount;
  final String displayAmount;
  final int confirmations;
  final UtxoState state;
  final String? label;
  final String? address;
  final String? ticker;
  final String? assetId;
  final bool isSelected;

  /// The transaction that created this coin.
  String get txid => outpoint.split(':').first;

  /// Output index inside [txid].
  int get vout {
    final parts = outpoint.split(':');
    return parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  }

  /// An incoming coin the chain has not confirmed yet. It is drawn as a
  /// provisional grey note — the same object a consolidation in flight is —
  /// and cannot be selected until a block includes it.
  bool get isPending => state == UtxoState.unconfirmed;

  /// Taken out of circulation by the user: still in the balance, never
  /// spent by the engine until it is unfrozen.
  bool get isFrozen => state == UtxoState.frozen;

  /// Denominated in satoshis of the chain's own coin (BTC or LBTC), where
  /// the fixed dust and whale amounts mean something. A token's "546" is
  /// not dust and its "1.00000000" is not a whale.
  bool get isBtcLike =>
      ticker == null ||
      ticker == 'BTC' ||
      ticker == 'LBTC' ||
      ticker == 'L-BTC';

  String get shortOutpoint {
    final parts = outpoint.split(':');
    final txid = parts[0];
    final vout = parts.length > 1 ? parts[1] : '0';
    return '${txid.substring(0, 8)}…:$vout';
  }

  /// Head and tail of the txid plus the vout — `a1b2c3d4e5…7f8e9d:0`.
  /// Enough to spot-check against an explorer on a phone card, where the
  /// full 64-hex outpoint would never fit on one line.
  String get midOutpoint {
    final parts = outpoint.split(':');
    final txid = parts[0];
    final vout = parts.length > 1 ? parts[1] : '0';
    if (txid.length <= 18) return '$txid:$vout';
    return '${txid.substring(0, 10)}…${txid.substring(txid.length - 6)}:$vout';
  }

  /// Head and tail of the address this coin sits on ([shortCoinAddress]),
  /// or null when the engine named none. The whole address is in the coin's
  /// details.
  String? get shortAddress {
    final a = address;
    return a == null || a.isEmpty ? null : shortCoinAddress(a);
  }

  /// [clearLabel] is what makes "erase the label" expressible: a plain
  /// `label: null` is indistinguishable from "leave it alone", so clearing a
  /// tag used to persist to disk and stay on screen until the next reload.
  Utxo copyWith({
    bool? isSelected,
    String? label,
    UtxoState? state,
    bool clearLabel = false,
  }) => Utxo(
    outpoint: outpoint,
    amount: amount,
    displayAmount: displayAmount,
    confirmations: confirmations,
    state: state ?? this.state,
    label: clearLabel ? null : (label ?? this.label),
    address: address,
    ticker: ticker,
    assetId: assetId,
    isSelected: isSelected ?? this.isSelected,
  );
}
