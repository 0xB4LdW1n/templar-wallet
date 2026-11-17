import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../liquid/form_parts.dart';
import '../settings/test_server_switch.dart';
import 'make_offer_flow.dart';
import 'order_book_admin.dart';
import 'publish_error.dart';
import 'atomic_offer_flow.dart';
import 'models/swap_offer.dart';
import 'swap_gate.dart';
import 'take_flow.dart';

enum _MarketFilter { all, crossChain, liquid }

/// Chain-aware market over the order book the engine uses (a joined test
/// server's, an environment override or the local default). Liquid rows use
/// LiquiDEX; Bitcoin ↔ Liquid rows use the recoverable HTLC v1 state machine.
class SwapScreen extends StatefulWidget {
  const SwapScreen({super.key});

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final _bridge = walletBridge;

  List<MarketOffer> _markets = [];
  List<MyOffer> _myOffers = [];
  List<AtomicSwap> _myAtomic = [];
  bool _loading = true;
  bool _loadingMine = true;
  bool _includeUnavailable = false;
  bool _cancelling = false;
  bool _justRefreshed = false;
  String? _error;

  /// Why this wallet's LiquiDEX offers, or its cross-chain swaps, could not
  /// be read. The two lists load apart: one failing never hides the other.
  String? _offersError;
  String? _atomicError;
  _MarketFilter _filter = _MarketFilter.all;

  String? get _walletId => context.read<AppState>().activeWalletId;

  /// The cross-chain (BTC ↔ Liquid HTLC) routes exist only on Liquid
  /// testnet: on a regtest — a test server's — there is no coordinator, so
  /// their filter, settlement choice, rows and words are not drawn at all.
  bool get _crossChain => crossChainAvailable(context.read<AppState>());

  List<MarketOffer> get _visibleMarkets => _markets.where((offer) {
    if (!_crossChain && (offer.isCrossChain || offer.isAtomic)) return false;
    return switch (_crossChain ? _filter : _MarketFilter.all) {
      _MarketFilter.all => true,
      _MarketFilter.crossChain => offer.isCrossChain,
      _MarketFilter.liquid => !offer.isCrossChain,
    };
  }).toList();

  @override
  void initState() {
    super.initState();
    _refresh(feedback: false);
    // First use of the market this session: ask the joined test server
    // whether its chains were reset (once; no polling).
    checkTestServerOnce(context.read<AppState>(), bridge: _bridge);
  }

  Future<void> _rejoin(String url) async {
    try {
      final done = await joinTestServer(
        context,
        url,
        rejoin: true,
        bridge: _bridge,
      );
      if (!mounted || done == null) return;
      if (done.walletClosed) {
        context.go(AppRoutes.walletPicker);
      } else {
        _refresh(silent: true);
      }
    } on TestServerError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _loadMarkets({bool silent = false}) async {
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final markets = await _bridge.listMarkets(
        includeUnavailable: _includeUnavailable,
      );
      if (!mounted) return;
      setState(() {
        _markets = markets;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = swapError(error);
        _loading = false;
      });
    }
  }

  Future<void> _loadMine({bool silent = false}) async {
    final walletId = _walletId;
    if (walletId == null) {
      setState(() => _loadingMine = false);
      return;
    }
    setState(() {
      if (!silent) _loadingMine = true;
      _offersError = null;
      _atomicError = null;
    });
    final crossChain = _crossChain;
    // Apart, so a stale cross-chain record (a coordinator's 404) can never
    // hide this wallet's LiquiDEX offers, nor the other way round.
    Future<void> offers() async {
      try {
        final list = await _bridge.listMyOffers(walletId);
        if (mounted) setState(() => _myOffers = list);
      } catch (error) {
        if (mounted) {
          setState(() {
            _myOffers = [];
            _offersError = plainBookError(
              error,
              what: 'This wallet\'s LiquiDEX offers could not be read',
            );
          });
        }
      }
    }

    Future<void> atomic() async {
      if (!crossChain) {
        if (mounted) setState(() => _myAtomic = []);
        return;
      }
      try {
        final list = await _bridge.atomicSwapList(walletId);
        if (mounted) setState(() => _myAtomic = list);
      } catch (error) {
        if (mounted) {
          setState(() {
            _myAtomic = [];
            _atomicError = plainBookError(
              error,
              what: 'The cross-chain swaps could not be read',
            );
          });
        }
      }
    }

    await Future.wait([offers(), atomic()]);
    if (mounted) setState(() => _loadingMine = false);
  }

