/// One timeline for the Activity screen: on-chain payments, Templar Protocol
/// loans, LiquiDEX and Bitcoin ↔ Liquid swaps, and pegs.
///
/// A read-only view. Every entry wraps exactly what the engine or a local
/// store reported and says nothing it was not told: a missing date stays
/// missing (the entry joins "Undated"), a missing amount is not drawn, and
/// a state the app does not know is shown in the engine's own words.
///
/// Presentation that needs no context lives here (title, facts, status
/// word) so it is testable without a widget tree; amounts are carried as
/// [ActivityAmount] and formatted by the row, in the user's unit.
library;

import '../../../services/price_service.dart';
import '../../protocol/models/protocol_portfolio.dart';
import '../../protocol/models/protocol_records.dart';
import '../../protocol/protocol_copy.dart';
import '../../peg/models/peg_models.dart';
import '../../swap/models/swap_offer.dart';
import 'transaction.dart';

/// What an entry is; the kind filter and the glyph tile follow it.
enum ActivityKind {
  payment,
  loan,
  swap,
  peg;

  /// The kind filter's label, plural.
  String get filterLabel => switch (this) {
    payment => 'Payments',
    loan => 'Loans',
    swap => 'Swaps',
    peg => 'Pegs',
  };
}

/// How a status reads: the normal state needs no colour; only a wait or a
/// loss earns a dot (design.md, "The accent").
enum ActivityTone { neutral, wait, loss }

class ActivityStatus {
  const ActivityStatus(this.label, [this.tone = ActivityTone.neutral]);
  final String label;
  final ActivityTone tone;
}

/// An amount as its source gave it. Bitcoin-denominated ones (BTC, LBTC)
/// that carry base units are re-written in the user's unit; an issued asset
/// keeps the figure and ticker the source gave, since only the source knows
/// its precision.
class ActivityAmount {
  const ActivityAmount({required this.ticker, required this.text, this.sats});

  final String ticker;

  /// The figure without its ticker, as the source wrote it.
  final String text;
  final int? sats;

  bool get isBitcoin => switch (ticker.toUpperCase()) {
    'BTC' || 'TBTC' || 'LBTC' || 'L-BTC' || 'TL-BTC' || 'RL-BTC' => true,
    _ => false,
  };

  /// `0.00100000 BTC`, `100,000 sats`, `25.00 USDT`.
  String format({required bool useSats}) {
    final s = sats;
    if (isBitcoin && s != null) {
      final coin = ticker.toUpperCase().contains('L') ? 'LBTC' : 'BTC';
      return PriceService.formatUnit(s, sat: useSats, coin: coin);
    }
    return '${_trimZeros(text)} $ticker'.trim();
  }

  /// `68.00000000` → `68.00`: zeros past the cents say nothing about the
  /// value. Anything that is not a plain decimal is left as it came.
  static String _trimZeros(String figure) {
    final m = RegExp(r'^([\d,]+)\.(\d+)$').firstMatch(figure.trim());
    if (m == null) return figure;
    var frac = m.group(2)!;
    while (frac.length > 2 && frac.endsWith('0')) {
      frac = frac.substring(0, frac.length - 1);
    }
    return '${m.group(1)}.$frac';
  }

  static ActivityAmount fromSats(int sats, String ticker) =>
      ActivityAmount(ticker: ticker, text: '$sats', sats: sats);

  static ActivityAmount fromLeg(SwapLeg leg) => ActivityAmount(
    ticker: leg.ticker,
    text: leg.displayAmount,
    sats: leg.amountSats,
  );

  static ActivityAmount fromMarketLeg(MarketLeg leg) => ActivityAmount(
    ticker: leg.ticker,
    text: leg.displayAmount,
    sats: leg.amountSats,
  );

  static ActivityAmount fromMoney(ProtocolMoney m) => ActivityAmount(
    ticker: m.ticker,
    text: protocolGroupDigits(m.amount),
    sats: m.sats,
  );
}

/// One row of an entry's detail: a fact in words, or an amount (masked by
/// the privacy switch, formatted in the user's unit).
class ActivityFact {
  const ActivityFact(this.label, this.text) : amount = null;
  const ActivityFact.amount(this.label, ActivityAmount this.amount)
    : text = null;

