// The Activity screen's sources beyond `list_activity`: Templar Protocol
// loans, LiquiDEX offers, Bitcoin ↔ Liquid HTLC swaps and peg orders.
//
// Each source is queried only when the wallet has it (the same conditions
// the sidebar uses to show its page), and each one fails alone: a source
// that throws contributes nothing and its name, never an empty screen.

import '../../bridge/mock_wallet_bridge.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/protocol_portfolio_service.dart';
import '../../services/protocol_store.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/models/protocol_records.dart';
import 'models/activity_entry.dart';

/// Which sources the active wallet has.
class ActivitySourceFlags {
  const ActivitySourceFlags({
    required this.bitcoin,
    required this.liquid,
    this.loans = false,
    this.liquidDex = false,
    this.peg = false,
  });

  final bool bitcoin;
  final bool liquid;
  final bool loans;
  final bool liquidDex;
  final bool peg;

  /// Loans live on Liquid (a loan is a Liquid covenant).
  bool get hasLoans => liquid && loans;

  /// LiquiDEX offers and the HTLC swaps both live on the LiquiDEX page.
  bool get hasSwaps => liquid && liquidDex;

  /// A peg needs both chains: a Liquid-only wallet has nothing to peg out to.
  bool get hasPegs => liquid && bitcoin && peg;

  /// The kinds the kind filter offers, payments always first.
  List<ActivityKind> get kinds => [
    ActivityKind.payment,
    if (hasLoans) ActivityKind.loan,
    if (hasSwaps) ActivityKind.swap,
    if (hasPegs) ActivityKind.peg,
  ];
}

/// Loads a wallet's loan entries. The app reads [ProtocolStore] and the
/// connected sites' portfolios; tests and the mock bridge pass their own.
typedef LoanActivityLoader =
    Future<List<ActivityEntry>> Function(String walletId, String? walletName);

/// What the extra sources returned: the entries, and the sources that
/// failed, by name ("loans", "swaps", "pegs").
class ActivityExtras {
  const ActivityExtras({this.entries = const [], this.failed = const []});
  final List<ActivityEntry> entries;
  final List<String> failed;
}

class ActivitySources {
  ActivitySources({required this.bridge, LoanActivityLoader? loans})
    : _loans = loans ?? _defaultLoans(bridge);

  final WalletBridge bridge;
  final LoanActivityLoader _loans;

  /// The last answer per wallet, so coming back to the page does not make
  /// the extra rows pop in again. In memory only.
  static final Map<String, ActivityExtras> _cache = {};

  static ActivityExtras? cached(String walletId) => _cache[walletId];

  /// The kind a source (as named in [ActivityExtras.failed]) feeds.
  static ActivityKind kindOf(String source) => switch (source) {
    _loansName => ActivityKind.loan,
    _pegsName => ActivityKind.peg,
    _ => ActivityKind.swap,
  };

  static const _loansName = 'loans';
  static const _offersName = 'LiquiDEX offers';
  static const _htlcName = 'cross-chain swaps';
  static const _pegsName = 'pegs';

  /// Test seam.
  static void clearCache() => _cache.clear();

  Future<ActivityExtras> load(
    String walletId,
    ActivitySourceFlags flags, {
    String? walletName,
  }) async {
    final jobs = <(String, Future<List<ActivityEntry>> Function())>[
      if (flags.hasLoans) (_loansName, () => _loans(walletId, walletName)),
      if (flags.hasSwaps)
        (
          _offersName,
          () async => [
            for (final o in await bridge.listMyOffers(walletId))
              LiquidexSwapEntry(o),
          ],
        ),
      // HTLC swaps move coins on both chains.
      if (flags.hasSwaps && flags.bitcoin)
        (
          _htlcName,
          () async => [
            for (final s in await bridge.atomicSwapList(walletId))
              AtomicSwapEntry(s),
          ],
        ),
      if (flags.hasPegs)
        (
          _pegsName,
          () async => [
            for (final p in await bridge.pegList(walletId)) PegEntry(p),
          ],
        ),
    ];
    final results = await Future.wait([
      for (final (name, run) in jobs) _guard(name, run),
    ]);
    final out = ActivityExtras(
      entries: [for (final r in results) ...?r.$2],
      failed: [
        for (final r in results)
          if (r.$2 == null) r.$1,
      ],
    );
    _cache[walletId] = out;
    return out;
  }

  /// Runs one source; any throw (an engine error, a method the bridge does
  /// not implement) becomes "this source failed".
  static Future<(String, List<ActivityEntry>?)> _guard(
    String name,
    Future<List<ActivityEntry>> Function() run,
  ) async {
    try {
      return (name, await run());
    } catch (_) {
      return (name, null);
    }
  }

  static LoanActivityLoader _defaultLoans(WalletBridge bridge) {
    // The mock bridge has no site to ask; it serves a demo portfolio so the
    // timeline can be looked at without one (the mock badge stays up).
    if (bridge is MockWalletBridge) {
      return (walletId, _) async {
        final json = bridge.demoLoanPortfolio(walletId);
        if (json == null) return const [];
        final p = ProtocolPortfolio.fromJson(json);
        return [for (final l in p.loans) LoanEntry(loan: l, siteName: p.site)];
      };
    }
    return (walletId, walletName) =>
        loadProtocolLoanActivity(walletId: walletId, walletName: walletName);
  }
}

/// The wallet's loans from what Templar Protocol left on this device: the
/// portfolio of every connected site that handed back a token (the last
/// answer in memory, else one fetch), and the signing records. A record
/// whose loan the portfolio lists is folded into that loan; the rest stand
/// alone. Records name their wallet, not its id, so they are matched by the
/// active wallet's name.
///
/// Throws only when nothing could be read: a portfolio that fails while the
/// records load still yields the records.
Future<List<ActivityEntry>> loadProtocolLoanActivity({
  required String walletId,
  required String? walletName,
  ProtocolStore? store,
  ProtocolPortfolioService? service,
}) async {
  final st = store ?? ProtocolStore.instance;
  final svc = service ?? ProtocolPortfolioService.instance;
  final sites = await st.sitesForWallet(walletId);
  final name = (walletName ?? '').trim();
  final records = name.isEmpty
      ? <ProtocolSignRecord>[]
      : (await st.history()).where((r) => r.walletName == name).toList();

  final out = <ActivityEntry>[];
  final used = <ProtocolSignRecord>{};
  Object? failure;
  for (final site in sites.where((s) => s.hasPortfolio)) {
    ProtocolPortfolio? portfolio = svc.snapshot(site.key)?.portfolio;
    if (portfolio == null) {
      try {
        portfolio = await svc.refresh(site);
      } catch (e) {
        failure = e;
        continue;
      }
    }
    for (final loan in portfolio.loans) {
      final mine = records
          .where((r) => r.origin == site.origin && r.loanRef == loan.ref)
          .toList();
      used.addAll(mine);
      out.add(
        LoanEntry(
          loan: loan,
          siteName: site.site,
          siteKey: site.key,
          signatures: mine,
        ),
      );
    }
  }
  out.addAll([
    for (final r in records)
      if (!used.contains(r)) LoanSignatureEntry(r),
  ]);
  if (out.isEmpty && failure != null) throw failure;
  return out;
}
