/// A quote from the active network's peg provider for moving [amountSats]
/// between chains (templarlib docs/API.md, `peg_quote`).
///
/// Direction is `"in"` (BTC → LBTC) or `"out"` (LBTC → BTC). All amounts are
/// in satoshis. [provider] is `native` (the Elements peg of a joined test
/// server) or `sideswap` (a third party's custodial swap on Liquid testnet).
class PegQuote {
  const PegQuote({
    required this.direction,
    required this.amountSats,
    required this.rate,
    required this.serviceFeeSats,
    required this.networkFeeSats,
    required this.receiveSats,
    required this.minSats,
    required this.maxSats,
    required this.etaMinutes,
    required this.simulated,
    this.provider = 'native',
    this.confirmationsRequired = 0,
    this.networkFeeIncluded = false,
  });

  final String direction;
  final int amountSats;
  final double rate;
  final int serviceFeeSats;
  final int networkFeeSats;

  /// What lands at the payout address after all fees.
  final int receiveSats;
  final int minSats;
  final int maxSats;
  final int etaMinutes;
  final bool simulated;

  /// `native` | `sideswap`.
  final String provider;

  /// Confirmations of the deposit the provider waits for.
  final int confirmationsRequired;

  /// True when [networkFeeSats] is taken out of the amount (the receive is
  /// smaller); false when it is paid on top of it.
  final bool networkFeeIncluded;

  factory PegQuote.fromJson(Map<String, dynamic> j) => PegQuote(
    direction: j['direction'] as String? ?? 'in',
    amountSats: (j['amount_sats'] as num?)?.toInt() ?? 0,
    rate: (j['rate'] as num?)?.toDouble() ?? 1.0,
    serviceFeeSats: (j['service_fee_sats'] as num?)?.toInt() ?? 0,
    networkFeeSats: (j['network_fee_sats'] as num?)?.toInt() ?? 0,
    receiveSats: (j['receive_sats'] as num?)?.toInt() ?? 0,
    minSats: (j['min_sats'] as num?)?.toInt() ?? 0,
    maxSats: (j['max_sats'] as num?)?.toInt() ?? 0,
    etaMinutes: (j['eta_minutes'] as num?)?.toInt() ?? 0,
    simulated: j['simulated'] as bool? ?? false,
    provider: j['provider'] as String? ?? 'native',
    confirmationsRequired: (j['confirmations_required'] as num?)?.toInt() ?? 0,
    networkFeeIncluded: j['network_fee_included'] as bool? ?? false,
  );
}

/// One entry of a peg order's status history: which [status] was entered and
/// when ([at], unix seconds).
class PegStatusEntry {
  const PegStatusEntry({required this.status, required this.at});

  final String status;
  final int at;

  factory PegStatusEntry.fromJson(Map<String, dynamic> j) => PegStatusEntry(
    status: j['status'] as String? ?? '',
    at: (j['at'] as num?)?.toInt() ?? 0,
  );
}

/// A peg-in / peg-out order (templarlib docs/API.md, **PegOrder**).
///
/// Native peg-in: `awaiting_deposit → deposit_seen → confirming → claimable
/// → settling → completed`, the claim being the user's step. Native peg-out:
/// `awaiting_deposit` (until the user funds it) `→ deposit_seen → confirming
/// → settling → completed`. `completed`, `cancelled`, `expired` and `failed`
/// are final; a status can step back after a reorg. Which steps are allowed
/// is the engine's to decide — the getters here only pick what to offer.
class PegOrder {
  const PegOrder({
    required this.orderId,
    required this.walletId,
    required this.direction,
    required this.status,
    required this.depositAddress,
    required this.depositExpectedSats,
    required this.payoutAddress,
    required this.payoutExpectedSats,
    required this.createdAt,
    required this.updatedAt,
    required this.etaMinutes,
    this.txidDeposit,
    this.txidPayout,
    required this.simulated,
    required this.statusHistory,
    this.provider = 'native',
    this.confirmations = 0,
    this.confirmationsRequired = 0,
    this.depositReceivedSats,
    this.txidClaim,
    this.validUntilLiquidHeight,
    this.lastError,
    this.expiresAt,
  });

  final String orderId;
  final String walletId;

  /// `"in"` = BTC → LBTC, `"out"` = LBTC → BTC.
  final String direction;
  final String status;

  /// Peg-in: the Bitcoin address to pay. Native peg-out: empty — the
  /// peg-out is made by funding the order.
  final String depositAddress;
  final int depositExpectedSats;
  final String payoutAddress;

  /// After a claim: what the claim actually paid.
  final int payoutExpectedSats;

  /// Unix seconds.
  final int createdAt;
  final int updatedAt;
  final int etaMinutes;

  /// Peg-in: the Bitcoin deposit; peg-out: the Liquid peg-out.
  final String? txidDeposit;

  /// Peg-in: the claim; peg-out: the federation's Bitcoin payment.
  final String? txidPayout;
  final bool simulated;
  final List<PegStatusEntry> statusHistory;

  /// `native` | `sideswap` | `simulated` (the retired demo provider).
  final String provider;

  /// Of the deposit: Bitcoin for a peg-in, Liquid for a peg-out.
  final int confirmations;
  final int confirmationsRequired;
  final int? depositReceivedSats;
  final String? txidClaim;

