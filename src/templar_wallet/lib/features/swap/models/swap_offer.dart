/// One side of a LiquiDEX swap, oriented from the taker's point of view.
class SwapLeg {
  const SwapLeg({
    required this.assetId,
    required this.ticker,
    required this.amountSats,
    required this.displayAmount,
  });

  final String assetId;

  /// Short ticker for display (derived from the order book's asset name).
  final String ticker;
  final int amountSats;

  /// Human-formatted amount as provided by the order book.
  final String displayAmount;

  factory SwapLeg.fromJson(Map<String, dynamic> j) => SwapLeg(
    assetId: j['asset_id'] as String? ?? '',
    ticker: _displayTicker(j['ticker'] as String? ?? ''),
    amountSats: j['amount_sats'] as int? ?? 0,
    displayAmount: j['display_amount'] as String? ?? '0',
  );
}

String _displayTicker(String ticker) => switch (ticker.toUpperCase()) {
  'L-BTC' || 'TL-BTC' || 'RL-BTC' => 'LBTC',
  _ => ticker,
};

/// A LiquiDEX (v0) order from the configured order book, presented to the taker.
///
/// [receive] is what the taker gets, [pay] is what the taker gives to the maker
/// (excluding the network fee). [proposalJson] is the raw v0 proposal, carried so
/// the take flow can complete it without re-fetching.
class SwapOffer {
  const SwapOffer({
    required this.id,
    required this.available,
    required this.receive,
    required this.pay,
    required this.price,
    required this.priceDisplay,
    required this.created,
    this.verified = true,
    this.verifyNote,
    required this.proposalJson,
    this.network = '',
    this.takeable = false,
    this.kind = 'swap',
  });

  final int id;
  final bool available;
  final SwapLeg receive;
  final SwapLeg pay;

  /// Paid-asset units per received-asset unit, computed from the proposal.
  final double price;
  final String priceDisplay;
  final String created;

  /// Maker's output commitment + SIGHASH were cryptographically verified against the
  /// signed transaction. (Defaults to true for locally-constructed mock offers; the
  /// FFI path always sets this explicitly from the backend.)
  final bool verified;

  /// Reason an order failed verification, if any.
  final String? verifyNote;
  final String proposalJson;

  /// "mainnet", "testnet", or "" when unknown. Mainnet rows are view-only.
  final String network;

  /// Whether this wallet can take the order (testnet + available + verified).
  final bool takeable;

  /// Offer kind — only "swap" today; "loan" arrives with the lending protocol.
  final String kind;

  factory SwapOffer.fromJson(Map<String, dynamic> j) => SwapOffer(
    id: j['id'] as int? ?? 0,
    available: j['available'] as bool? ?? false,
    receive: SwapLeg.fromJson(j['receive'] as Map<String, dynamic>),
    pay: SwapLeg.fromJson(j['pay'] as Map<String, dynamic>),
    price: (j['price'] as num?)?.toDouble() ?? 0,
    priceDisplay: j['price_display'] as String? ?? '',
    created: _displayCreated(j['created']),
    verified: j['verified'] as bool? ?? false,
    verifyNote: j['verify_note'] as String?,
    proposalJson: j['proposal_json'] as String? ?? '',
    network: j['network'] as String? ?? '',
    takeable: j['takeable'] as bool? ?? false,
    kind: j['kind'] as String? ?? 'swap',
  );
}

String _displayCreated(Object? raw) {
  final text = raw?.toString() ?? '';
  final seconds = int.tryParse(text);
  if (seconds == null) return text;
  final value = DateTime.fromMillisecondsSinceEpoch(
    seconds * 1000,
    isUtc: true,
  );
  String two(int part) => part.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)} UTC';
}

/// One chain-aware side of the unified local market feed.
class MarketLeg {
  const MarketLeg({
    required this.chain,
    required this.network,
    required this.assetId,
    required this.ticker,
    required this.name,
    required this.precision,
    required this.amountSats,
    required this.displayAmount,
  });

  final String chain;
  final String network;
  final String assetId;
  final String ticker;
  final String name;
  final int precision;
  final int amountSats;
  final String displayAmount;

  bool get isBitcoin => chain == 'bitcoin';

  factory MarketLeg.fromJson(Map<String, dynamic> j) => MarketLeg(
    chain: j['chain'] as String? ?? '',
    network: j['network'] as String? ?? '',
    assetId: j['asset_id'] as String? ?? '',
    ticker: _displayTicker(j['ticker'] as String? ?? ''),
    name: j['name'] as String? ?? '',
    precision: j['precision'] as int? ?? 0,
    amountSats: j['amount_sats'] as int? ?? 0,
    displayAmount: j['display_amount'] as String? ?? '0',
  );
}