  final String label;
  final String? text;
  final ActivityAmount? amount;
}

/// A transaction an entry produced, with the chain whose explorer has it.
class ActivityTxRef {
  const ActivityTxRef(this.label, this.txid, this.chain);
  final String label;
  final String txid;
  final TxChain chain;
}

/// Anything the Activity timeline lists.
sealed class ActivityEntry {
  const ActivityEntry();

  ActivityKind get kind;

  /// A key unique across every source.
  String get id;

  /// When it happened; null when its source records no time.
  DateTime? get time;

  /// Still waiting on something (a confirmation, a taker, a signature, a
  /// deposit): the entry joins the "Pending" group at the top.
  bool get isPending;

  /// The chains it touches, for the chain filter.
  Set<TxChain> get chains;

  /// Every transaction id this entry owns. An on-chain transaction with one
  /// of these ids is the same event and is folded into this entry.
  List<String> get txids => [for (final r in txRefs) r.txid];

  List<ActivityTxRef> get txRefs;

  String get title;

  /// The row's subtitle, before the status.
  List<String> get facts;

  ActivityStatus? get status;

  /// The figure on the right of the row, and the one under it.
  ActivityAmount? get primary;
  ActivityAmount? get secondary;

  /// The asset badge on the glyph tile's corner.
  String? get badgeTicker;

  /// The detail's key/value rows, in order.
  List<ActivityFact> get details;

  /// Lower-cased text the search matches against.
  String get searchText => [
    title,
    ...facts,
    status?.label ?? '',
    ...txids,
    primary?.ticker ?? '',
    primary?.text ?? '',
    secondary?.ticker ?? '',
    secondary?.text ?? '',
    ...extraSearch,
  ].join(' ').toLowerCase();

  List<String> get extraSearch => const [];
}

// ── Payment ───────────────────────────────────────────────────────────────────

/// An on-chain transaction, as `list_activity` reports it. Drawn by the
/// payment row and detail the screen always had.
class PaymentEntry extends ActivityEntry {
  const PaymentEntry(this.tx);
  final Transaction tx;

  @override
  ActivityKind get kind => ActivityKind.payment;
  @override
  String get id => 'tx:${tx.txid}';

  /// An unconfirmed transaction carries no block time (both engines report
  /// 0); that is not a date.
  @override
  DateTime? get time =>
      tx.timestamp.millisecondsSinceEpoch == 0 ? null : tx.timestamp;
  @override
  bool get isPending => tx.confirmations == 0;
  @override
  Set<TxChain> get chains => {tx.chain};
  @override
  List<ActivityTxRef> get txRefs => [
    ActivityTxRef('Transaction ID', tx.txid, tx.chain),
  ];
  @override
  String get title => tx.title;
  @override
  List<String> get facts => const [];
  @override
  ActivityStatus? get status => null;
  @override
  ActivityAmount? get primary => null;
  @override
  ActivityAmount? get secondary => null;
  @override
  String? get badgeTicker => tx.chain == TxChain.bitcoin ? 'BTC' : tx.ticker;
  @override
  List<ActivityFact> get details => const [];

  // Amounts carry an upper-case ticker ('+0.001 BTC', '-12.50 USDT'), so
  // both sides are lower-cased or 'btc' would never match.
  @override
  String get searchText => [
    tx.txid,
    // The other transaction of a fee bump is folded into this row: its
    // txid must still find it.
    tx.bump?.otherTxid ?? '',
    tx.bump?.label ?? '',
    tx.note ?? '',
    tx.amount,
    tx.ticker,
    tx.directionLabel,
  ].join(' ').toLowerCase();
}

// ── Loans ─────────────────────────────────────────────────────────────────────

const ProtocolCopy _copy = ProtocolCopy.english;

String _role(String raw) => switch (raw.trim()) {
  'borrower' => 'Borrowed',
  'lender' => 'Lent',
  final other => _copy.role(other),
};

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `3 Dec`, or `3 Dec 2027` outside the current year.
String activityShortDate(DateTime t, {DateTime? now}) {
  final l = t.toLocal();
  final year = (now ?? DateTime.now()).year;
  final base = '${l.day} ${_months[l.month - 1]}';
  return l.year == year ? base : '$base ${l.year}';
}