  /// Native peg-in: the deposit address is guaranteed through this Liquid
  /// height.
  final int? validUntilLiquidHeight;

  /// Why the last status check could not read the chains.
  final String? lastError;

  /// SideSwap: Unix seconds after which the deposit is no longer taken.
  final int? expiresAt;

  bool get isPegIn => direction == 'in';
  bool get awaitingDeposit => status == 'awaiting_deposit';

  /// An order of the retired simulated provider: shown, never paid.
  bool get isLegacySimulated => simulated || provider == 'simulated';
  bool get isSideSwap => provider == 'sideswap';
  bool get isClaimable => status == 'claimable';

  /// Final orders never change again — polling skips them.
  bool get isTerminal =>
      status == 'completed' ||
      status == 'cancelled' ||
      status == 'expired' ||
      status == 'failed';

  /// The app offers "Fund from this wallet" (the engine decides).
  bool get canOfferFund => awaitingDeposit && !isLegacySimulated;

  /// The app offers "Claim" (native peg-in only).
  bool get canOfferClaim => isClaimable && isPegIn && provider == 'native';

  /// The deposit address a peg-in can also be paid at from elsewhere.
  bool get showsDepositAddress =>
      awaitingDeposit && depositAddress.isNotEmpty && !isLegacySimulated;

  factory PegOrder.fromJson(Map<String, dynamic> j) => PegOrder(
    orderId: j['order_id'] as String? ?? '',
    walletId: j['wallet_id'] as String? ?? '',
    direction: j['direction'] as String? ?? 'in',
    status: j['status'] as String? ?? '',
    depositAddress: j['deposit_address'] as String? ?? '',
    depositExpectedSats: (j['deposit_expected_sats'] as num?)?.toInt() ?? 0,
    payoutAddress: j['payout_address'] as String? ?? '',
    payoutExpectedSats: (j['payout_expected_sats'] as num?)?.toInt() ?? 0,
    createdAt: (j['created_at'] as num?)?.toInt() ?? 0,
    updatedAt: (j['updated_at'] as num?)?.toInt() ?? 0,
    etaMinutes: (j['eta_minutes'] as num?)?.toInt() ?? 0,
    txidDeposit: j['txid_deposit'] as String?,
    txidPayout: j['txid_payout'] as String?,
    simulated: j['simulated'] as bool? ?? false,
    statusHistory:
        (j['status_history'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(PegStatusEntry.fromJson)
            .toList() ??
        const [],
    // Orders stored before the native peg carry no provider: they are the
    // simulated provider's.
    provider:
        j['provider'] as String? ??
        ((j['simulated'] as bool? ?? false) ? 'simulated' : 'native'),
    confirmations: (j['confirmations'] as num?)?.toInt() ?? 0,
    confirmationsRequired: (j['confirmations_required'] as num?)?.toInt() ?? 0,
    depositReceivedSats: (j['deposit_received_sats'] as num?)?.toInt(),
    txidClaim: j['txid_claim'] as String?,
    validUntilLiquidHeight: (j['valid_until_liquid_height'] as num?)?.toInt(),
    lastError: j['last_error'] as String?,
    expiresAt: (j['expires_at'] as num?)?.toInt(),
  );
}

/// An engine refusal of a peg step, as a person reads it. The tags are the
/// contract (`PEG_UNAVAILABLE:`, `PEG_NOT_READY:`, `PEG_EXPIRED:`,
/// `PEG_PROOF_REJECTED:`); limit and builder errors are plain text and pass
/// through.
String pegErrorText(Object error) {
  final raw = error.toString().replaceFirst('Exception: wallet-ffi: ', '');
  final colon = raw.indexOf(':');
  if (!raw.startsWith('PEG_') || colon < 0) return raw;
  final detail = raw.substring(colon + 1).trim();
  return switch (raw.substring(0, colon)) {
    'PEG_UNAVAILABLE' => 'No peg here. $detail',
    'PEG_NOT_READY' => 'Not yet: $detail',
    'PEG_EXPIRED' =>
      'This deposit address has expired: never pay it. Start a new peg. '
          '($detail)',
    'PEG_PROOF_REJECTED' =>
      'The deposit\'s proof does not match this wallet\'s own view of the '
          'Bitcoin chain, so nothing was signed. ($detail)',
    'PEG_INSUFFICIENT_FUNDS' =>
      'Not enough coins: ${_sentence(detail)} Nothing was signed.',
    _ => raw,
  };
}

/// The engine refused to fund an order because the wallet cannot pay it
/// (`PEG_INSUFFICIENT_FUNDS`): BTC for a peg-in deposit, L-BTC for a
/// peg-out and its fee.
bool isPegInsufficientFunds(Object error) => error
    .toString()
    .replaceFirst('Exception: wallet-ffi: ', '')
    .startsWith('PEG_INSUFFICIENT_FUNDS');

/// The engine's sentence with its first letter raised and a full stop at
/// the end, to sit inside a paragraph.
String _sentence(String text) {
  final t = text.trim();
  if (t.isEmpty) return t;
  final first = t[0].toUpperCase() + t.substring(1);
  return first.endsWith('.') ? first : '$first.';
}
