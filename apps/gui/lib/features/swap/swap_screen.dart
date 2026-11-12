import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'make_offer_flow.dart';
import 'atomic_offer_flow.dart';
import 'models/swap_offer.dart';
import 'take_flow.dart';

enum _MarketFilter { all, crossChain, liquid }

/// Chain-aware local market. Liquid rows use LiquiDEX; Bitcoin testnet ↔
/// Liquid testnet rows use the recoverable HTLC v1 state machine.
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
  String? _mineError;
  _MarketFilter _filter = _MarketFilter.all;

  String? get _walletId => context.read<AppState>().activeWalletId;

  List<MarketOffer> get _visibleMarkets => _markets.where((offer) {
    return switch (_filter) {
      _MarketFilter.all => true,
      _MarketFilter.crossChain => offer.isCrossChain,
      _MarketFilter.liquid => !offer.isCrossChain,
    };
  }).toList();

  @override
  void initState() {
    super.initState();
    _refresh(feedback: false);
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
      _mineError = null;
    });
    try {
      final results = await Future.wait<Object>([
        _bridge.listMyOffers(walletId),
        _bridge.atomicSwapList(walletId),
      ]);
      if (!mounted) return;
      setState(() {
        _myOffers = results[0] as List<MyOffer>;
        _myAtomic = results[1] as List<AtomicSwap>;
        _loadingMine = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _mineError = swapError(error);
        _loadingMine = false;
      });
    }
  }

  Future<void> _refresh({bool silent = false, bool feedback = true}) async {
    await Future.wait([
      _loadMarkets(silent: silent),
      _loadMine(silent: silent),
    ]);
    if (!mounted || !feedback || _error != null || _mineError != null) return;
    setState(() => _justRefreshed = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _justRefreshed = false);
  }

  Future<void> _openAdmin() async {
    final opened = await launchUrl(
      Uri.parse('http://127.0.0.1:3210'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the local admin dashboard'),
        ),
      );
    }
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
    final type = await showAppDialog<String>(
      context,
      builder: (dialogContext) => AppDialog(
        title: const Text('Choose settlement'),
        content: const SizedBox(
          width: 430,
          child: Text(
            'Cross-chain uses recoverable HTLCs between Bitcoin testnet and '
            'Liquid testnet. LiquiDEX exchanges two Liquid assets in one transaction.',
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
        const SnackBar(content: Text('Offer reserved. Maker must fund first.')),
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
        SnackBar(content: Text('Swap $action transaction broadcast.')),
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
      ).showSnackBar(SnackBar(content: Text('Published as local order #$id')));
      _loadMarkets();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(swapError(error))));
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
        _mineError = swapError(error);
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
                padding: EdgeInsets.fromLTRB(
                  pad,
                  AppSpacing.lg,
                  pad,
                  AppSpacing.xxl,
                ),
                sliver: SliverList.list(
                  children: [
                    _marketHeader(),
                    const SizedBox(height: AppSpacing.md),
                    _orderBookExplainer(),
                    const SizedBox(height: AppSpacing.lg),
                    _filters(),
                    const SizedBox(height: AppSpacing.md),
                    _marketSection(),
                    const SizedBox(height: AppSpacing.xl),
                    _myOffersSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _marketHeader() {
    final s = AppScheme.of(context);
    final compact = AppLayout.isCompact(context);
    final network =
        context.watch<AppState>().liquidNetwork?.shortName ?? 'testnet';
    final openRoutes = _markets.where((offer) => offer.available).length;
    final (status, statusColor) = _loading
        ? ('Connecting', s.inkFaint)
        : _error != null
        ? ('Market offline', s.danger)
        : openRoutes == 0
        ? ('No open routes', s.inkFaint)
        : ('$openRoutes open route${openRoutes == 1 ? '' : 's'}', s.success);

    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _compactRouteMark(),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'LOCAL ROUTING · ${network.toUpperCase()}',
                style: AppTypography.navSection.copyWith(
                  color: s.inkFaint,
                  fontSize: 10,
                  letterSpacing: 1.25,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Local order book',
                style: AppTypography.sectionTitle.copyWith(
                  color: s.ink,
                  fontSize: compact ? 19 : 21,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final utilityActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _utilityAction(
          label: _justRefreshed ? 'Market updated' : 'Refresh market',
          icon: _justRefreshed ? Icons.check_rounded : Icons.refresh_rounded,
          iconColor: _justRefreshed ? s.success : null,
          onPressed: _loading ? null : () => _refresh(silent: true),
        ),
        const SizedBox(width: AppSpacing.xs),
        _utilityAction(
          label: 'Import proposal',
          icon: Icons.input_rounded,
          onPressed: _importProposal,
        ),
        const SizedBox(width: AppSpacing.xs),
        _utilityAction(
          label: 'How it works',
          icon: Icons.info_outline_rounded,
          onPressed: _showOrderBookGuide,
        ),
        const SizedBox(width: AppSpacing.xs),
        _utilityAction(
          label: 'Local admin',
          icon: Icons.tune_rounded,
          onPressed: _openAdmin,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: s.panel,
        border: Border.all(color: s.edge),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            identity,
            const SizedBox(height: AppSpacing.md),
            Divider(height: 1, color: s.edge),
            const SizedBox(height: AppSpacing.md),
            utilityActions,
            const SizedBox(height: AppSpacing.sm),
            PrimaryButton(
              label: 'New offer',
              icon: Icons.add_rounded,
              isFullWidth: true,
              onPressed: _makeOffer,
            ),
          ] else ...[
            Row(
              children: [
                Expanded(child: identity),
                utilityActions,
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  label: 'New offer',
                  icon: Icons.add_rounded,
                  onPressed: _makeOffer,
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: s.edge),
          const SizedBox(height: AppSpacing.sm),
          if (compact)
            Column(
              children: [
                _settlementFact(
                  color: AppColors.liquid,
                  text: 'Liquid swaps · live settlement',
                  expanded: true,
                ),
                const SizedBox(height: AppSpacing.xs),
                _settlementFact(
                  color: AppColors.bitcoin,
                  text: 'Bitcoin routes · live HTLC testnet',
                  expanded: true,
                ),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.lg,
              runSpacing: AppSpacing.xs,
              children: [
                _settlementFact(
                  color: AppColors.liquid,
                  text: 'Liquid swaps · live settlement',
                ),
                _settlementFact(
                  color: AppColors.bitcoin,
                  text: 'Bitcoin routes · live HTLC testnet',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _orderBookExplainer() {
    final s = AppScheme.of(context);
    final compact = AppLayout.isCompact(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Maker posts; taker completes',
          style: AppTypography.label.copyWith(color: s.ink),
        ),
        const SizedBox(height: 3),
        Text(
          'The local book stores signed public proposals, never keys or funds. '
          'A Liquid taker verifies the proposal, pays the requested asset and '
          'receives the offered asset in one atomic transaction.',
          style: AppTypography.caption.copyWith(
            color: s.inkSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: s.panelInset,
        border: Border.all(color: s.edge),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                copy,
                const SizedBox(height: AppSpacing.sm),
                GhostButton(
                  label: 'Two-wallet test',
                  icon: Icons.account_balance_wallet_outlined,
                  onPressed: _showOrderBookGuide,
                ),
              ],
            )
          : Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: s.liquid),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: copy),
                const SizedBox(width: AppSpacing.md),
                GhostButton(
                  label: 'Two-wallet test',
                  icon: Icons.account_balance_wallet_outlined,
                  onPressed: _showOrderBookGuide,
                ),
              ],
            ),
    );
  }

  Future<void> _showOrderBookGuide() async {
    await showAppDialog<void>(
      context,
      builder: (dialogContext) => AppDialog(
        title: const Text('How the local order book works'),
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
                  'Choose one funded Liquid coin, set the asset and amount wanted, then publish locally.',
                ),
                _guideStep(
                  2,
                  'Wallet B · verify',
                  'Use the same testnet or regtest network, refresh, and open the offer. “Receive” is what B gets; “Pay” is what B spends.',
                ),
                _guideStep(
                  3,
                  'Wallet B · take',
                  'Review the independently verified proposal, sign, and broadcast the completed atomic transaction.',
                ),
                _guideStep(
                  4,
                  'Wallet A · sync',
                  'Switch back or open the other wallet instance and sync to see the received asset and spent offer coin.',
                  last: true,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Both wallets need the asset they pay plus LBTC for fees. '
                  'BTC routes marked HTLC v1 use two funding transactions, a shared preimage and recoverable timeouts.',
                  style: AppTypography.caption,
                ),
              ],
            ),
          ),
        ),
        actions: [
          PrimaryButton(
            label: 'Got it',
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      ),
    );
  }

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
              color: s.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppTypography.label.copyWith(color: s.accent),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.label),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: AppTypography.caption.copyWith(
                    color: s.inkSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactRouteMark() {
    final s = AppScheme.of(context);
    return Semantics(
      label: 'Bitcoin and Liquid',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: s.panelInset,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AssetLogo(ticker: 'BTC', size: 30),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                Icons.swap_horiz_rounded,
                size: 16,
                color: s.inkFaint,
              ),
            ),
            const AssetLogo(ticker: 'LBTC', size: 30),
          ],
        ),
      ),
    );
  }

  Widget _utilityAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? iconColor,
  }) {
    final s = AppScheme.of(context);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: s.panelInset,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: SizedBox.square(
              dimension: AppLayout.minTouchTarget,
              child: Icon(
                icon,
                size: 18,
                color: onPressed == null
                    ? s.inkFaint
                    : (iconColor ?? s.inkSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settlementFact({
    required Color color,
    required String text,
    bool expanded = false,
  }) {
    final s = AppScheme.of(context);
    return Row(
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        if (expanded)
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption.copyWith(
                color: s.inkSecondary,
                fontSize: 11.5,
              ),
            ),
          )
        else
          Text(
            text,
            style: AppTypography.caption.copyWith(
              color: s.inkSecondary,
              fontSize: 11.5,
            ),
          ),
      ],
    );
  }

  Widget _filters() {
    final s = AppScheme.of(context);
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('All', _MarketFilter.all),
                const SizedBox(width: AppSpacing.sm),
                _filterChip('BTC routes', _MarketFilter.crossChain),
                const SizedBox(width: AppSpacing.sm),
                _filterChip('Liquid assets', _MarketFilter.liquid),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Tooltip(
          message: 'Show closed and cancelled offers',
          child: FilterChip(
            label: const Text('Closed', style: TextStyle(fontSize: 12)),
            selected: _includeUnavailable,
            onSelected: _loading
                ? null
                : (value) {
                    setState(() => _includeUnavailable = value);
                    _loadMarkets();
                  },
            selectedColor: s.accentSoft,
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, _MarketFilter value) {
    final s = AppScheme.of(context);
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: _filter == value,
      selectedColor: s.accentSoft,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _marketSection() {
    final markets = _visibleMarkets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListSectionLabel(
          label: _loading
              ? 'Markets'
              : '${markets.length} market${markets.length == 1 ? '' : 's'}',
          actionLabel: 'Local admin',
          onAction: _openAdmin,
        ),
        if (_loading)
          const DataWell(
            child: SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            ),
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
    return DataWell(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: s.inkFaint),
            const SizedBox(height: AppSpacing.sm),
            Text('Local market is offline', style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                SecondaryButton(
                  label: 'Retry',
                  icon: Icons.refresh_rounded,
                  onPressed: _loadMarkets,
                ),
                GhostButton(
                  label: 'Open admin',
                  icon: Icons.tune_rounded,
                  onPressed: _openAdmin,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyMarkets() {
    final s = AppScheme.of(context);
    return DataWell(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Icon(Icons.swap_horiz_rounded, size: 32, color: s.inkFaint),
            const SizedBox(height: AppSpacing.sm),
            Text('No matching markets', style: AppTypography.sectionTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Use the local admin dashboard to post controlled test quotes.',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _marketRow(MarketOffer offer) {
    final s = AppScheme.of(context);
    final gives = offer.makerGives;
    final wants = offer.makerWants;
    final unavailable = !offer.available;
    final statusColor = offer.demo
        ? AppColors.warning
        : offer.takeable
        ? AppColors.success
        : s.inkFaint;

    return Semantics(
      button: true,
      label:
          'Receive ${gives.displayAmount} ${gives.ticker}; pay '
          '${wants.displayAmount} ${wants.ticker}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showMarketDetails(offer),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPaddingSmall,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                _pairedLogos(gives.ticker, wants.ticker),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Receive ${gives.displayAmount} ${gives.ticker}',
                        style: AppTypography.bodySmall.copyWith(
                          color: unavailable ? s.inkFaint : s.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pay ${wants.displayAmount} ${wants.ticker}'
                        '${offer.priceDisplay.isEmpty ? '' : ' · ${offer.priceDisplay}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: s.inkSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    TagChip(
                      label: offer.demo
                          ? 'HTLC demo'
                          : offer.isAtomic
                          ? 'HTLC v1'
                          : 'LiquiDEX',
                      color: offer.demo
                          ? AppColors.warning
                          : offer.isAtomic
                          ? AppColors.bitcoin
                          : AppColors.liquid,
                    ),
                    if (unavailable) ...[
                      const SizedBox(height: 4),
                      Text(
                        offer.status.toUpperCase(),
                        style: AppTypography.navSection.copyWith(
                          color: statusColor,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.chevron_right_rounded, color: s.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pairedLogos(String first, String second) {
    return SizedBox(
      width: 48,
      height: 36,
      child: Stack(
        children: [
          AssetLogo(ticker: first, size: 32),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: AssetLogo(ticker: second, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _myOffersSection() {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListSectionLabel(label: 'My swaps'),
        if (_loadingMine)
          const DataWell(
            child: SizedBox(
              height: 72,
              child: Center(child: CircularProgressIndicator()),
            ),
          )
        else if (_mineError != null)
          DataWell(
            child: Text(
              _mineError!,
              style: AppTypography.caption.copyWith(color: AppColors.danger),
            ),
          )
        else if (_myOffers.isEmpty && _myAtomic.isEmpty)
          DataWell(
            child: Text(
              'Offers and active HTLC swaps created by this wallet will appear here.',
              style: AppTypography.bodySmall.copyWith(color: s.inkSecondary),
            ),
          )
        else
          ListCard(
            children: [
              for (final swap in _myAtomic) _atomicSwapRow(swap),
              for (final offer in _myOffers) _myOfferRow(offer),
            ],
          ),
      ],
    );
  }

  Widget _atomicSwapRow(AtomicSwap swap) {
    final s = AppScheme.of(context);
    final action = swap.canFund
        ? 'fund'
        : swap.canClaim
        ? 'claim'
        : swap.canRefund
        ? 'refund'
        : null;
    final gives = swap.role == 'maker' ? swap.offered : swap.wanted;
    final gets = swap.role == 'maker' ? swap.wanted : swap.offered;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPaddingSmall,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _pairedLogos(gives.ticker, gets.ticker),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${gives.displayAmount} ${gives.ticker} → ${gets.displayAmount} ${gets.ticker}',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '#${swap.offerId} · ${swap.role} · ${swap.status.replaceAll('_', ' ')}',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ),
          ),
          if (action == null)
            StatusBadge(label: swap.status.replaceAll('_', ' ').toUpperCase())
          else
            PrimaryButton(
              label: action == 'fund'
                  ? 'Fund HTLC'
                  : action == 'claim'
                  ? 'Claim'
                  : 'Refund',
              icon: action == 'refund'
                  ? Icons.undo_rounded
                  : Icons.lock_open_rounded,
              onPressed: () => _atomicAction(swap, action),
            ),
        ],
      ),
    );
  }

  Widget _myOfferRow(MyOffer offer) {
    final s = AppScheme.of(context);
    final open = offer.status == 'open';
    final compact = AppLayout.isCompact(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPaddingSmall,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          _pairedLogos(offer.offers.ticker, offer.wants.ticker),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${offer.offers.displayAmount} ${offer.offers.ticker} → '
                  '${offer.wants.displayAmount} ${offer.wants.ticker}',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${offer.offerId} · ${offer.status}',
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
            ),
          ),
          if (open && compact)
            PopupMenuButton<String>(
              tooltip: 'Offer actions',
              onSelected: (action) {
                if (action == 'publish') _publishOffer(offer);
                if (action == 'cancel') _cancelOffer(offer);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'publish', child: Text('Publish locally')),
                PopupMenuItem(value: 'cancel', child: Text('Cancel offer')),
              ],
            )
          else if (open) ...[
            GhostButton(
              label: 'Publish',
              icon: Icons.publish_rounded,
              onPressed: () => _publishOffer(offer),
            ),
            const SizedBox(width: AppSpacing.xs),
            GhostButton(
              label: 'Cancel',
              icon: Icons.close_rounded,
              onPressed: _cancelling ? null : () => _cancelOffer(offer),
            ),
          ] else
            StatusBadge(label: offer.status.toUpperCase()),
        ],
      ),
    );
  }

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
            StatusBadge(
              label: offer.demo
                  ? 'HTLC DEMO'
                  : offer.isAtomic
                  ? 'HTLC V1'
                  : 'LIQUIDEX',
              variant: offer.demo ? BadgeVariant.warning : BadgeVariant.success,
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
                      icon: Icons.copy_rounded,
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
                  Text(offer.note, style: AppTypography.bodySmall),
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
          if (offer.demo)
            SecondaryButton(
              label: 'Open admin',
              icon: Icons.tune_rounded,
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
                  : Icons.swap_horiz_rounded,
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
          Text(
            label.toUpperCase(),
            style: AppTypography.navSection.copyWith(color: s.inkFaint),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              AssetLogo(ticker: value.ticker, size: 34),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${value.displayAmount} ${value.ticker}',
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      value.network,
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
            child: Icon(Icons.arrow_forward_rounded, color: s.inkFaint),
          ),
          leg(offer.makerWants, 'You pay · maker wants'),
        ],
      ),
    );
  }

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
        Text('SETTLEMENT PREVIEW', style: AppTypography.navSection),
        const SizedBox(height: AppSpacing.md),
        for (var index = 0; index < steps.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == 0 ? s.accentSoft : s.panelInset,
                    border: Border.all(
                      color: index == 0 ? s.accent : s.edgeStrong,
                    ),
                  ),
                  child: index == 0
                      ? Icon(Icons.check_rounded, size: 14, color: s.accent)
                      : Text(
                          '${index + 1}',
                          style: AppTypography.label.copyWith(
                            color: s.inkFaint,
                          ),
                        ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(steps[index].$1, style: AppTypography.label),
                      Text(
                        steps[index].$2,
                        style: AppTypography.caption.copyWith(
                          color: s.inkSecondary,
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