/// `12 Sep 2026 14:05`.
String activityFullDate(DateTime t) {
  final l = t.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '${l.day} ${_months[l.month - 1]} ${l.year} $h:$m';
}

/// A Templar Protocol loan, as the connected site's portfolio reports it,
/// with the signatures this wallet recorded for it.
class LoanEntry extends ActivityEntry {
  const LoanEntry({
    required this.loan,
    required this.siteName,
    this.siteKey,
    this.signatures = const [],
  });

  final ProtocolLoan loan;
  final String siteName;

  /// The connected site's record key, for the loan's own page; null when
  /// there is none to open (the mock bridge's demo loans).
  final String? siteKey;

  /// Signing requests this wallet answered for this loan, newest first.
  final List<ProtocolSignRecord> signatures;

  bool get _awaitingSignature {
    final p = loan.pendingRequest;
    return p != null && !p.isExpired();
  }

  @override
  ActivityKind get kind => ActivityKind.loan;
  @override
  String get id => 'loan:${siteKey ?? siteName}:${loan.id}';

  /// The site's `opened_at`; else the first signature this wallet recorded
  /// for it; else none.
  @override
  DateTime? get time {
    final opened = loan.openedAt;
    if (opened != null) return opened.toLocal();
    if (signatures.isEmpty) return null;
    return signatures
        .map((s) => s.at)
        .reduce((a, b) => a.isBefore(b) ? a : b)
        .toLocal();
  }

  @override
  bool get isPending =>
      loan.state == ProtocolLoanState.originating || _awaitingSignature;
  @override
  Set<TxChain> get chains => const {TxChain.liquid};

  @override
  List<ActivityTxRef> get txRefs {
    final out = <ActivityTxRef>[];
    final seen = <String>{};
    void add(String label, String? txid) {
      if (txid == null || txid.isEmpty || !seen.add(txid)) return;
      out.add(ActivityTxRef(label, txid, TxChain.liquid));
    }

    add('Origination', loan.txids.origination);
    for (final n in loan.covenant?.nodes ?? const <ProtocolCovenantNode>[]) {
      final by = n.createdBy;
      add(
        by == null || by.isEmpty ? 'Covenant ${n.index + 1}' : _copy.action(by),
        n.txid,
      );
    }
    add('Current covenant', loan.covenant?.currentTxid);
    add('Repayment', loan.txids.repayment);
    add('Liquidation', loan.txids.liquidation);
    return out;
  }

  @override
  String get title => 'Loan ${loan.ref}';

  @override
  List<String> get facts {
    final plan = loan.repaymentPlan;
    final out = <String>[_role(loan.role)];
    if (plan?.nPaid != null && plan?.nTotal != null) {
      out.add('${plan!.nPaid} of ${plan.nTotal} paid');
    }
    final due = plan?.deadlineEstimate ?? loan.dueAtEstimate;
    if (loan.state.isOpen && due != null) {
      out.add('due ${activityShortDate(due)}');
    }
    return out;
  }

  @override
  ActivityStatus get status {
    if (_awaitingSignature) {
      return const ActivityStatus('Signature requested', ActivityTone.wait);
    }
    final word = loan.state == ProtocolLoanState.unknown
        ? _copy.state(loan.stateLabel)
        : _copy.state(loan.state.name);
    return switch (loan.state) {
      ProtocolLoanState.originating => ActivityStatus(word, ActivityTone.wait),
      ProtocolLoanState.defaulted ||
      ProtocolLoanState.liquidated => ActivityStatus(word, ActivityTone.loss),
      _ => ActivityStatus(word),
    };
  }

  @override
  ActivityAmount? get primary {
    final p = loan.principal;
    return p == null ? null : ActivityAmount.fromMoney(p);
  }

  @override
  ActivityAmount? get secondary {
    final c = loan.collateral;
    return c == null ? null : ActivityAmount.fromMoney(c);
  }

  @override
  String? get badgeTicker => loan.principal?.ticker;

