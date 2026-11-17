import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../features/dashboard/models/balance_history.dart';
import '../../features/dashboard/models/dashboard_data.dart';
import '../../services/asset_registry_service.dart';
import '../../services/issued_asset_store.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/asset_card.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'asset_detail_dialog.dart';
import 'liquid_issued.dart';
import 'liquid_overview.dart';

// ── Screen ───────────────────────────────────────────────────────────────────
//
// Liquid's own dashboard. At the top, the L-BTC balance and its chart — in
// Liquid's hue — with the split of the Liquid assets beside it; under it two
// blocks: the assets this wallet holds, and "Issued assets", which carries
// the three asset operations (issue, reissue, burn) over the list of what
// this wallet issued. Tapping an asset opens its detail in the same dialog a
// transaction's detail uses. Nothing on this page is filled with the accent:
// there is no single thing the page exists to do.

class LiquidScreen extends StatefulWidget {
  const LiquidScreen({super.key});

  @override
  State<LiquidScreen> createState() => _LiquidScreenState();
}

class _LiquidScreenState extends State<LiquidScreen> {
  final _bridge = walletBridge;

  List<AssetBalance> _liquidAssets = [];
  Map<String, IssuedAssetEntry> _issuedAssets = {};
  List<String> _hiddenAssets = [];
  bool _showHidden = false;
  bool _loading = true;
  String? _error;
  BalanceHistory? _history;
  bool _historyFailed = false;
  int _lastSyncVersion = 0;
  String? _lastWalletId;
  AppState? _appState;