  Future<void> _refresh({bool silent = false, bool feedback = true}) async {
    await Future.wait([
      _loadMarkets(silent: silent),
      _loadMine(silent: silent),
    ]);
    if (!mounted || !feedback || _error != null || _offersError != null) {
      return;
    }
    setState(() => _justRefreshed = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _justRefreshed = false);
  }

  /// The book's admin page, only for a book on this machine.
  Uri? get _adminUri => orderBookAdminUri(context.read<AppState>());

  Future<void> _openAdmin() async {
    final uri = _adminUri;
    if (uri != null) await openOrderBookAdmin(context, uri);
  }

  Future<void> _takeProposal(String proposalJson) async {
    final txid = await openTakeFlow(context, proposalJson: proposalJson);
    if (txid != null && mounted) _refresh(silent: true);
  }

  Future<void> _importProposal() async {
    final proposal = await showImportProposalDialog(context);
    if (proposal != null && mounted) await _takeProposal(proposal);
  }

  Future<void> _makeOffer() async {
    final st = context.read<AppState>();
    // Off Liquid testnet there is one settlement: straight to LiquiDEX.
    if (!_crossChain) {
      final created = await openMakeOfferFlow(context);
      if (created != null && mounted) _refresh(silent: true);
      return;
    }
    final type = await showAppDialog<String>(
      context,
      builder: (dialogContext) => AppDialog(
        title: const Text('Choose settlement'),
        content: SizedBox(
          width: 430,
          child: Text(
            'Cross-chain uses recoverable HTLCs between Bitcoin '
            '${st.bitcoinNetworkName} and Liquid ${st.liquidNetworkName}. '
            'LiquiDEX exchanges two Liquid assets in one transaction.',
          ),
        ),
        actions: [
          SecondaryButton(
            label: 'Liquid · LiquiDEX',
            icon: Icons.water_drop_outlined,
            onPressed: () => Navigator.of(dialogContext).pop('liquid'),
          ),
          PrimaryButton(
            label: 'BTC ↔ Liquid',
            icon: Icons.lock_clock_outlined,
            onPressed: () => Navigator.of(dialogContext).pop('atomic'),
          ),
        ],
      ),
    );
    if (!mounted || type == null) return;
    final created = type == 'atomic'
        ? await openAtomicOfferFlow(context)
        : await openMakeOfferFlow(context);
    if (created != null && mounted) _refresh(silent: true);
  }