  @override
  List<ActivityFact> get details {
    final plan = loan.repaymentPlan;
    final out = <ActivityFact>[
      ActivityFact('Status', status.label),
      ActivityFact('Role', _copy.role(loan.role)),
      ActivityFact('Site', siteName),
    ];
    final p = loan.principal;
    if (p != null) {
      out.add(ActivityFact.amount('Principal', ActivityAmount.fromMoney(p)));
    }
    final c = loan.collateral;
    if (c != null) {
      out.add(ActivityFact.amount('Collateral', ActivityAmount.fromMoney(c)));
    }
    final i = loan.interest;
    if (i != null) {
      out.add(ActivityFact.amount('Interest', ActivityAmount.fromMoney(i)));
      if (i.rateBps != null) {
        out.add(ActivityFact('Rate', protocolBpsLabel(i.rateBps!)));
      }
    }
    final owed = loan.owed;
    if (owed != null && loan.state.isOpen) {
      out.add(ActivityFact.amount('Owed', ActivityAmount.fromMoney(owed)));
    }
    if (plan?.nPaid != null && plan?.nTotal != null) {
      out.add(
        ActivityFact(
          'Installments',
          '${plan!.nPaid} of ${plan.nTotal} paid'
              '${plan.mMissed != null && plan.mMissed! > 0 ? ' · ${plan.mMissed} missed' : ''}',
        ),
      );
    }
    final due = plan?.deadlineEstimate ?? loan.dueAtEstimate;
    if (loan.state.isOpen && due != null) {
      out.add(ActivityFact('Next deadline', activityFullDate(due)));
    }
    final opened = loan.openedAt;
    if (opened != null) {
      out.add(ActivityFact('Opened', activityFullDate(opened)));
    }
    for (final s in signatures) {
      out.add(
        ActivityFact(
          s.action.isEmpty ? 'Signature' : _copy.action(s.action),
          '${s.outcome.label} · ${activityFullDate(s.at)}',
        ),
      );
    }
    return out;
  }

  @override
  List<String> get extraSearch => [loan.ref, siteName, loan.role];
}

/// A signing request this wallet answered that the portfolio does not
/// explain (no site token, the site offline, or a loan it no longer lists).
/// The store keeps the outcome, the loan reference and the action — no
/// amounts, by design (protocol_records.dart).
class LoanSignatureEntry extends ActivityEntry {
  const LoanSignatureEntry(this.record);
  final ProtocolSignRecord record;

  @override
  ActivityKind get kind => ActivityKind.loan;
  @override
  String get id =>
      'sign:${record.origin}:${record.loanRef}:${record.at.toIso8601String()}';
  @override
  DateTime? get time =>
      record.at.millisecondsSinceEpoch == 0 ? null : record.at.toLocal();
  @override
  bool get isPending => false;
  @override
  Set<TxChain> get chains => const {TxChain.liquid};
  @override
  List<ActivityTxRef> get txRefs => const [];
  @override
  String get title =>
      record.loanRef.isEmpty ? 'Templar Protocol' : 'Loan ${record.loanRef}';
  @override
  List<String> get facts => [
    if (record.action.isNotEmpty) _copy.action(record.action),
    record.site,
  ];
  @override
  ActivityStatus get status => ActivityStatus(
    record.outcome.label,
    record.outcome == ProtocolSignOutcome.failed
        ? ActivityTone.loss
        : ActivityTone.neutral,
  );
  @override
  ActivityAmount? get primary => null;
  @override
  ActivityAmount? get secondary => null;
  @override
  String? get badgeTicker => null;
  @override
  List<ActivityFact> get details => [
    ActivityFact('Outcome', record.outcome.label),
    if (record.action.isNotEmpty)
      ActivityFact('Request', _copy.action(record.action)),
    if (record.loanRef.isNotEmpty) ActivityFact('Loan', record.loanRef),
    ActivityFact('Site', record.site),
    if (record.origin.isNotEmpty) ActivityFact('Origin', record.origin),
    if (time != null) ActivityFact('Date', activityFullDate(record.at)),
  ];
  @override
  List<String> get extraSearch => [record.loanRef, record.origin];
}

// ── Swaps ─────────────────────────────────────────────────────────────────────