/// A LiquiDEX offer, real HTLC-v1 route, or explicit non-settling demo quote.
class MarketOffer {
  const MarketOffer({
    required this.id,
    required this.sourceId,
    required this.status,
    required this.settlement,
    required this.demo,
    required this.available,
    required this.makerGives,
    required this.makerWants,
    required this.priceDisplay,
    required this.note,
    required this.createdAt,
    required this.proposalJson,
    required this.verified,
    required this.takeable,
    this.blockReason,
  });

  final String id;
  final int sourceId;
  final String status;
  final String settlement;
  final bool demo;
  final bool available;
  final MarketLeg makerGives;
  final MarketLeg makerWants;
  final String priceDisplay;
  final String note;
  final int createdAt;
  final String proposalJson;
  final bool verified;
  final bool takeable;
  final String? blockReason;

  bool get isCrossChain => makerGives.chain != makerWants.chain;
  bool get isLiquidex => settlement == 'liquidex-v0';
  bool get isAtomic => settlement == 'htlc-v1';
  bool get involvesBitcoin => makerGives.isBitcoin || makerWants.isBitcoin;

  factory MarketOffer.fromJson(Map<String, dynamic> j) => MarketOffer(
    id: j['id'] as String? ?? '',
    sourceId: j['source_id'] as int? ?? 0,
    status: j['status'] as String? ?? '',
    settlement: j['settlement'] as String? ?? '',
    demo: j['demo'] as bool? ?? false,
    available: j['available'] as bool? ?? false,
    makerGives: MarketLeg.fromJson(j['maker_gives'] as Map<String, dynamic>),
    makerWants: MarketLeg.fromJson(j['maker_wants'] as Map<String, dynamic>),
    priceDisplay: j['price_display'] as String? ?? '',
    note: j['note'] as String? ?? '',
    createdAt: j['created_at'] as int? ?? 0,
    proposalJson: j['proposal_json'] as String? ?? '',
    verified: j['verified'] as bool? ?? false,
    takeable: j['takeable'] as bool? ?? false,
    blockReason: j['block_reason'] as String?,
  );
}

/// One locally-owned side of a real BTC testnet <-> Liquid testnet HTLC swap.
class AtomicSwap {
  const AtomicSwap({
    required this.offerId,
    required this.role,
    required this.status,
    required this.offered,
    required this.wanted,
    required this.nextAction,
    required this.canFund,
    required this.canClaim,
    required this.canRefund,
    required this.makerTimeout,
    this.takerTimeout,
  });

  final int offerId;
  final String role;
  final String status;
  final MarketLeg offered;
  final MarketLeg wanted;
  final String nextAction;
  final bool canFund;
  final bool canClaim;
  final bool canRefund;
  final int makerTimeout;
  final int? takerTimeout;

  factory AtomicSwap.fromJson(Map<String, dynamic> j) {
    final row = j['row'] as Map<String, dynamic>? ?? const {};
    final state = row['state'] as Map<String, dynamic>? ?? const {};
    MarketLeg leg(String prefix) => MarketLeg.fromJson({
      'chain': state['${prefix}_chain'],
      'network': state['${prefix}_chain'] == 'bitcoin'
          ? 'bitcoin-testnet'
          : 'liquid-testnet',
      'asset_id': state['${prefix}_asset_id'],
      'ticker': state['${prefix}_ticker'],
      'name': state['${prefix}_name'],
      'precision': state['${prefix}_precision'],
      'amount_sats': state['${prefix}_amount_sats'],
      'display_amount': _formatBaseUnits(
        state['${prefix}_amount_sats'] as int? ?? 0,
        state['${prefix}_precision'] as int? ?? 8,
      ),
    });
    return AtomicSwap(
      offerId: j['offer_id'] as int? ?? 0,
      role: j['role'] as String? ?? '',
      status: row['status'] as String? ?? '',
      offered: leg('offered'),
      wanted: leg('wanted'),
      nextAction: j['next_action'] as String? ?? 'wait',
      canFund: j['can_fund'] as bool? ?? false,
      canClaim: j['can_claim'] as bool? ?? false,
      canRefund: j['can_refund'] as bool? ?? false,
      makerTimeout: state['maker_timeout'] as int? ?? 0,
      takerTimeout: state['taker_timeout'] as int?,
    );
  }
}

String _formatBaseUnits(int amount, int precision) {
  if (precision <= 0) return '$amount';
  final raw = amount.toString().padLeft(precision + 1, '0');
  return '${raw.substring(0, raw.length - precision)}.'
      '${raw.substring(raw.length - precision)}';
}