  Future<void> _joinAtomic(MarketOffer offer) async {
    final walletId = _walletId;
    if (walletId == null) return;
    try {
      await _bridge.atomicSwapJoin(walletId, offer.sourceId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offer reserved — the maker funds first')),
      );
      await _refresh(silent: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(swapError(error))));
      }
    }
  }

  Future<void> _atomicAction(AtomicSwap swap, String action) async {
    final walletId = _walletId;
    if (walletId == null) return;
    // Funding, claiming and refunding an HTLC sign with this wallet's key.
    if (!await confirmSwapSignature(context, 'the HTLC $action') || !mounted) {
      return;
    }
    try {
      switch (action) {
        case 'fund':
          await _bridge.atomicSwapFund(walletId, swap.offerId);
        case 'claim':
          await _bridge.atomicSwapClaim(walletId, swap.offerId);
        case 'refund':
          await _bridge.atomicSwapRefund(walletId, swap.offerId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Swap $action transaction broadcast')),
      );
      await _refresh(silent: true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(swapError(error))));
      }
    }
  }

  Future<void> _publishOffer(MyOffer offer) async {
    try {
      final id = await _bridge.swapPublish(offer.proposalJson);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Published as order #$id')));
      _loadMarkets();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(swapPublishErrorText(error))));
    }
  }

  Future<void> _cancelOffer(MyOffer offer) async {
    final walletId = _walletId;
    if (walletId == null || _cancelling) return;
    final confirmed =
        await showAppDialog<bool>(
          context,
          builder: (dialogContext) => AppDialog(
            title: const Text('Cancel this offer?'),
            content: SizedBox(
              width: 440,
              child: Text(
                'Cancelling self-spends the offered coin. The proposal becomes '
                'invalid everywhere it was shared and a small network fee applies.',
                style: AppTypography.bodySmall,
              ),
            ),
            actions: [
              GhostButton(
                label: 'Keep offer',
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              DangerButton(
                label: 'Cancel offer',
                icon: Icons.cancel_outlined,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    if (!await confirmSwapSignature(context, 'the cancellation') || !mounted) {
      return;
    }

    setState(() => _cancelling = true);
    try {
      final txid = await _bridge.swapCancel(walletId, offer.offerId);
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Offer cancelled — txid $txid')));
      _loadMine();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _offersError = swapError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = AppSpacing.pagePadding(context);
    return Scaffold(
      body: PageBackground.flat(
        child: RefreshIndicator(
          onRefresh: () => _refresh(silent: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.all(pad),
                sliver: SliverToBoxAdapter(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpacing.contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _marketHeader(),
                          ..._staleNotice(),
                          _orderBookExplainer(),
                          const SizedBox(height: AppSpacing.xl),
                          _filters(),
                          const SizedBox(height: AppSpacing.xl),
                          _marketSection(),
                          const SizedBox(height: AppSpacing.xl),
                          _myOffersSection(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The joined test server's chains were reset: the book and the wallet
  /// no longer agree on the chain until the user re-joins.
  List<Widget> _staleNotice() {
    final st = context.watch<AppState>();
    final url = st.testServer?.profile?.baseUrl;
    if (!st.testServerStale || url == null) return const [];
    return [
      WarningBanner(
        title: 'The test chain was reset',
        message:
            '${st.testServerName} now runs a new chain. Re-join it to see its '
            'order book and your regtest coins again.',
        action: SecondaryButton(
          label: 'Re-join',
          icon: Icons.restart_alt,
          dense: true,
          onPressed: () => _rejoin(url),
        ),
      ),
      const SizedBox(height: AppSpacing.lg),
    ];
  }

  /// The page's name, the market's state as one quiet line of meta (which
  /// book, which network), the tools as outlined icon buttons and the one
  /// thing the page exists for: "New offer". On a phone the tools take their
  /// own row and "New offer" spans the column under them.
  Widget _marketHeader() {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final st = context.watch<AppState>();
    String sentence(String word) =>
        word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}';
    // Which book this is: a tester comparing two wallets must be able to
    // tell at a glance that both look at the same one — the joined test
    // server by name, a remote book by host, or the local default.
    final book = st.testServer?.active.orderbook;
    final labName = st.testServerName;
    final bookLabel =
        labName ??
        (book == null || book.isLoopback
            ? 'Local order book'
            : Uri.tryParse(book.origin.url)?.host ?? book.origin.url);
    // The network the routes settle on; both chains named when they differ
    // (a Liquid regtest beside Bitcoin testnet).
    final liquidNet = st.liquidNetworkName;
    final bitcoinNet = st.bitcoinNetworkName;
    final networkLabel = liquidNet == bitcoinNet
        ? sentence(liquidNet)
        : 'Liquid $liquidNet · Bitcoin $bitcoinNet';
    final admin = orderBookAdminUri(st);
    final openRoutes = _markets.where((offer) => offer.available).length;
    // Only a reported live state earns the green dot; connecting and empty
    // say so in words, an offline book in the danger ink.
    final (status, Color? dot) = _loading
        ? ('Connecting', null)
        : _error != null
        ? ('Market offline', s.danger)
        : openRoutes == 0
        ? ('No open routes', null)
        : ('$openRoutes open route${openRoutes == 1 ? '' : 's'}', s.success);

    final meta = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              StatusDot(dot),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              status,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
        Text('·', style: AppTypography.caption.copyWith(color: s.inkFaint)),
        Text(
          bookLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        Text('·', style: AppTypography.caption.copyWith(color: s.inkFaint)),
        Text(
          networkLabel,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );

    final tools = <Widget>[
      OutlinedIconAction(
        icon: _justRefreshed ? Icons.check : Icons.refresh,
        tooltip: _justRefreshed ? 'Market updated' : 'Refresh market',
        onPressed: _loading ? null : () => _refresh(silent: true),
      ),
      OutlinedIconAction(
        icon: Icons.input_outlined,
        tooltip: 'Import proposal',
        onPressed: _importProposal,
      ),
      OutlinedIconAction(
        icon: Icons.info_outline,
        tooltip: 'How it works',
        onPressed: _showOrderBookGuide,
      ),
      if (admin != null)
        OutlinedIconAction(
          icon: Icons.tune_outlined,
          tooltip: 'Order book admin',
          onPressed: _openAdmin,
        ),
    ];

    final newOffer = PrimaryButton(
      label: 'New offer',
      icon: Icons.add,
      isFullWidth: phone,
      onPressed: _makeOffer,
    );

    final title = Text(
      'LiquiDEX',
      style: AppTypography.pageTitleOf(context).copyWith(color: s.ink),
    );

    if (phone) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: AppSpacing.xs),
            meta,
            const SizedBox(height: AppSpacing.lg),
            newOffer,
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                for (var i = 0; i < tools.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  tools[i],
                ],
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                title,
                const SizedBox(height: AppSpacing.xs),
                meta,
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          for (final t in tools) ...[t, const SizedBox(width: AppSpacing.sm)],
          const SizedBox(width: AppSpacing.xs),
          newOffer,
        ],
      ),
    );
  }

  Widget _orderBookExplainer() {
    return InfoBanner(
      title: 'Maker posts; taker completes',
      message:
          'The order book stores signed public proposals, never keys or funds. '
          'A Liquid taker checks the proposal, pays the requested asset and '
          'receives the offered asset in one atomic transaction.',
      action: GhostButton(
        label: 'Two-wallet test',
        icon: Icons.account_balance_wallet_outlined,
        onPressed: _showOrderBookGuide,
      ),
    );
  }

  Future<void> _showOrderBookGuide() async {
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => AppDialog(
        title: const Text('How the order book works'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const InfoBanner(
                  title: 'Non-custodial by design',
                  message:
                      'The service coordinates public offers. Signing stays in '
                      'each wallet. A real LiquiDEX swap settles both Liquid '
                      'asset legs together, or neither leg settles.',
                ),
                const SizedBox(height: AppSpacing.lg),
                _guideStep(
                  1,
                  'Wallet A · make',
                  'Choose one funded Liquid coin, set the asset and amount wanted, then publish it.',
                ),
                _guideStep(
                  2,
                  'Wallet B · check',
                  'Use the same network (and the same test server), refresh, and open the offer. “Receive” is what B gets; “Pay” is what B spends.',
                ),
                _guideStep(
                  3,
                  'Wallet B · take',
                  'Review the checks the wallet ran on the proposal, sign, and broadcast the completed atomic transaction.',
                ),
                _guideStep(
                  4,
                  'Wallet A · sync',
                  'Switch back or open the other wallet instance and sync to see the received asset and spent offer coin.',
                  last: true,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  _crossChain
                      ? 'Both wallets need the asset they pay plus LBTC for '
                            'fees. BTC routes marked HTLC v1 use two funding '
                            'transactions, a shared preimage and recoverable '
                            'timeouts.'
                      : 'Both wallets need the asset they pay plus LBTC for '
                            'fees.',
                  style: AppTypography.caption.copyWith(
                    color: AppScheme.of(context).inkSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          SecondaryButton(
            label: 'Got it',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

  /// One step of the guide: its number as quiet text in a raised tile, the
  /// title, the sentence under it.
  Widget _guideStep(
    int number,
    String title,
    String body, {
    bool last = false,
  }) {
    final s = AppScheme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: s.panelInset,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
            ),
            child: Text(
              '$number',
              style: AppTypography.label.copyWith(color: s.inkSecondary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.label.copyWith(color: s.ink)),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() {
    final phone = AppLayout.isPhone(context);
    context.watch<AppState>();
    final closed = ChoiceTile(
      label: 'Closed',
      selected: _includeUnavailable,
      tooltip: 'Show closed and cancelled offers',
      onSelected: _loading
          ? null
          : () {
              setState(() => _includeUnavailable = !_includeUnavailable);
              _loadMarkets();
            },
    );
    // One settlement here: nothing to filter by, only closed offers.
    if (!_crossChain) {
      return Align(alignment: Alignment.centerLeft, child: closed);
    }
    final segments = SegmentedSwitch<_MarketFilter>(
      options: const [
        SegOption(value: _MarketFilter.all, label: 'All'),
        SegOption(value: _MarketFilter.crossChain, label: 'BTC routes'),
        SegOption(value: _MarketFilter.liquid, label: 'Liquid assets'),
      ],
      selected: _filter,
      onChanged: (value) => setState(() => _filter = value),
      expand: phone,
    );
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          segments,
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: Alignment.centerLeft, child: closed),
        ],
      );
    }
    return Row(children: [segments, const Spacer(), closed]);
  }

  Widget _marketSection() {
    final markets = _visibleMarkets;
    final admin = orderBookAdminUri(context.watch<AppState>());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionLabel(
          label: _loading ? 'Markets' : 'Markets · ${markets.length}',
          actionLabel: admin != null ? 'Book admin' : null,
          onAction: admin != null ? _openAdmin : null,
        ),
        if (_loading)
          const ListCard(
            children: [
              SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          )
        else if (_error != null)
          _marketError()
        else if (markets.isEmpty)
          _emptyMarkets()
        else
          ListCard(children: [for (final offer in markets) _marketRow(offer)]),
      ],
    );
  }

  Widget _marketError() {
    final s = AppScheme.of(context);
    return ListCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Icon(Icons.cloud_off_outlined, size: 24, color: s.inkFaint),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Order book is offline',
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  SecondaryButton(
                    label: 'Retry',
                    icon: Icons.refresh,
                    onPressed: _loadMarkets,
                  ),
                  if (_adminUri != null)
                    GhostButton(
                      label: 'Open admin',
                      icon: Icons.tune_outlined,
                      onPressed: _openAdmin,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyMarkets() {
    final s = AppScheme.of(context);
    return ListCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            children: [
              Text(
                'No matching markets',
                style: AppTypography.body.copyWith(color: s.ink),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _adminUri != null
                    ? 'Publish an offer, or post test quotes from the order '
                          'book admin'
                    : 'Publish an offer to open the first market',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The venue of a route, as a word: neutral, sentence case.
  static String _venue(MarketOffer offer) => offer.demo
      ? 'HTLC demo'
      : offer.isAtomic
      ? 'HTLC v1'
      : 'LiquiDEX';

  Widget _marketRow(MarketOffer offer) {
    final s = AppScheme.of(context);
    final gives = offer.makerGives;
    final wants = offer.makerWants;
    final unavailable = !offer.available;
    final status = offer.status.replaceAll('_', ' ');

    return _SwapRow(
      semanticLabel:
          'Receive ${gives.displayAmount} ${gives.ticker}; pay '
          '${wants.displayAmount} ${wants.ticker}',
      leading: _PairedLogos(first: gives.ticker, second: wants.ticker),
      title: 'Receive ${gives.displayAmount} ${marketLegName(gives)}',
      titleInk: unavailable ? s.inkFaint : s.ink,
      subtitle:
          'Pay ${wants.displayAmount} ${marketLegName(wants)}'
          '${offer.priceDisplay.isEmpty ? '' : ' · ${offer.priceDisplay}'}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unavailable) ...[
            Text(
              status.isEmpty
                  ? status
                  : '${status[0].toUpperCase()}${status.substring(1)}',
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          QuietTag(label: _venue(offer)),
        ],
      ),
      chevron: true,
      onTap: () => _showMarketDetails(offer),
    );
  }

  Widget _myOffersSection() {
    final s = AppScheme.of(context);
    Widget note(String text, Color ink) => ListCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(text, style: AppTypography.caption.copyWith(color: ink)),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ListSectionLabel(label: 'My swaps'),
        if (_loadingMine)
          const ListCard(
            children: [
              SizedBox(
                height: 72,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
          )
        else ...[
          if (_myOffers.isNotEmpty)
            ListCard(
              children: [for (final offer in _myOffers) _myOfferRow(offer)],
            )
          else if (_offersError != null)
            note(_offersError!, s.inkSecondary)
          else if (_myAtomic.isEmpty && _atomicError == null)
            note(
              _crossChain
                  ? 'Offers and active HTLC swaps created by this wallet '
                        'appear here'
                  : 'Offers created by this wallet appear here',
              s.inkSecondary,
            ),
          if (_myOffers.isNotEmpty && _offersError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            note(_offersError!, s.inkSecondary),
          ],
          // Cross-chain swaps: Liquid testnet only, read on their own.
          if (_crossChain && (_myAtomic.isNotEmpty || _atomicError != null))
            ...[
              const SizedBox(height: AppSpacing.lg),
              const ListSectionLabel(label: 'Cross-chain swaps'),
              if (_myAtomic.isNotEmpty)
                ListCard(
                  children: [for (final w in _myAtomic) _atomicSwapRow(w)],
                )
              else
                note(_atomicError!, s.inkSecondary),
            ],
        ],
      ],
    );
  }

  Widget _atomicSwapRow(AtomicSwap swap) {
    final action = swap.canFund
        ? 'fund'
        : swap.canClaim
        ? 'claim'
        : swap.canRefund
        ? 'refund'
        : null;
    final gives = swap.role == 'maker' ? swap.offered : swap.wanted;
    final gets = swap.role == 'maker' ? swap.wanted : swap.offered;
    final status = swap.status.replaceAll('_', ' ');
    if (!swap.isLive) {
      // Not this book's live row: what the record is, in words, and no
      // action (nothing would be signed against it).
      final known = gives.amountSats > 0 || gets.amountSats > 0;
      return _SwapRow(
        semanticLabel: 'Cross-chain swap ${swap.offerId}',
        leading: _PairedLogos(
          first: known ? gives.ticker : 'BTC',
          second: known ? gets.ticker : 'LBTC',
        ),
        title: known
            ? '${gives.displayAmount} ${gives.ticker} → '
                  '${gets.displayAmount} ${gets.ticker}'
            : 'Cross-chain swap #${swap.offerId}',
        subtitle:
            '#${swap.offerId} · ${atomicAvailabilityText(swap.availability)}',
        trailing: StatusBadge(
          label: atomicAvailabilityBadge(swap.availability),
          variant: swap.availability == 'book_mismatch'
              ? BadgeVariant.warning
              : BadgeVariant.neutral,
        ),
      );
    }
    return _SwapRow(
      semanticLabel:
          '${gives.displayAmount} ${gives.ticker} to '
          '${gets.displayAmount} ${gets.ticker}',
      leading: _PairedLogos(first: gives.ticker, second: gets.ticker),
      title:
          '${gives.displayAmount} ${gives.ticker} → '
          '${gets.displayAmount} ${gets.ticker}',
      subtitle: '#${swap.offerId} · ${swap.role} · $status',
      // The page's one filled control is "New offer"; a row's action is a
      // quiet button beside its data.
      trailing: action == null
          ? StatusBadge(label: _sentence(status))
          : SecondaryButton(
              label: action == 'fund'
                  ? 'Fund HTLC'
                  : action == 'claim'
                  ? 'Claim'
                  : 'Refund',
              icon: action == 'refund'
                  ? Icons.undo_outlined
                  : Icons.lock_open_outlined,
              dense: true,
              onPressed: () => _atomicAction(swap, action),
            ),
    );
  }

  Widget _myOfferRow(MyOffer offer) {
    final open = offer.status == 'open';
    final phone = AppLayout.isPhone(context);
    final Widget trailing;
    if (open && phone) {
      trailing = PopupMenuButton<String>(
        tooltip: 'Offer actions',
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          if (action == 'publish') _publishOffer(offer);
          if (action == 'cancel') _cancelOffer(offer);
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'publish', child: Text('Publish')),
          PopupMenuItem(value: 'cancel', child: Text('Cancel offer')),
        ],
      );
    } else if (open) {
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SecondaryButton(
            label: 'Publish',
            icon: Icons.publish_outlined,
            dense: true,
            onPressed: () => _publishOffer(offer),
          ),
          const SizedBox(width: AppSpacing.xs),
          GhostButton(
            label: 'Cancel',
            icon: Icons.close,
            onPressed: _cancelling ? null : () => _cancelOffer(offer),
          ),
        ],
      );
    } else {
      trailing = StatusBadge(label: _sentence(offer.status));
    }
    return _SwapRow(
      semanticLabel:
          '${offer.offers.displayAmount} ${offer.offers.ticker} to '
          '${offer.wants.displayAmount} ${offer.wants.ticker}',
      leading: _PairedLogos(
        first: offer.offers.ticker,
        second: offer.wants.ticker,
      ),
      title:
          '${offer.offers.displayAmount} ${swapLegName(offer.offers)} → '
          '${offer.wants.displayAmount} ${swapLegName(offer.wants)}',
      subtitle: '${offer.offerId} · ${offer.status}',
      trailing: trailing,
    );
  }

  static String _sentence(String text) => text.isEmpty
      ? text
      : '${text[0].toUpperCase()}${text.substring(1).replaceAll('_', ' ')}';

  Future<void> _showMarketDetails(MarketOffer offer) async {
    final gives = offer.makerGives;
    final wants = offer.makerWants;
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => AppDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                'Receive ${gives.ticker} · Pay ${wants.ticker}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            StatusBadge(
              label: _venue(offer),
              variant: offer.demo ? BadgeVariant.warning : BadgeVariant.neutral,
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _routeSummary(offer),
                const SizedBox(height: AppSpacing.lg),
                if (offer.demo) ...[
                  const WarningBanner(
                    title: 'Experience preview only',
                    message:
                        'This route does not create an HTLC, request a signature, '
                        'broadcast a transaction, or move funds. Mainnet remains disabled.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _demoTimeline(),
                ] else if (offer.isAtomic) ...[
                  const WarningBanner(
                    title: 'Real two-chain settlement',
                    message:
                        'Joining reserves the offer. The maker funds first, then '
                        'you fund the second HTLC. Claims reveal one shared '
                        'preimage; each side can refund after its timeout.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const InfoBanner(
                    title: 'Privacy tradeoff',
                    message:
                        'The Liquid HTLC output is explicit, so its asset and '
                        'amount are public. Keys stay in the wallet and mainnet is blocked.',
                  ),
                ] else ...[
                  // `verified` is the engine's own offline check of the
                  // maker's signature, so the word is the engine's to say.
                  InfoBanner(
                    title: offer.verified
                        ? 'Proposal verified locally'
                        : 'Proposal unavailable',
                    message: offer.takeable
                        ? 'The signed maker commitment passed offline verification. '
                              'The take flow performs chain verification before signing.'
                        : (offer.blockReason ?? 'This offer cannot be taken.'),
                  ),
                  if (offer.proposalJson.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    GhostButton(
                      label: 'Copy proposal',
                      icon: Icons.copy_outlined,
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: offer.proposalJson),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Proposal copied')),
                        );
                      },
                    ),
                  ],
                ],
                if (offer.note.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    offer.note,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppScheme.of(context).inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          GhostButton(
            label: 'Close',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          if (offer.demo && _adminUri != null)
            SecondaryButton(
              label: 'Open admin',
              icon: Icons.tune_outlined,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _openAdmin();
              },
            )
          else if (offer.takeable)
            PrimaryButton(
              label: offer.isAtomic ? 'Reserve offer' : 'Review and take',
              icon: offer.isAtomic
                  ? Icons.lock_clock_outlined
                  : Icons.swap_horiz,
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (offer.isAtomic) {
                  _joinAtomic(offer);
                } else {
                  _takeProposal(offer.proposalJson);
                }
              },
            ),
        ],
      ),
    );
  }

  Widget _routeSummary(MarketOffer offer) {
    final s = AppScheme.of(context);
    Widget leg(MarketLeg value, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.eyebrow.copyWith(color: s.inkFaint)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              AssetLogo(ticker: value.ticker, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${value.displayAmount} ${marketLegName(value)}',
                      style: AppTypography.numeric.copyWith(color: s.ink),
                    ),
                    Text(
                      [
                        if (value.name.isNotEmpty && value.name != value.ticker)
                          value.name,
                        networkWords(value.network),
                      ].join(' · '),
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return DataWell(
      child: Row(
        children: [
          leg(offer.makerGives, 'You receive · maker gives'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Icon(
              Icons.arrow_forward,
              size: AppSpacing.icon,
              color: s.inkFaint,
            ),
          ),
          leg(offer.makerWants, 'You pay · maker wants'),
        ],
      ),
    );
  }

  /// What a demo route would do, as neutral steps: the first one (the quote
  /// is published) is a fact, the rest are future work.
  Widget _demoTimeline() {
    final s = AppScheme.of(context);
    const steps = [
      ('Quote published', 'Available in the local demo order book'),
      ('Bitcoin funding', 'Future audited HTLC transaction'),
      ('Liquid funding', 'Future audited confidential HTLC transaction'),
      ('Secret redeem', 'Future atomic settlement or timeout refund'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settlement preview',
          style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
        ),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < steps.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Centred on the first line of the label (20 tall).
                SizedBox(
                  height: 20,
                  child: Center(
                    child: StatusDot(index == 0 ? s.success : s.edgeStrong),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[index].$1,
                        style: AppTypography.label.copyWith(
                          color: index == 0 ? s.ink : s.inkSecondary,
                        ),
                      ),
                      Text(
                        steps[index].$2,
                        style: AppTypography.caption.copyWith(
                          color: s.inkFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Two assets of a pair: 24 px glyphs overlapping by 8, the second ringed in
/// the card colour so the overlap reads as two coins, not one blot.
class _PairedLogos extends StatelessWidget {
  const _PairedLogos({required this.first, required this.second});

  final String first;
  final String second;

  static const double _size = 24;
  static const double _ring = 2;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return SizedBox(
      width: _size * 2 - AppSpacing.sm + _ring,
      height: _size + _ring * 2,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: _ring,
            child: AssetLogo(ticker: first, size: _size),
          ),
          Positioned(
            left: _size - AppSpacing.sm - _ring,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(_ring),
              decoration: BoxDecoration(
                color: s.panel,
                borderRadius: BorderRadius.circular(999),
              ),
              child: AssetLogo(ticker: second, size: _size),
            ),
          ),
        ],
      ),
    );
  }
}

/// A market or swap row: the pair, a title over a tabular subtitle, and the
/// venue / status / actions on the right. 60 tall (64 on a phone).
class _SwapRow extends StatefulWidget {
  const _SwapRow({
    required this.semanticLabel,
    required this.leading,
    required this.title,
    required this.subtitle,
    this.titleInk,
    this.trailing,
    this.onTap,
    this.chevron = false,
  });

  final String semanticLabel;
  final Widget leading;
  final String title;
  final String subtitle;
  final Color? titleInk;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  @override
  State<_SwapRow> createState() => _SwapRowState();
}

class _SwapRowState extends State<_SwapRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final onTap = widget.onTap;
    final trailing = widget.trailing;

    final content = Row(
      children: [
        widget.leading,
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyOf(context).copyWith(
                  color: widget.titleInk ?? s.ink,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                widget.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.numericSmall.copyWith(
                  color: s.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing,
        ],
        if (widget.chevron) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_outlined,
            size: AppSpacing.icon,
            color: s.inkFaint,
          ),
        ],
      ],
    );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: onTap == null
          ? Colors.transparent
          : _down
          ? s.pressed
          : _hover
          ? s.hover
          : Colors.transparent,
      foregroundDecoration: _focus && onTap != null
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: BoxConstraints(minHeight: phone ? 64 : 60),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      child: content,
    );

    if (onTap == null) {
      return Semantics(label: widget.semanticLabel, child: body);
    }
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() {
          _hover = v;
          if (!v) _down = false;
        }),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: body,
        ),
      ),
    );
  }
}