String _sentence(String raw) {
  final t = raw.replaceAll('_', ' ').trim();
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// A LiquiDEX offer this wallet made (`list_my_offers`).
class LiquidexSwapEntry extends ActivityEntry {
  const LiquidexSwapEntry(this.offer);
  final MyOffer offer;

  @override
  ActivityKind get kind => ActivityKind.swap;
  @override
  String get id => 'liquidex:${offer.offerId}';
  @override
  DateTime? get time => offer.createdAt <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(offer.createdAt * 1000);

  /// Open: waiting for a taker.
  @override
  bool get isPending => offer.status == 'open';
  @override
  Set<TxChain> get chains => const {TxChain.liquid};

  /// The offered outpoint is the coin put up, not a transaction of this
  /// swap, so it is shown but never claims an on-chain row.
  @override
  List<ActivityTxRef> get txRefs => const [];
  @override
  String get title => 'LiquiDEX swap';
  @override
  List<String> get facts => [
    'Maker',
    '${offer.offers.ticker} → ${offer.wants.ticker}',
  ];

  /// The engine's three words: open, closed (the offered coin was spent),
  /// cancelled. "Closed" is not "taken": the engine does not say which.
  @override
  ActivityStatus get status => switch (offer.status) {
    'open' => const ActivityStatus('Open', ActivityTone.wait),
    final other => ActivityStatus(_sentence(other)),
  };
  @override
  ActivityAmount get primary => ActivityAmount.fromLeg(offer.offers);
  @override
  ActivityAmount get secondary => ActivityAmount.fromLeg(offer.wants);
  @override
  String? get badgeTicker => offer.wants.ticker;
  @override
  List<ActivityFact> get details => [
    ActivityFact('Status', status.label),
    const ActivityFact('Role', 'Maker'),
    ActivityFact.amount('You give', primary),
    ActivityFact.amount('You get', secondary),
    if (time != null) ActivityFact('Created', activityFullDate(time!)),
    ActivityFact('Offer', offer.offerId),
  ];
  @override
  List<String> get extraSearch => [offer.offerId, offer.utxo];
}

/// One side of a Bitcoin ↔ Liquid HTLC swap (`atomic_swap_list`).
class AtomicSwapEntry extends ActivityEntry {
  const AtomicSwapEntry(this.swap);
  final AtomicSwap swap;

  static const Set<String> _done = {
    'claimed',
    'refunded',
    'cancelled',
    'expired',
    'completed',
    'failed',
  };

  bool get _maker => swap.role == 'maker';

  /// The offer's legs, oriented to this wallet: a maker gives what it
  /// offered, a taker gives what the maker wanted (as the LiquiDEX screen
  /// reads them).
  MarketLeg get gives => _maker ? swap.offered : swap.wanted;
  MarketLeg get gets => _maker ? swap.wanted : swap.offered;

  @override
  ActivityKind get kind => ActivityKind.swap;
  @override
  String get id => 'htlc:${swap.offerId}:${swap.role}';

  /// The engine's list carries no creation time.
  @override
  DateTime? get time => null;
  @override
  bool get isPending => !_done.contains(swap.status);
  @override
  Set<TxChain> get chains => const {TxChain.bitcoin, TxChain.liquid};
  @override
  List<ActivityTxRef> get txRefs => const [];
  @override
  String get title => 'Cross-chain swap';
  @override
  List<String> get facts => [
    _sentence(swap.role),
    '${gives.ticker} → ${gets.ticker}',
    if (swap.canFund) 'ready to fund',
    if (swap.canClaim) 'ready to claim',
    if (swap.canRefund) 'refund available',
  ];
  @override
  ActivityStatus get status => ActivityStatus(
    _sentence(swap.status.isEmpty ? 'unknown' : swap.status),
    swap.status == 'failed' || swap.status == 'expired'
        ? ActivityTone.loss
        : isPending
        ? ActivityTone.wait
        : ActivityTone.neutral,
  );
  @override
  ActivityAmount get primary => ActivityAmount.fromMarketLeg(gives);
  @override
  ActivityAmount get secondary => ActivityAmount.fromMarketLeg(gets);
  @override
  String? get badgeTicker => gets.ticker;
  @override
  List<ActivityFact> get details => [
    ActivityFact('Status', status.label),
    ActivityFact('Role', _sentence(swap.role)),
    ActivityFact.amount('You give', primary),
    ActivityFact.amount('You get', secondary),
    if (swap.nextAction.isNotEmpty && swap.nextAction != 'wait')
      ActivityFact('Next step', _sentence(swap.nextAction)),
    if (swap.makerTimeout > 0)
      ActivityFact('Maker timeout', 'block ${swap.makerTimeout}'),
    if (swap.takerTimeout != null && swap.takerTimeout! > 0)
      ActivityFact('Taker timeout', 'block ${swap.takerTimeout}'),
    ActivityFact('Offer', '#${swap.offerId}'),
  ];
  @override
  List<String> get extraSearch => ['${swap.offerId}', swap.role];
}

// ── Pegs ──────────────────────────────────────────────────────────────────────

/// A peg-in or peg-out order (`peg_list`).
class PegEntry extends ActivityEntry {
  const PegEntry(this.order);
  final PegOrder order;

  /// The provider's documented lifecycle (peg_models.dart). Cancelled is a
  /// branch off the first step, not a step.
  static const List<String> lifecycle = [
    'awaiting_deposit',
    'deposit_seen',
    'confirming',
    'settling',
    'completed',
  ];

  static String statusLabel(String raw) => switch (raw) {
    'awaiting_deposit' => 'Awaiting deposit',
    'deposit_seen' => 'Deposit seen',
    'confirming' => 'Confirming',
    'settling' => 'Settling',
    'completed' => 'Completed',
    'cancelled' => 'Cancelled',
    final other => _sentence(other),
  };

  bool get _in => order.isPegIn;
  String get fromTicker => _in ? 'BTC' : 'LBTC';
  String get toTicker => _in ? 'LBTC' : 'BTC';
  TxChain get _from => _in ? TxChain.bitcoin : TxChain.liquid;
  TxChain get _to => _in ? TxChain.liquid : TxChain.bitcoin;

  @override
  ActivityKind get kind => ActivityKind.peg;
  @override
  String get id => 'peg:${order.orderId}';
  @override
  DateTime? get time => order.createdAt <= 0
      ? null
      : DateTime.fromMillisecondsSinceEpoch(order.createdAt * 1000);
  @override
  bool get isPending => !order.isTerminal;
  @override
  Set<TxChain> get chains => const {TxChain.bitcoin, TxChain.liquid};
  @override
  List<ActivityTxRef> get txRefs => [
    if ((order.txidDeposit ?? '').isNotEmpty)
      ActivityTxRef('Deposit', order.txidDeposit!, _from),
    if ((order.txidPayout ?? '').isNotEmpty)
      ActivityTxRef('Payout', order.txidPayout!, _to),
  ];
  @override
  String get title => _in ? 'Peg-in' : 'Peg-out';

  /// `step 3 of 5` while it runs: the position in the provider's lifecycle.
  /// The order carries no confirmation count, so none is shown.
  String? get stepLabel {
    if (order.isTerminal) return null;
    final i = lifecycle.indexOf(order.status);
    return i < 0 ? null : 'step ${i + 1} of ${lifecycle.length}';
  }

  @override
  List<String> get facts => [
    '$fromTicker → $toTicker',
    ?stepLabel,
    if (order.simulated) 'simulated',
  ];
  @override
  ActivityStatus get status => ActivityStatus(
    statusLabel(order.status),
    order.isTerminal ? ActivityTone.neutral : ActivityTone.wait,
  );
  @override
  ActivityAmount get primary =>
      ActivityAmount.fromSats(order.depositExpectedSats, fromTicker);
  @override
  ActivityAmount get secondary =>
      ActivityAmount.fromSats(order.payoutExpectedSats, toTicker);
  @override
  String? get badgeTicker => toTicker;
  @override
  List<ActivityFact> get details => [
    ActivityFact('Status', status.label),
    if (stepLabel != null) ActivityFact('Progress', _sentence(stepLabel!)),
    ActivityFact('Direction', '$fromTicker → $toTicker'),
    ActivityFact.amount('Deposit', primary),
    ActivityFact.amount('Payout', secondary),
    for (final h in order.statusHistory)
      if (h.at > 0)
        ActivityFact(
          statusLabel(h.status),
          activityFullDate(DateTime.fromMillisecondsSinceEpoch(h.at * 1000)),
        ),
    if (order.simulated) const ActivityFact('Provider', 'Simulated'),
    if (order.depositAddress.isNotEmpty)
      ActivityFact('Deposit address', order.depositAddress),
    if (order.payoutAddress.isNotEmpty)
      ActivityFact('Payout address', order.payoutAddress),
    ActivityFact('Order', order.orderId),
  ];
  @override
  List<String> get extraSearch => [order.orderId, order.direction];
}

// ── Timeline ──────────────────────────────────────────────────────────────────

/// The merged list, and the on-chain transactions folded into a richer
/// entry (by txid), which that entry's detail can still open.
class ActivityTimeline {
  const ActivityTimeline({required this.entries, required this.linked});
  final List<ActivityEntry> entries;
  final Map<String, Transaction> linked;
}

/// Merges `list_activity` with the other sources. An on-chain transaction
/// whose txid an entry owns is the same event: the entry stays (it knows
/// more), the transaction leaves the list and is kept in
/// [ActivityTimeline.linked]. Then: pending first, newest first, undated
/// last; ties keep the order their sources gave.
ActivityTimeline mergeActivity(
  List<Transaction> txs,
  List<ActivityEntry> extras,
) {
  final claimed = <String>{for (final e in extras) ...e.txids};
  final linked = <String, Transaction>{};
  final entries = <ActivityEntry>[];
  for (final tx in txs) {
    if (claimed.contains(tx.txid)) {
      linked[tx.txid] = tx;
    } else {
      entries.add(PaymentEntry(tx));
    }
  }
  entries.addAll(extras);
  return ActivityTimeline(entries: sortActivity(entries), linked: linked);
}

int _bucket(ActivityEntry e) => e.isPending ? 0 : (e.time == null ? 2 : 1);

/// Pending, then dated newest first, then undated. Within "Pending" an
/// entry without a time (an unconfirmed payment) leads. Stable.
List<ActivityEntry> sortActivity(List<ActivityEntry> entries) {
  final indexed = [for (var i = 0; i < entries.length; i++) (i, entries[i])];
  indexed.sort((a, b) {
    final ba = _bucket(a.$2);
    final bb = _bucket(b.$2);
    if (ba != bb) return ba - bb;
    final ta = a.$2.time;
    final tb = b.$2.time;
    if (ta != null || tb != null) {
      if (ta == null) return -1;
      if (tb == null) return 1;
      final c = tb.compareTo(ta);
      if (c != 0) return c;
    }
    return a.$1 - b.$1;
  });
  return [for (final e in indexed) e.$2];
}

/// The label of an entry's group: "Pending", "Today", "Yesterday",
/// "12 Sep 2026", or "Undated".
String activityGroupLabel(ActivityEntry e, {DateTime? now}) {
  if (e.isPending) return 'Pending';
  final t = e.time;
  if (t == null) return 'Undated';
  final dt = t.toLocal();
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(dt.year, dt.month, dt.day);
  if (d == today) return 'Today';
  if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
}

/// Consecutive entries with the same label, in order.
List<({String label, List<ActivityEntry> entries})> groupActivity(
  List<ActivityEntry> sorted, {
  DateTime? now,
}) {
  final out = <({String label, List<ActivityEntry> entries})>[];
  for (final e in sorted) {
    final label = activityGroupLabel(e, now: now);
    if (out.isEmpty || out.last.label != label) {
      out.add((label: label, entries: <ActivityEntry>[]));
    }
    out.last.entries.add(e);
  }
  return out;
}

/// The chain filter ('all' | 'bitcoin' | 'liquid'), the kind filter (null
/// = all) and the search, applied together.
List<ActivityEntry> filterActivity(
  List<ActivityEntry> entries, {
  String chain = 'all',
  ActivityKind? kind,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return entries.where((e) {
    if (chain == 'bitcoin' && !e.chains.contains(TxChain.bitcoin)) {
      return false;
    }
    if (chain == 'liquid' && !e.chains.contains(TxChain.liquid)) return false;
    if (kind != null && e.kind != kind) return false;
    return q.isEmpty || e.searchText.contains(q);
  }).toList();
}