  @override
  void initState() {
    super.initState();
    _load();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _appState = context.read<AppState>();
        _lastSyncVersion = _appState!.syncVersion;
        _lastWalletId = _appState!.activeWalletId;
        _appState!.addListener(_onAppStateChanged);
      }
    });
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    final newVersion = _appState?.syncVersion ?? 0;
    final newWalletId = _appState?.activeWalletId;
    if ((newVersion != _lastSyncVersion || newWalletId != _lastWalletId) &&
        mounted) {
      _lastSyncVersion = newVersion;
      _lastWalletId = newWalletId;
      setState(() => _loading = true);
      _load();
      _loadHistory();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (context.read<AppState>().syncState == SyncState.syncing) return;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    try {
      final data = await _bridge.getWalletSummary(walletId);
      // All Liquid assets: everything except native BTC
      final liquidAssets = data.assets.where((a) => a.ticker != 'BTC').toList();

      // Load local issued-asset store (scoped per wallet) + hidden list.
      final issued = await IssuedAssetStore.instance.getIssuedAssets(walletId);
      final hidden = await IssuedAssetStore.instance.getHiddenAssets();

      if (mounted) {
        setState(() {
          _liquidAssets = liquidAssets;
          _issuedAssets = issued;
          _hiddenAssets = hidden;
          _loading = false;
          _error = null;
        });
      }

      // Fetch Blockstream metadata in the background — doesn't block the screen.
      // Cache is never cleared so this only fetches IDs not already known.
      final ids = liquidAssets
          .where((a) => a.ticker != 'LBTC')
          .map((a) => a.assetId)
          .toList();
      // Blockstream's registry is Liquid testnet's: never ask it about a
      // regtest's asset ids (the engine names those from the lab's book).
      if (ids.isNotEmpty &&
          mounted &&
          !context.read<AppState>().isLiquidRegtest) {
        AssetRegistryService.instance.prefetchAll(ids).then((_) {
          if (mounted) setState(() {}); // Re-render once metadata arrives
        });
      }
    } catch (e) {
      // A failed load is NOT "no assets" — keep the error so the balances
      // section shows a retry card instead of a lying empty state.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  /// The chart's history loads on its own: a slow or failing call never
  /// holds up the assets.
  Future<void> _loadHistory() async {
    if (!mounted) return;
    if (context.read<AppState>().syncState == SyncState.syncing) return;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    try {
      final history = await _bridge.getBalanceHistory(walletId);
      if (mounted) {
        setState(() {
          _history = history;
          _historyFailed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  Future<void> _hideAsset(String assetId) async {
    await IssuedAssetStore.instance.hideAsset(assetId);
    final hidden = await IssuedAssetStore.instance.getHiddenAssets();
    if (mounted) setState(() => _hiddenAssets = hidden);
  }

  Future<void> _unhideAsset(String assetId) async {
    await IssuedAssetStore.instance.unhideAsset(assetId);
    final hidden = await IssuedAssetStore.instance.getHiddenAssets();
    if (mounted) setState(() => _hiddenAssets = hidden);
  }

  void _showDetail(AssetGroup group) {
    final id = group.main.assetId;
    final hidden = _hiddenAssets.contains(id);
    showAssetDetailDialog(
      context,
      asset: group.main,
      reissuanceToken: group.reissuanceToken,
      issued: _issuedAssets[id],
      // An orphan reissuance token (its asset not held) is still a token.
      isReissuanceToken: _issuedAssets.values.any((e) => e.tokenId == id),
      isHidden: hidden,
      onToggleHidden: () => hidden ? _unhideAsset(id) : _hideAsset(id),
    );
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final groups = groupAssets(_liquidAssets, _issuedAssets);
    final visible = _showHidden
        ? groups
        : groups.where((g) => !_hiddenAssets.contains(g.main.assetId)).toList();
    final hiddenCount = _hiddenAssets
        .where((id) => groups.any((g) => g.main.assetId == id))
        .length;
    final lbtc = _liquidAssets.where((a) => a.ticker == 'LBTC').firstOrNull;
    final tokenIds = {
      for (final e in _issuedAssets.values)
        if (e.tokenId != null) e.tokenId!,
    };

    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: ListenableBuilder(
              // L-BTC's fiat follows the price as it arrives or changes
              // currency.
              listenable: PriceService.instance,
              builder: (context, _) => ListView(
                padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
                children: [
                  const PageHeader(
                    title: 'Liquid assets',
                    actions: [PrivacyToggle()],
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _LoadError(message: _error!, onRetry: _retry)
                  else ...[
                    LiquidOverview(
                      lbtcSats: lbtc?.amount ?? 0,
                      history: _history,
                      historyFailed: _historyFailed,
                      shares: [
                        // L-BTC first: the chain's own coin leads the split.
                        for (final g in visible)
                          if (g.main.ticker == 'LBTC') _share(g),
                        for (final g in visible)
                          if (g.main.ticker != 'LBTC' &&
                              !tokenIds.contains(g.main.assetId))
                            _share(g),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    const ListSectionLabel(label: 'Assets'),
                    _assetList(context, visible, hiddenCount),
                    const SizedBox(height: AppSpacing.xxl),
                    const ListSectionLabel(label: 'Issued assets'),
                    IssuedAssetsCard(
                      issued: _issuedAssets.values.toList(),
                      holdings: _liquidAssets,
                      onOpen: (entry, asset, token) => showAssetDetailDialog(
                        context,
                        asset: asset,
                        reissuanceToken: token,
                        issued: entry,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const _ConfidentialNote(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  LiquidShare _share(AssetGroup g) {
    final a = g.main;
    final entry = _issuedAssets[a.assetId];
    final name = a.ticker == 'LBTC'
        ? 'Liquid Bitcoin'
        : liquidAssetName(a, issued: entry);
    final ticker = liquidAssetTicker(a, issued: entry);
    final (figure, unit) = splitAmountUnit(a.displayAmount);
    return LiquidShare(
      asset: a,
      name: name,
      amount: unit == null ? '$figure $ticker' : a.displayAmount,
    );
  }

  /// One card of rows — the Dashboard's assets group, so the same asset is
  /// drawn in one material wherever it appears.
  ///
  /// The show-hidden toggle rides at the foot of the card: it stays reachable
  /// when every asset is hidden (the list is then empty) and gets a whole row
  /// to be pressed on.
  Widget _assetList(
    BuildContext context,
    List<AssetGroup> visible,
    int hiddenCount,
  ) {
    final s = AppScheme.of(context);
    final masked = balancesHidden(context);
    return ListCard(
      children: [
        if (visible.isEmpty)
          const _EmptyAssets()
        else
          for (final g in visible)
            _AssetRow(
              group: g,
              issued: _issuedAssets[g.main.assetId],
              hidden: _hiddenAssets.contains(g.main.assetId),
              masked: masked,
              onTap: () => _showDetail(g),
            ),
        if (hiddenCount > 0)
          ListRow(
            // The eye shows the current state, never the action — the same
            // rule the PrivacyToggle follows (privacy.dart).
            icon: _showHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            tint: s.inkFaint,
            title: _showHidden ? 'Hide hidden assets' : 'Show hidden assets',
            subtitle: '$hiddenCount hidden',
            onTap: () => setState(() => _showHidden = !_showHidden),
          ),
      ],
    );
  }
}

/// Confidentiality is a property of every asset on the page, so it is
/// stated once, quietly, at its foot.
class _ConfidentialNote extends StatelessWidget {
  const _ConfidentialNote();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            Icons.visibility_off_outlined,
            size: AppSpacing.iconSmall,
            color: s.inkFaint,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Liquid uses confidential transactions: amounts and asset types '
            'are blinded on-chain and visible only to this wallet',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        ),
      ],
    );
  }
}

// ── Asset row ─────────────────────────────────────────────────────────────────

/// One asset: its glyph, its name over its ticker and issuer, and on the
/// right the balance over its fiat value (only when the asset has a price)
/// and its coin count. 64 tall.
class _AssetRow extends StatefulWidget {
  const _AssetRow({
    required this.group,
    required this.issued,
    required this.hidden,
    required this.masked,
    required this.onTap,
  });

  final AssetGroup group;
  final IssuedAssetEntry? issued;
  final bool hidden;
  final bool masked;
  final VoidCallback onTap;

  @override
  State<_AssetRow> createState() => _AssetRowState();
}

class _AssetRowState extends State<_AssetRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  static const double _height = 64;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final reg = AssetRegistryService.instance;
    final asset = widget.group.main;
    final info = reg.get(asset.assetId);
    final ticker = liquidAssetTicker(asset, issued: widget.issued);
    final name = asset.ticker == 'LBTC'
        ? 'Liquid Bitcoin'
        : liquidAssetName(asset, issued: widget.issued);
    final domain = info?.domain;
    // The reissuance token is not a property of the holding: it has its own
    // line under "Issued assets". Here the row only says where it came from.
    final meta = <String>[
      ticker,
      if (domain != null && domain.isNotEmpty) domain,
      // A phone row has half the width: the shorter words read whole.
      if (widget.issued != null)
        phone ? 'issued here' : 'issued by this wallet',
      if (widget.hidden) 'hidden',
    ].join(' · ');
    final (figure, unit) = splitAmountUnit(asset.displayAmount);
    // Only L-BTC has a price. An issued token shows nothing rather than a
    // made-up €0.00.
    final fiat = asset.ticker == 'LBTC' && !widget.masked
        ? PriceService.instance.fiatDisplay(asset.amount)
        : null;
    final coins = '${asset.utxoCount} UTXO${asset.utxoCount == 1 ? '' : 's'}';
    final nameInk = widget.hidden ? s.inkSecondary : s.ink;

    final amount = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                widget.masked ? kMaskedAmount : figure,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.numeric.copyWith(color: nameInk),
              ),
            ),
            if (!widget.masked) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                unit ?? ticker,
                maxLines: 1,
                style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
              ),
            ],
          ],
        ),
        // Desktop gives the coin count its own column, so the line under
        // the amount is the fiat value or nothing; a phone has room for one
        // line and prefers the fiat value.
        if (fiat != null || phone)
          Text(
            fiat ?? coins,
            maxLines: 1,
            style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
          ),
      ],
    );

    final content = Row(
      children: [
        AssetLogo(ticker: asset.ticker, size: 32),
        const SizedBox(width: kListGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyOf(
                  context,
                ).copyWith(color: nameInk, fontWeight: FontWeight.w500),
              ),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: amount,
        ),
        if (!phone) ...[
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 64,
            child: Text(
              coins,
              textAlign: TextAlign.end,
              maxLines: 1,
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
          ),
        ],
        const SizedBox(width: AppSpacing.xs),
        Icon(
          Icons.chevron_right_outlined,
          size: AppSpacing.icon,
          color: s.inkFaint,
        ),
      ],
    );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: _down
          ? s.pressed
          : _hover
          ? s.hover
          : Colors.transparent,
      foregroundDecoration: _focus
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: const BoxConstraints(minHeight: _height),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      child: content,
    );

    return Semantics(
      button: true,
      child: MergeSemantics(
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
                widget.onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// No assets: one quiet line and the one way to get some.
class _EmptyAssets extends StatelessWidget {
  const _EmptyAssets();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Text(
            'No Liquid assets yet',
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Receive',
            icon: Icons.south_west_outlined,
            isFullWidth: phone,
            onPressed: () => context.go(AppRoutes.receive),
          ),
        ],
      ),
    );
  }
}

// ── Load failure ──────────────────────────────────────────────────────────────
// Replaces only the balances section; a failed load must not masquerade as
// "No Liquid assets".

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, size: AppSpacing.icon, color: s.danger),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Could not load Liquid assets',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: 'Retry',
            icon: Icons.refresh,
            onPressed: onRetry,
            isFullWidth: AppLayout.isPhone(context),
          ),
        ],
      ),
    );
  }
}