/// One verification check on a proposal. [ok] is tri-state: true = passed,
/// false = failed, null = not runnable (e.g. needs chain access in offline mode).
class SwapCheck {
  const SwapCheck({required this.name, this.ok, this.note});

  final String name;
  final bool? ok;
  final String? note;

  /// "sighash_single_acp" → "Sighash single acp".
  String get displayName {
    final words = name.replaceAll('_', ' ');
    return words.isEmpty ? name : words[0].toUpperCase() + words.substring(1);
  }

  factory SwapCheck.fromJson(Map<String, dynamic> j) => SwapCheck(
    name: j['name'] as String? ?? '',
    ok: j['ok'] as bool?,
    note: j['note'] as String?,
  );
}

/// Full verification result for a proposal (`swap_verify`).
class SwapAnalysis {
  const SwapAnalysis({
    required this.valid,
    required this.checks,
    required this.makerOffers,
    required this.makerWants,
    required this.network,
    required this.takeable,
    this.takeBlockReason,
  });

  final bool valid;
  final List<SwapCheck> checks;

  /// Maker's input leg — what the taker receives.
  final SwapLeg makerOffers;

  /// Maker's output leg — what the taker pays.
  final SwapLeg makerWants;

  /// "testnet", "mainnet", or "unknown".
  final String network;
  final bool takeable;

  /// Why the order cannot be taken, when [takeable] is false.
  final String? takeBlockReason;

  factory SwapAnalysis.fromJson(Map<String, dynamic> j) => SwapAnalysis(
    valid: j['valid'] as bool? ?? false,
    checks: [
      for (final c in (j['checks'] as List<dynamic>? ?? []))
        SwapCheck.fromJson(c as Map<String, dynamic>),
    ],
    makerOffers: SwapLeg.fromJson(j['maker_offers'] as Map<String, dynamic>),
    makerWants: SwapLeg.fromJson(j['maker_wants'] as Map<String, dynamic>),
    network: j['network'] as String? ?? 'unknown',
    takeable: j['takeable'] as bool? ?? false,
    takeBlockReason: j['take_block_reason'] as String?,
  );
}

/// Honest preview of the taker transaction (`swap_take_preview`): real fee and
/// change computed from the actually-built (unsigned) transaction.
class SwapTakePreview {
  const SwapTakePreview({
    required this.youReceive,
    required this.youPay,
    required this.feeSats,
    required this.feeDisplay,
    required this.change,
    required this.analysis,
  });

  final SwapLeg youReceive;
  final SwapLeg youPay;
  final int feeSats;
  final String feeDisplay;
  final List<SwapLeg> change;
  final SwapAnalysis analysis;

  factory SwapTakePreview.fromJson(Map<String, dynamic> j) => SwapTakePreview(
    youReceive: SwapLeg.fromJson(j['you_receive'] as Map<String, dynamic>),
    youPay: SwapLeg.fromJson(j['you_pay'] as Map<String, dynamic>),
    feeSats: j['fee_sats'] as int? ?? 0,
    feeDisplay: j['fee_display'] as String? ?? '',
    change: [
      for (final c in (j['change'] as List<dynamic>? ?? []))
        SwapLeg.fromJson(c as Map<String, dynamic>),
    ],
    analysis: SwapAnalysis.fromJson(j['analysis'] as Map<String, dynamic>),
  );
}

/// An offer this wallet made (`swap_make` / `list_my_offers`).
class MyOffer {
  const MyOffer({
    required this.offerId,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.offers,
    required this.wants,
    required this.proposalJson,
    required this.utxo,
  });

  final String offerId;
  final String kind;

  /// "open", "closed" (offered coin was spent), or "cancelled".
  final String status;

  /// Unix seconds.
  final int createdAt;
  final SwapLeg offers;
  final SwapLeg wants;
  final String proposalJson;

  /// The offered outpoint, "txid:vout".
  final String utxo;

  factory MyOffer.fromJson(Map<String, dynamic> j) => MyOffer(
    offerId: j['offer_id'] as String? ?? '',
    kind: j['kind'] as String? ?? 'swap',
    status: j['status'] as String? ?? 'open',
    createdAt: j['created_at'] as int? ?? 0,
    offers: SwapLeg.fromJson(j['offers'] as Map<String, dynamic>),
    wants: SwapLeg.fromJson(j['wants'] as Map<String, dynamic>),
    proposalJson: j['proposal_json'] as String? ?? '',
    utxo: j['utxo'] as String? ?? '',
  );
}