/// Cross-chain (BTC ↔ Liquid HTLC) swaps exist only on Liquid testnet.
bool crossChainAvailable(AppState st) =>
    !st.isLiquidRegtest && !st.isBitcoinRegtest;

/// A LiquiDEX leg as shown: its ticker, with the short asset id beside a
/// name the wallet did not give (`TMPL · 80d249a8`).
String swapLegName(SwapLeg leg) =>
    leg.showsIdBeside ? '${leg.ticker} · ${leg.shortId}' : leg.ticker;

String marketLegName(MarketLeg leg) =>
    leg.showsIdBeside ? '${leg.ticker} · ${leg.shortId}' : leg.ticker;

/// `liquid-regtest` → `Liquid regtest`.
String networkWords(String network) {
  final parts = network.split('-');
  if (parts.length != 2) return network;
  final chain = parts[0] == 'bitcoin' ? 'Bitcoin' : 'Liquid';
  return '$chain ${parts[1]}';
}

/// What a cross-chain record that is not live means, for people.
String atomicAvailabilityText(String availability) => switch (availability) {
  'other_book' => 'kept for another order book; not followed here',
  'not_on_this_book' => 'this order book no longer knows it',
  'book_mismatch' => 'the order book\'s copy does not match the agreed terms',
  'book_unreachable' => 'the order book did not answer; it may still be live',
  _ => 'live',
};

String atomicAvailabilityBadge(String availability) => switch (availability) {
  'other_book' => 'Other book',
  'not_on_this_book' => 'Not on this book',
  'book_mismatch' => 'Mismatch',
  'book_unreachable' => 'Unreachable',
  _ => 'Live',
};

/// A failure of an order-book read, in words: never the raw
/// `Order book HTTP 404: …` string as the content of a section.
String plainBookError(Object error, {required String what}) {
  final raw = swapError(error);
  final http = RegExp(r'HTTP (\d{3})').firstMatch(raw)?.group(1);
  if (http != null) {
    return '$what: the order book answered with an error ($http). Refresh '
        'to try again';
  }
  final lower = raw.toLowerCase();
  if (lower.contains('connect') ||
      lower.contains('timed out') ||
      lower.contains('unreachable')) {
    return '$what: the order book did not answer. Refresh to try again';
  }
  return '$what: $raw';
}
