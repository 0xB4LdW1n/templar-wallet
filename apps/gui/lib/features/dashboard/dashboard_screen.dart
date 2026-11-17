import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../test_coins/test_coins.dart';
import '../test_coins/test_coins_card.dart';
import '../../app/routes.dart';
import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../services/asset_registry_service.dart';
import '../../services/cosigner_label_store.dart';
import '../../services/fee_bump_store.dart';
import '../../services/issued_asset_store.dart';
import '../../services/price_history_service.dart';
import '../../services/price_service.dart';
import '../../shared/models/cosigner_label.dart';
import '../../shared/widgets/asset_card.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cosigner_label_editor.dart';
import '../../shared/widgets/cosigner_ring.dart';
import '../../shared/widgets/plain_card.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/privacy.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/value_chart.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../history/fee_bump_fold.dart';
import '../liquid/asset_detail_dialog.dart';
import '../wallet_info/models/wallet_info.dart';
import 'models/balance_history.dart';
import '../utxos/models/pending_consolidation.dart';
import '../../services/pending_consolidation_store.dart';
import 'models/dashboard_data.dart';

// The Dashboard — the app's first moment (design.md, "The moments").
//
// The balance and its chart are the one rich thing on the page; everything
// around them is quiet. Top to bottom: the wallet's name and identity, the
// hero (figure, its other denomination and its change, Send and Receive, the
// chart and its two controls), the keys of a shared wallet, then one card per
// chain with its lists inside it. Send is the screen's one filled accent
// control.

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _bridge = walletBridge;
  DashboardData? _data;
  WalletInfo? _walletInfo;
  BalanceHistory? _history;
  bool _historyFailed = false;
  List<String> _hiddenAssets = [];
  Map<String, IssuedAssetEntry> _issuedAssets = {};
  bool _showHidden = false;
  bool _loading = true;
  String? _error;

  /// A rebuild is in flight from the open-failure card.
  bool _repairing = false;
  int _lastSyncVersion = 0;
  AppState? _appState;

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    if (appState.cachedDashboard != null) {
      _data = appState.cachedDashboard;
      _loading = false;
    }
    _load();
    _loadHistory();
    // Refresh price on dashboard open
    PriceService.instance.fetch();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _appState = context.read<AppState>();
        _lastSyncVersion = _appState!.syncVersion;
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
    if (newVersion != _lastSyncVersion && mounted) {
      _lastSyncVersion = newVersion;
      _load();
      _loadHistory();
    }
  }

  /// Balance history feeds the hero chart only — it loads on its own so a slow
  /// or failing call never holds up the first paint of the dashboard.
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
      // The chart shows its own empty state; nothing else on Home depends on it.
      if (mounted) setState(() => _historyFailed = true);
    }
  }

  /// Prepends rows for consolidations the wallet engine has not caught up
  /// with. Dropped automatically once a sync returns the real transaction,
  /// since the txid is then already in the summary.
  Future<DashboardData> _withPendingConsolidations(
    String walletId,
    DashboardData data,
  ) async {
    final List<PendingConsolidation> pending;
    try {
      pending = await PendingConsolidationStore.instance.listAllFor(walletId);
    } catch (_) {
      return data;
    }
    if (pending.isEmpty) return data;
    final known = data.recentActivity.map((t) => t.txid).toSet();
    final extra =
        pending
            .where((p) => !known.contains(p.txid))
            .map(
              (p) => RecentActivityItem(
                txid: p.txid,
                direction: 'self',
                chain: p.chainKey,
                // Approximate: the real output is the inputs minus the fee.
                amount: '~${p.displayAmount}',
                ticker: p.ticker ?? 'BTC',
                timestamp: p.startedAt,
                confirmations: 0,
                note: p.activityNote,
              ),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (extra.isEmpty) return data;
    return data.withActivity([...extra, ...data.recentActivity]);
  }

  /// Drops the second transaction of a fee bump — a CPFP child, a replaced
  /// original — from the recent activity, as Activity folds it into the
  /// payment it belongs to: here it would read as a payment of its own.
  Future<DashboardData> _withoutBumpTwins(
    String walletId,
    DashboardData data,
  ) async {
    final List<FeeBumpRecord> records;
    try {
      records = await FeeBumpStore.instance.listFor(walletId);
    } catch (_) {
      return data;
    }
    final gone = feeBumpHiddenTxids({
      for (final t in data.recentActivity) t.txid: t.confirmations > 0,
    }, records);
    if (gone.isEmpty) return data;
    return data.withActivity([
      for (final t in data.recentActivity)
        if (!gone.contains(t.txid)) t,
    ]);
  }

  Future<void> _load() async {
    if (!mounted) return;
    if (context.read<AppState>().syncState == SyncState.syncing) return;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    // Never let a bridge failure strand the shimmer: an uncaught error here
    // would skip the setState below and leave Home permanently blank.
    DashboardData data;
    try {
      data = await _bridge.getWalletSummary(walletId);
    } catch (e) {
      if (mounted && _data == null) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
      return;
    }
    final liquidIds = data.assets
        .where((a) => a.ticker != 'BTC' && a.ticker != 'LBTC')
        .map((a) => a.assetId)
        .toList();
    if (liquidIds.isNotEmpty) {
      AssetRegistryService.instance.prefetchAll(liquidIds);
    }
    // A consolidation broadcast a minute ago is in no engine's history yet —
    // BDK picks it up on the next sync. Home would otherwise show the coins
    // gone from UTXOs and nothing at all here.
    data = await _withPendingConsolidations(walletId, data);
    data = await _withoutBumpTwins(walletId, data);
    final hidden = await IssuedAssetStore.instance.getHiddenAssets();
    final issued = await IssuedAssetStore.instance.getIssuedAssets(walletId);
    // Fingerprint + xpub for the header's identity line — non-fatal if
    // unavailable.
    WalletInfo? info;
    try {
      info = await _bridge.getWalletInfo(walletId);
    } catch (_) {}
    if (mounted) {
      context.read<AppState>().cachedDashboard = data;
      setState(() {
        _data = data;
        _walletInfo = info;
        _hiddenAssets = hidden;
        _issuedAssets = issued;
        _loading = false;
        _error = null;
      });
    }
  }

  void _reload() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  /// A multisig whose stored descriptor cannot be parsed is the one open
  /// failure the app can fix by itself: the cosigner keys are still in the
  /// registry, so the descriptor can be rebuilt from them. Every other
  /// failure here (a locked vault, a missing file) needs something else.
  bool get _canRepair {
    final state = context.read<AppState>();
    final multisig = (state.activeWalletType ?? '').toLowerCase().contains(
      'multisig',
    );
    final error = (_error ?? '').toLowerCase();
    // "Descriptor checksum mismatch" is BDK refusing a database that holds
    // another wallet's descriptor — the descriptor itself is fine, and a
    // rebuild would produce the same one.
    return multisig &&
        error.contains('descriptor') &&
        !error.contains('checksum');
  }

  Future<void> _repairWallet() async {
    final state = context.read<AppState>();
    final id = state.activeWalletId;
    if (id == null) return;
    setState(() => _repairing = true);
    try {
      await walletBridge.repairMultisigWallet(id);
      if (!mounted) return;
      setState(() => _repairing = false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _repairing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not repair: ${e.toString().replaceFirst('Exception: wallet-ffi: ', '')}',
          ),
          backgroundColor: AppScheme.of(context).danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBackground.flat(
        child: _loading
            ? const _DashboardSkeleton()
            : _data == null
            ? _DashboardError(
                message: _error ?? 'Could not load the wallet',
                onRetry: _reload,
                onRepair: _canRepair ? _repairWallet : null,
                repairing: _repairing,
              )
            : _DashboardContent(
                data: _data!,
                walletInfo: _walletInfo,
                history: _history,
                historyFailed: _historyFailed,
                hiddenAssets: _hiddenAssets,
                issuedAssets: _issuedAssets,
                showHidden: _showHidden,
                onToggleShowHidden: () =>
                    setState(() => _showHidden = !_showHidden),
              ),
      ),
    );
  }
}

// ── Page frame ────────────────────────────────────────────────────────────────

/// The page's gutter and its capped content column, shared by the content,
/// the skeleton and the error so the three line up exactly.
class _PageColumn extends StatelessWidget {
  const _PageColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

// ── Load failure ──────────────────────────────────────────────────────────────
// Shown only when the very first load fails (no cached data to fall back on),
// e.g. the wallet could not be opened. Offline is NOT such a case — opening and
// address derivation work without a network.

class _DashboardError extends StatelessWidget {
  const _DashboardError({
    required this.message,
    required this.onRetry,
    this.onRepair,
    this.repairing = false,
  });
  final String message;
  final VoidCallback onRetry;

  /// Offered only for the failure it actually fixes: a multisig whose stored
  /// descriptor does not parse. Null otherwise — a button that cannot help is
  /// worse than no button on a screen where nothing else works.
  final VoidCallback? onRepair;
  final bool repairing;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: PlainCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Could not open this wallet',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: s.inkSecondary,
                  ),
                ),
                if (onRepair != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'This wallet\'s descriptor was built from a key that could '
                    'not be used as it was written. The cosigner keys are still '
                    'here, so it can be rebuilt from them — same wallet, same '
                    'addresses, nothing to collect from your devices again.',
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    SecondaryButton(
                      label: 'Try again',
                      icon: Icons.refresh_outlined,
                      onPressed: onRetry,
                      isFullWidth: phone,
                    ),
                    if (onRepair != null)
                      SecondaryButton(
                        label: repairing
                            ? 'Repairing…'
                            : 'Rebuild from the keys',
                        icon: Icons.healing_outlined,
                        isLoading: repairing,
                        isFullWidth: phone,
                        onPressed: repairing ? null : onRepair,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

/// The page during the first load: the same blocks in the same places, their
/// figures replaced by placeholders, so nothing jumps when the data lands.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    if (AppLayout.isPhone(context)) {
      return _PageColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HeroPanel(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  const ShimmerBox(width: 96, height: 12),
                  const SizedBox(height: AppSpacing.lg),
                  const ShimmerBox(width: 200, height: 36),
                  const SizedBox(height: AppSpacing.sm),
                  const ShimmerBox(width: 240, height: 16),
                  const SizedBox(height: AppSpacing.lg),
                  const ShimmerBox(width: double.infinity, height: 160),
                  const SizedBox(height: AppSpacing.xxxl + AppSpacing.lg),
                  Row(
                    children: const [
                      Expanded(
                        child: ShimmerBox(
                          width: double.infinity,
                          height: AppSpacing.phoneControlHeight,
                          borderRadius: AppSpacing.radiusPhoneControl,
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: ShimmerBox(
                          width: double.infinity,
                          height: AppSpacing.phoneControlHeight,
                          borderRadius: AppSpacing.radiusPhoneControl,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ShimmerBox(width: 64, height: 12),
            const SizedBox(height: AppSpacing.md),
            _skeletonCard(3),
          ],
        ),
      );
    }

    return _PageColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ShimmerBox(width: 200, height: 32),
          const SizedBox(height: AppSpacing.sm),
          const ShimmerBox(width: 160, height: 16),
          const SizedBox(height: AppSpacing.xl),
          HeroPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: AppSpacing.sm),
                          ShimmerBox(width: 96, height: 12),
                          SizedBox(height: AppSpacing.md),
                          ShimmerBox(width: 280, height: 44),
                          SizedBox(height: AppSpacing.sm),
                          ShimmerBox(width: 320, height: 16),
                        ],
                      ),
                    ),
                    ShimmerBox(width: 88, height: AppSpacing.controlHeight),
                    SizedBox(width: AppSpacing.sm),
                    ShimmerBox(width: 108, height: AppSpacing.controlHeight),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShimmerBox(width: 180, height: 32),
                    SizedBox(width: AppSpacing.md),
                    ShimmerBox(width: 280, height: 32),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                const ShimmerBox(width: double.infinity, height: 280),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _skeletonCard(3)),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: _skeletonCard(3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _skeletonCard(int rows) => PlainCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            ShimmerBox(width: 24, height: 24, borderRadius: 999),
            SizedBox(width: AppSpacing.md),
            ShimmerBox(width: 96, height: 16),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        const ShimmerBox(width: 200, height: 28),
        for (var i = 0; i < rows; i++) ...[
          const SizedBox(height: AppSpacing.lg),
          const Row(
            children: [
              ShimmerBox(width: kListTile, height: kListTile),
              SizedBox(width: AppSpacing.md),
              Expanded(child: ShimmerBox(width: double.infinity, height: 16)),
            ],
          ),
        ],
      ],
    ),
  );
}

// ── Content ───────────────────────────────────────────────────────────────────

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({
    required this.data,
    required this.walletInfo,
    required this.history,
    required this.historyFailed,
    required this.hiddenAssets,
    required this.issuedAssets,
    required this.showHidden,
    required this.onToggleShowHidden,
  });
  final DashboardData data;
  final WalletInfo? walletInfo;
  final BalanceHistory? history;
  final bool historyFailed;
  final List<String> hiddenAssets;
  final Map<String, IssuedAssetEntry> issuedAssets;
  final bool showHidden;
  final VoidCallback onToggleShowHidden;

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    return _PageColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The mobile shell's own header already names the wallet directly
          // above; a phone opens on the balance.
          if (!phone)
            Reveal(
              child: _WalletHeader(name: data.walletName, info: walletInfo),
            ),
          Reveal(
            delay: 1,
            child: _Hero(
              data: data,
              history: history,
              historyFailed: historyFailed,
            ),
          ),
          // Joined to a test server with a faucet: the coins it pays, one
          // action each, where the balance they land in is.
          if (context.select<AppState, bool>(
            (st) => testCoinsFor(st).isNotEmpty,
          )) ...[
            const SizedBox(height: AppSpacing.xl),
            const Reveal(delay: 2, child: TestCoinsCard()),
          ],
          // A shared wallet's keys, on the screen people actually open.
          if ((walletInfo?.cosignerKeys.length ?? 0) > 1) ...[
            const SizedBox(height: AppSpacing.xl),
            Reveal(delay: 2, child: _CosignerCard(info: walletInfo!)),
          ],
          if (phone) ...[
            // One assets list and one activity list, both chains folded in:
            // a row already says which asset it is by its glyph and name.
            const SizedBox(height: AppSpacing.xl),
            Reveal(
              delay: 2,
              child: _PhoneAssets(
                data: data,
                issuedAssets: issuedAssets,
                hiddenAssets: hiddenAssets,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Reveal(delay: 3, child: _PhoneActivity(data: data)),
          ] else ...[
            const SizedBox(height: AppSpacing.xl),
            Reveal(
              delay: 2,
              child: _ChainSections(
                data: data,
                issuedAssets: issuedAssets,
                hiddenAssets: hiddenAssets,
                showHidden: showHidden,
                onToggleShowHidden: onToggleShowHidden,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Header (desktop) ──────────────────────────────────────────────────────────
// The wallet's name as the page title, and under it the one line of identity:
// what kind of wallet, and the master fingerprint that tells it apart from
// every other wallet built on another seed. The network sits on the right.
//
// Same metrics as `PageHeader`, which takes its meta as a plain string; this
// line carries a mono fingerprint and a copy button.

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.name, required this.info});

  final String name;
  final WalletInfo? info;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final type = context.select<AppState, String?>((st) => st.activeWalletType);
    final fp = info?.masterFingerprint ?? '';
    // A hardware wallet's label already carries its fingerprint.
    final typeLabel = type == null || type.isEmpty
        ? null
        : (fp.isNotEmpty && type.contains(fp)
              ? type.replaceAll(' ($fp)', '')
              : type);
    final hasMeta = typeLabel != null || fp.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.pageTitle.copyWith(color: s.ink),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              TestnetBadge(label: networkBadgeLabel(context)),
            ],
          ),
          if (hasMeta)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Row(
                children: [
                  if (typeLabel != null)
                    Text(
                      typeLabel,
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  if (typeLabel != null && fp.isNotEmpty)
                    Text(
                      '  ·  ',
                      style: AppTypography.caption.copyWith(color: s.inkFaint),
                    ),
                  if (fp.isNotEmpty) ...[
                    Text(
                      fp,
                      style: AppTypography.monoSmall.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _CopyKeyButton(info: info!),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Copies the wallet's xpub — the fingerprint alone is not enough to
/// reconstruct it — or the fingerprint when there is no single xpub
/// (multisig). The glyph turns into a check for a moment.
class _CopyKeyButton extends StatefulWidget {
  const _CopyKeyButton({required this.info});
  final WalletInfo info;

  @override
  State<_CopyKeyButton> createState() => _CopyKeyButtonState();
}

class _CopyKeyButtonState extends State<_CopyKeyButton> {
  bool _copied = false;
  Timer? _reset;

  bool get _hasXpub => widget.info.xpub.isNotEmpty;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final text = _hasXpub ? widget.info.xpub : widget.info.masterFingerprint;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final what = _hasXpub ? 'xpub' : 'fingerprint';
    return IconButton(
      tooltip: _copied ? 'Copied' : 'Copy $what',
      onPressed: _copy,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(
        width: AppSpacing.xl,
        height: AppSpacing.xl,
      ),
      iconSize: AppSpacing.iconSmall,
      color: s.inkSecondary,
      icon: AnimatedSwitcher(
        duration: AppMotion.of(context, AppMotion.quick),
        switchInCurve: AppMotion.settle,
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: Icon(
          _copied ? Icons.check_outlined : Icons.content_copy_outlined,
          key: ValueKey(_copied),
        ),
      ),
    );
  }
}

// ── Keys ────────────────────────────────────────────────────────────────────
// Who can sign for this wallet, in the place people look first. It is the
// roster, not a count of signatures on a transaction, so no seal here.

class _CosignerCard extends StatefulWidget {
  const _CosignerCard({required this.info});

  final WalletInfo info;

  @override
  State<_CosignerCard> createState() => _CosignerCardState();
}

class _CosignerCardState extends State<_CosignerCard> {
  Map<String, CosignerLabel> _labels = const {};

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  @override
  void didUpdateWidget(_CosignerCard old) {
    super.didUpdateWidget(old);
    if (old.info.id != widget.info.id) _loadLabels();
  }

  Future<void> _loadLabels() async {
    final labels = await CosignerLabelStore.instance.load(widget.info.id);
    if (mounted) setState(() => _labels = labels);
  }

  List<CosignerEntry> get _entries => resolveCosigners(
    cosignerKeys: widget.info.cosignerKeys,
    labels: _labels,
    localFingerprints: widget.info.localFingerprints,
  );

  Future<void> _openRoster([int? index]) async {
    await showCosignerRoster(
      context,
      entries: _entries,
      requiredSigs: widget.info.requiredSigs,
      initialIndex: index,
      onEdit: (entry) async {
        final edited = await showCosignerLabelEditor(
          context,
          label: entry.label,
          index: entry.index,
          subtitle: entry.fingerprint.isEmpty
              ? null
              : '${entry.fingerprint} · m/${entry.path}',
        );
        if (edited == null) return null;
        await CosignerLabelStore.instance.saveOne(widget.info.id, edited);
        await _loadLabels();
        // Hand the sheet the refreshed roster: it renders its own copy, and
        // the card behind it is not the thing the user is looking at.
        return _entries;
      },
    );
    // The roster edits labels in place, so the card behind it has to catch up
    // whether or not anything was changed.
    await _loadLabels();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final entries = _entries;
    final phone = AppLayout.isPhone(context);
    final shown = math.min(entries.length, maxRingIcons);
    final m = widget.info.requiredSigs;

    return PlainCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Keys',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
              ),
              GhostButton(
                label: entries.length > shown ? 'See all' : 'Details',
                onPressed: () => _openRoster(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CosignerRing(
                entries: entries,
                requiredSigs: m,
                size: phone ? 124 : 136,
                onTapEntry: (e) => _openRoster(e.index),
                onTapMore: () => _openRoster(),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m == null
                          ? '${entries.length} keys'
                          : 'Any $m of ${entries.length} keys can sign',
                      style: AppTypography.body.copyWith(color: s.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // The names, in order, so the ring's glyphs mean
                    // something without hovering every one of them.
                    for (final e in entries.take(maxRingIcons))
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Row(
                          children: [
                            Icon(
                              e.label.icon,
                              size: AppSpacing.iconSmall,
                              color: s.inkSecondary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                e.isLocal ? '${e.name} · this wallet' : e.name,
                                style: AppTypography.caption.copyWith(
                                  color: s.inkSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (entries.length > shown)
                      Text(
                        '+${entries.length - shown} more',
                        style: AppTypography.caption.copyWith(
                          color: s.inkFaint,
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
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────
// The figure, its other denomination and its change, the two verbs, and the
// chart. The figure is the whole-portfolio value of the native coins (BTC +
// LBTC); tokens without a price feed are listed below but not valued here.
//
// Tapping the figure swaps fiat for coin, and the chart follows: one unit for
// the whole hero, one way to change it. Fiat is an estimate from a third-party
// feed and the coin balance is the fact, so getting to the fact never costs
// more than one tap. The choice is per-visit state, not a preference — the
// settings toggle (BTC/sats) still decides *which* coin unit this shows.
//
// The chart is native-coin balance over time, valued in fiat (or shown as the
// raw coin balance). Everything is derived from two inputs: the wallet's
// balance history (a step function) and the BTC price series — neither of
// which is required for the hero to render.

enum _ChartRange {
  h24('24H', '1D', 'in 24 hours', Duration(hours: 24), 1),
  d7('7D', '1W', 'in 7 days', Duration(days: 7), 7),
  d30('30D', '1M', 'in 30 days', Duration(days: 30), 30),
  d90('90D', '3M', 'in 90 days', Duration(days: 90), 90),
  y1('1Y', '1Y', 'in 1 year', Duration(days: 365), 365),
  all('All', 'All', 'all time', null, 365);

  const _ChartRange(
    this.label,
    this.shortLabel,
    this.period,
    this.window,
    this.priceDays,
  );

  final String label;

  /// The phone's word for the range: six of them share one row there.
  final String shortLabel;

  /// What a change over this range is compared to: "+3.1% in 30 days".
  final String period;

  /// null = the whole history.
  final Duration? window;
  final int priceDays;
}

enum _ChainFilter { all, btc, liquid }

class _Hero extends StatefulWidget {
  const _Hero({
    required this.data,
    required this.history,
    required this.historyFailed,
  });
  final DashboardData data;
  final BalanceHistory? history;

  /// The history call failed — say so instead of loading forever.
  final bool historyFailed;

  @override
  State<_Hero> createState() => _HeroState();
}

class _HeroState extends State<_Hero> {
  /// The figure (and the chart) shows the coin balance instead of fiat.
  bool _coinFirst = false;

  _ChartRange _range = _ChartRange.d30;
  _ChainFilter _chain = _ChainFilter.all;

  List<PricePoint> _prices = const [];
  bool _pricesLoaded = false;
  bool _fetchingPrices = false;
  String _pricesKey = '';

  List<ChartPoint>? _series;
  String _seriesKey = '';
  Timer? _edgeTimer;

  /// The sample under the desktop pointer, read out in the controls row.
  ChartPoint? _hover;

  @override
  void initState() {
    super.initState();
    _syncEdgeTimer();
    _loadPrices();
    // The currency lives on PriceService; switching it invalidates the series.
    PriceService.instance.addListener(_onPriceServiceChanged);
  }

  @override
  void dispose() {
    _edgeTimer?.cancel();
    PriceService.instance.removeListener(_onPriceServiceChanged);
    super.dispose();
  }

  /// "Now" quantised so the memo key is stable between ticks. Short ranges
  /// advance by the minute; long ones by the hour, where a minute is invisible.
  DateTime _nowBucket() {
    final now = DateTime.now();
    final step =
        _range.window != null && _range.window! <= const Duration(days: 7)
        ? const Duration(minutes: 1)
        : const Duration(hours: 1);
    return DateTime.fromMillisecondsSinceEpoch(
      (now.millisecondsSinceEpoch ~/ step.inMilliseconds) * step.inMilliseconds,
    );
  }

  /// Keeps the right edge of a short-range chart current while Home stays open;
  /// longer ranges ride on the sync/price rebuilds already happening.
  void _syncEdgeTimer() {
    final live =
        _range.window != null && _range.window! <= const Duration(days: 7);
    if (live == (_edgeTimer != null)) return;
    _edgeTimer?.cancel();
    _edgeTimer = live
        ? Timer.periodic(const Duration(minutes: 1), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void didUpdateWidget(covariant _Hero old) {
    super.didUpdateWidget(old);
    // The "All" range asks for as many days of price as the history spans.
    if (old.history != widget.history) _loadPrices();
  }

  void _onPriceServiceChanged() => _loadPrices();

  /// Price days for the selected range. "All" walks up a ladder to the
  /// shortest series that still covers the wallet's history, so a young wallet
  /// does not download (and cache) a decade of prices it cannot use.
  int get _priceDays {
    if (_range.window != null) return _range.priceDays;
    final points = widget.history?.points ?? const <BalanceHistoryPoint>[];
    if (points.isEmpty) return 30;
    final span = DateTime.now().difference(points.first.time).inDays;
    for (final d in const [1, 7, 30, 90, 365]) {
      if (span <= d) return d;
    }
    return PriceHistoryService.allDays;
  }

  Future<void> _loadPrices() async {
    final currency = PriceService.instance.currency;
    final days = _priceDays;
    final key = '$currency|$days';
    // An empty series means offline/rate-limited, so a later price tick is
    // worth another try even though the key has not changed.
    final retryable = _pricesLoaded && _prices.isEmpty;
    if (_fetchingPrices || (key == _pricesKey && !retryable)) return;
    _fetchingPrices = true;
    _pricesKey = key;
    final series = await PriceHistoryService.instance.series(
      currency: currency,
      days: days,
    );
    _fetchingPrices = false;
    if (!mounted) return;
    setState(() {
      _prices = series;
      _pricesLoaded = true;
    });
  }

  void _selectRange(_ChartRange r) {
    if (r == _range) return;
    setState(() {
      _range = r;
      _hover = null;
    });
    _syncEdgeTimer();
    _loadPrices();
  }

  void _selectChain(_ChainFilter c) {
    if (c == _chain) return;
    setState(() {
      _chain = c;
      _hover = null;
    });
  }

  void _swapUnit() => setState(() {
    _coinFirst = !_coinFirst;
    _hover = null;
  });

  int _chainSats(BalanceHistoryPoint p) => switch (_chain) {
    _ChainFilter.all => p.btcSats + p.lbtcSats,
    _ChainFilter.btc => p.btcSats,
    _ChainFilter.liquid => p.lbtcSats,
  };

  int _currentSats(BalanceHistory h) => switch (_chain) {
    _ChainFilter.all => h.btcSats + h.lbtcSats,
    _ChainFilter.btc => h.btcSats,
    _ChainFilter.liquid => h.lbtcSats,
  };

  /// The balance step function clipped to the selected window, as
  /// (time, sats) pairs — always at least two samples.
  List<(DateTime, int)> _windowSamples(BalanceHistory h, DateTime now) {
    final points = h.points;
    final start = _range.window != null
        ? now.subtract(_range.window!)
        : (points.isNotEmpty
              ? points.first.time
              : now.subtract(const Duration(days: 30)));

    final out = <(DateTime, int)>[];
    int? carried;
    for (final p in points) {
      if (p.time.isBefore(start)) {
        carried = _chainSats(p);
        continue;
      }
      if (p.time.isAfter(now)) continue;
      out.add((p.time, _chainSats(p)));
    }
    // Balance before the window opened is the window's opening value —
    // without it a wallet that has not moved in 24h draws nothing at all.
    if (carried != null) out.insert(0, (start, carried));
    if (out.isEmpty) out.add((start, _currentSats(h)));
    out.add((now, _currentSats(h)));
    return out;
  }

  /// Fiat series: the balance is a step function, so resample onto an even
  /// grid — that is what makes the line move with price between transactions.
  List<ChartPoint> _fiatSeries(List<(DateTime, int)> samples, DateTime now) {
    final start = samples.first.$1;
    final spanMs = now.difference(start).inMilliseconds;
    final price = PriceHistoryService.instance;
    if (spanMs <= 0) {
      final sats = samples.last.$2;
      return [ChartPoint(now, sats / 1e8 * price.priceAt(now, _prices))];
    }
    const buckets = 120;
    final out = <ChartPoint>[];
    var index = 0;
    var held = samples.first.$2;
    for (var i = 0; i <= buckets; i++) {
      final t = start.add(Duration(milliseconds: spanMs * i ~/ buckets));
      while (index < samples.length && !samples[index].$1.isAfter(t)) {
        held = samples[index].$2;
        index++;
      }
      out.add(ChartPoint(t, held / 1e8 * price.priceAt(t, _prices)));
    }
    return out;
  }

  /// Built series, memoized on its inputs. [ValueChart] draws itself again
  /// whenever the list identity changes, so an unrelated rebuild (a price
  /// tick, a sync notification, the pointer moving) must hand back the very
  /// same list.
  List<ChartPoint> _seriesPoints(BalanceHistory? history, bool fiat) {
    // Keyed on content, not identity: a hash collision here would serve a
    // stale line for a different range or balance.
    final h = history;
    final hKey = h == null
        ? 'none'
        : '${h.points.length}.${h.btcSats}.${h.lbtcSats}.'
              '${h.points.isEmpty ? 0 : h.points.last.time.millisecondsSinceEpoch}';
    final pKey = _prices.isEmpty
        ? '0'
        : '${_prices.length}.${_prices.last.price}';
    final key =
        '$hKey|${_range.name}|${_chain.name}|$fiat|$pKey'
        '|${_nowBucket().millisecondsSinceEpoch}';
    final cached = _series;
    if (cached != null && key == _seriesKey) return cached;

    final List<ChartPoint> built;
    if (history == null) {
      built = const [];
    } else {
      final now = _nowBucket();
      final samples = _windowSamples(history, now);
      built = fiat
          ? _fiatSeries(samples, now)
          : [
              for (final (time, sats) in samples)
                ChartPoint(time, sats.toDouble()),
            ];
    }
    _series = built;
    _seriesKey = key;
    return built;
  }

  /// Percent change across the rendered series; null when it cannot be stated
  /// honestly (no history, or a zero opening value).
  double? _delta(List<ChartPoint> points) {
    if (points.length < 2) return null;
    final first = points.first.value;
    if (first <= 0) return null;
    return (points.last.value - first) / first * 100;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final useSats = context.select<AppState, bool>((st) => st.useSats);
    // Depend on the currency too, so the figure rebuilds when it changes.
    context.select<AppState, String>((st) => st.fiatCurrency);
    final hidden = balancesHidden(context);
    // Pure watch-only wallets cannot sign — no Send anywhere.
    final watchOnly = context.select<AppState, bool>(
      (st) => st.isActiveWalletWatchOnly,
    );
    final history = widget.history;
    int held(String ticker) => widget.data.assets
        .where((a) => a.ticker == ticker)
        .fold<int>(0, (sum, a) => sum + a.amount);
    final bothChains =
        history != null && history.hasBitcoin && history.hasLiquid;
    // The chain switch is one choice for the whole hero: it filters the
    // figure, its other denomination and the chart together. It only exists
    // on a wallet with both chains, so anything else reads as "all".
    final chain = bothChains ? _chain : _ChainFilter.all;
    final nativeSats = switch (chain) {
      _ChainFilter.all => held('BTC') + held('LBTC'),
      _ChainFilter.btc => held('BTC'),
      _ChainFilter.liquid => held('LBTC'),
    };
    final balanceLabel = switch (chain) {
      _ChainFilter.all => 'Total balance',
      _ChainFilter.btc => 'Bitcoin balance',
      _ChainFilter.liquid => 'Liquid balance',
    };

    return AnimatedBuilder(
      animation: PriceService.instance,
      builder: (context, _) {
        final price = PriceService.instance;
        // With no price feed there is only one number to show, so the swap
        // has nothing to swap to and the figure stays plain text.
        final swappable = price.hasPrice;
        final showCoin = _coinFirst || !swappable;
        final coinStr = PriceService.formatUnit(
          nativeSats,
          sat: useSats,
          coin: chain == _ChainFilter.liquid ? 'LBTC' : 'BTC',
        );
        final fiatStr = price.totalFiatDisplay(nativeSats);

        // Offline (or rate-limited): coin balance is still the truth, so the
        // chart shows that rather than nothing. Until the series lands,
        // priceAt falls back to the spot price; with neither, every balance
        // would be multiplied by zero into a flat line, so stay on coin.
        final priceUnavailable = _pricesLoaded && _prices.isEmpty;
        final hasAnyPrice = _prices.isNotEmpty || price.btcPrice > 0;
        final fiat = !showCoin && !priceUnavailable && hasAnyPrice;
        final points = _seriesPoints(history, fiat);
        final symbol = price.symbol;

        final figure = _Figure(
          value: hidden ? kMaskedAmount : (showCoin ? coinStr : fiatStr),
          splitUnit: showCoin && !hidden,
          swapTo: swappable
              ? (showCoin ? price.currency : (useSats ? 'sats' : 'BTC'))
              : null,
          onSwap: swappable ? _swapUnit : null,
        );
        final quiet = _QuietLine(
          other: swappable && !hidden ? (showCoin ? fiatStr : coinStr) : null,
          delta: _delta(points),
          period: _range.period,
        );

        final chart = ValueChart(
          height: phone ? 160 : 280,
          points: points,
          axes: true,
          markLatest: true,
          showReadout: phone,
          onCursor: phone ? null : (p) => setState(() => _hover = p),
          formatValue: (v) => hidden
              ? kMaskedAmount
              : fiat
              ? PriceService.formatFiat(v, symbol)
              : PriceService.formatUnit(v.round(), sat: useSats),
          formatAxis: (v, step) => hidden
              ? ''
              : fiat
              ? _axisLabel(v, step, prefix: symbol)
              : useSats
              ? _axisLabel(v, step)
              : _axisLabel(v / 1e8, step / 1e8),
          emptyMessage: history != null
              ? 'No history yet'
              : widget.historyFailed
              ? 'Balance history unavailable'
              : 'Loading history…',
          // Draw again only when the user changes the view, not on the
          // per-minute edge refresh.
          animationKey: '${_range.name}|${_chain.name}|$fiat',
        );
        final priceNote = !showCoin && priceUnavailable
            ? Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'No price history yet — the chart shows the coin balance',
                  style: AppTypography.caption.copyWith(color: s.inkFaint),
                ),
              )
            : null;

        if (phone) {
          return _phoneHero(
            context,
            balanceLabel: balanceLabel,
            figure: figure,
            quiet: quiet,
            chart: chart,
            priceNote: priceNote,
            bothChains: bothChains,
            watchOnly: watchOnly,
          );
        }
        return _desktopHero(
          context,
          balanceLabel: balanceLabel,
          figure: figure,
          quiet: quiet,
          chart: chart,
          priceNote: priceNote,
          bothChains: bothChains,
          watchOnly: watchOnly,
          hidden: hidden,
          fiat: fiat,
          symbol: symbol,
          useSats: useSats,
        );
      },
    );
  }

  Widget _desktopHero(
    BuildContext context, {
    required String balanceLabel,
    required Widget figure,
    required Widget quiet,
    required Widget chart,
    required Widget? priceNote,
    required bool bothChains,
    required bool watchOnly,
    required bool hidden,
    required bool fiat,
    required String symbol,
    required bool useSats,
  }) {
    final s = AppScheme.of(context);
    final hover = _hover;

    final rangeSwitch = SegmentedSwitch<_ChartRange>(
      dense: true,
      selected: _range,
      onChanged: _selectRange,
      options: [
        for (final r in _ChartRange.values) SegOption(value: r, label: r.label),
      ],
    );
    final chainSwitch = bothChains
        ? SegmentedSwitch<_ChainFilter>(
            dense: true,
            selected: _chain,
            onChanged: _selectChain,
            options: [
              const SegOption(value: _ChainFilter.all, label: 'All'),
              SegOption(value: _ChainFilter.btc, label: 'BTC', dot: s.bitcoin),
              SegOption(
                value: _ChainFilter.liquid,
                label: 'Liquid',
                dot: s.liquid,
              ),
            ],
          )
        : null;

    // The pointer's sample, where the controls row has room for it: the
    // date quiet, the value in ink. Neutral — it is a reading, not an action.
    final readout = hover == null
        ? const SizedBox.shrink()
        : Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${_stamp(hover.time)}  ',
                  style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
                ),
                TextSpan(
                  text: hidden
                      ? kMaskedAmount
                      : fiat
                      ? PriceService.formatFiat(hover.value, symbol)
                      : PriceService.formatUnit(
                          hover.value.round(),
                          sat: useSats,
                        ),
                  style: AppTypography.numeric.copyWith(color: s.ink),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );

    return HeroPanel(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _BalanceLabel(label: balanceLabel),
                    const SizedBox(height: AppSpacing.xs),
                    figure,
                    const SizedBox(height: AppSpacing.xs),
                    quiet,
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              // The hero's lead pair: large, and one width for both.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!watchOnly) ...[
                    SizedBox(
                      width: _heroActionWidth,
                      child: PrimaryButton(
                        label: 'Send',
                        icon: Icons.arrow_outward_outlined,
                        isFullWidth: true,
                        large: true,
                        onPressed: () => context.go(AppRoutes.send),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  SizedBox(
                    width: _heroActionWidth,
                    child: SecondaryButton(
                      label: 'Receive',
                      icon: Icons.call_received_outlined,
                      isFullWidth: true,
                      large: true,
                      onPressed: () => context.go(AppRoutes.receive),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(child: readout),
              if (chainSwitch != null) ...[
                const SizedBox(width: AppSpacing.lg),
                chainSwitch,
                const SizedBox(width: AppSpacing.md),
              ],
              rangeSwitch,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          chart,
          ?priceNote,
        ],
      ),
    );
  }

  Widget _phoneHero(
    BuildContext context, {
    required String balanceLabel,
    required Widget figure,
    required Widget quiet,
    required Widget chart,
    required Widget? priceNote,
    required bool bothChains,
    required bool watchOnly,
  }) {
    final s = AppScheme.of(context);
    final receive = SecondaryButton(
      label: 'Receive',
      icon: Icons.call_received_outlined,
      isFullWidth: true,
      onPressed: () => context.go(AppRoutes.receive),
    );
    return HeroPanel(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The network is stated once on a phone, here, where the number
          // is read.
          Row(
            children: [
              Expanded(
                child: _BalanceLabel(label: balanceLabel, withToggle: false),
              ),
              TestnetBadge(label: networkBadgeLabel(context)),
              const SizedBox(width: AppSpacing.xs),
              const PrivacyToggle(),
            ],
          ),
          figure,
          const SizedBox(height: AppSpacing.xs),
          quiet,
          const SizedBox(height: AppSpacing.lg),
          chart,
          ?priceNote,
          const SizedBox(height: AppSpacing.sm),
          _TextChips<_ChartRange>(
            selected: _range,
            onChanged: _selectRange,
            spread: true,
            options: [
              for (final r in _ChartRange.values) (r, r.shortLabel, null),
            ],
          ),
          if (bothChains)
            _TextChips<_ChainFilter>(
              selected: _chain,
              onChanged: _selectChain,
              options: [
                (_ChainFilter.all, 'All', null),
                (_ChainFilter.btc, 'BTC', s.bitcoin),
                (_ChainFilter.liquid, 'Liquid', s.liquid),
              ],
            ),
          const SizedBox(height: AppSpacing.lg),
          if (watchOnly)
            receive
          else
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Send',
                    icon: Icons.arrow_outward_outlined,
                    isFullWidth: true,
                    onPressed: () => context.go(AppRoutes.send),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: receive),
              ],
            ),
        ],
      ),
    );
  }
}

const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// The pointer's date in the desktop read-out.
String _stamp(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.day} ${_months[t.month - 1]} ${t.year}, '
      '${two(t.hour)}:${two(t.minute)}';
}

/// A y-axis tick, compact enough to sit at the chart's edge. Only here may a
/// figure be shortened (`€1.25M`, `€850k`): a tick is a gridline's name, not
/// a balance. [step] is the gap between ticks, so the label carries exactly
/// the decimals that tell two ticks apart.
String _axisLabel(double v, double step, {String prefix = ''}) {
  int decimalsFor(double st) {
    var d = 0;
    var x = st.abs();
    while (d < 8 && (x - x.roundToDouble()).abs() > 1e-6 * math.max(1, x)) {
      x *= 10;
      d++;
    }
    return d;
  }

  String trim(String s) =>
      s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;

  String grouped(int n) {
    final digits = n.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return (n < 0 ? '-' : '') + b.toString();
  }

  final a = v.abs();
  if (a >= 1e6 && step >= 1e4) {
    return '$prefix${trim((v / 1e6).toStringAsFixed(decimalsFor(step / 1e6)))}M';
  }
  if (a >= 1e4 && step >= 100) {
    return '$prefix${trim((v / 1e3).toStringAsFixed(decimalsFor(step / 1e3)))}k';
  }
  final d = decimalsFor(step);
  if (d == 0) return '$prefix${grouped(v.round())}';
  final fixed = v.toStringAsFixed(d);
  final dot = fixed.indexOf('.');
  return '$prefix${grouped(int.parse(fixed.substring(0, dot)))}'
      '${fixed.substring(dot)}';
}

/// Width of each of the hero's two actions on desktop.
const double _heroActionWidth = 152;

/// What the figure counts — "Total balance", or one chain's when the chain
/// switch narrows the hero — and on desktop the eye beside it.
class _BalanceLabel extends StatelessWidget {
  const _BalanceLabel({required this.label, this.withToggle = true});

  final String label;
  final bool withToggle;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final text = Text(
      label,
      style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
    );
    if (!withToggle) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        text,
        const SizedBox(width: AppSpacing.xs),
        const PrivacyToggle(),
      ],
    );
  }
}

/// The figure: exact, never abbreviated. A coin figure splits into the number
/// in ink and its unit one size down in the faint ink; a fiat figure carries
/// its symbol in front and has nothing to split. A tap swaps the unit, and a
/// small swap glyph beside it says the number can be tapped.
class _Figure extends StatefulWidget {
  const _Figure({
    required this.value,
    required this.splitUnit,
    this.swapTo,
    this.onSwap,
  });

  final String value;
  final bool splitUnit;

  /// The unit a tap switches to; null when there is nothing to switch to.
  final String? swapTo;
  final VoidCallback? onSwap;

  @override
  State<_Figure> createState() => _FigureState();
}

class _FigureState extends State<_Figure> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final bigStyle = AppTypography.balanceHeroOf(
      context,
    ).copyWith(color: s.ink);
    final unitStyle =
        (phone
                ? AppTypography.balanceMediumOf(context)
                : AppTypography.balanceMedium)
            .copyWith(color: s.inkFaint);

    var number = widget.value;
    String? unit;
    if (widget.splitUnit) {
      final i = number.lastIndexOf(' ');
      if (i > 0) {
        unit = number.substring(i + 1);
        number = number.substring(0, i);
      }
    }

    Widget text = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(number, maxLines: 1, style: bigStyle),
        if (unit != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(unit, maxLines: 1, style: unitStyle),
        ],
      ],
    );
    // A long sats figure scales down to the column instead of wrapping.
    text = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: text,
    );

    final onSwap = widget.onSwap;
    final to = widget.swapTo;
    if (onSwap == null || to == null) return text;

    final glyph = Icon(
      Icons.swap_vert_outlined,
      size: phone ? 20 : AppSpacing.iconSmall,
      color: _hover || _focus ? s.inkSecondary : s.inkFaint,
    );
    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        const SizedBox(width: AppSpacing.sm),
        glyph,
      ],
    );
    final tappable = Semantics(
      button: true,
      label: '${widget.value}. Show $to',
      excludeSemantics: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onSwap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSwap,
          child: Container(
            foregroundDecoration: _focus
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    border: Border.all(color: s.focus, width: 2),
                  )
                : null,
            child: body,
          ),
        ),
      ),
    );
    if (phone) return tappable;
    return Tooltip(message: 'Show $to', child: tappable);
  }
}

/// One quiet line under the figure: the other denomination, then the change
/// over the chart's range with its period spelled out.
class _QuietLine extends StatelessWidget {
  const _QuietLine({
    required this.other,
    required this.delta,
    required this.period,
  });

  /// "≈ 0.01734567 BTC" without the "≈"; null hides it (no price, masked).
  final String? other;

  /// Percent change over the range; null when it cannot be stated.
  final double? delta;
  final String period;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final style = AppTypography.bodyOf(context);
    final d = delta;
    // Sub-0.05% moves read as noise, not as a gain.
    final flat = d == null || d.abs() < 0.05;
    final up = d != null && d > 0;
    final ink = flat ? s.inkSecondary : (up ? s.success : s.danger);
    final o = other;

    final change = d == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!flat) ...[
                Icon(
                  up
                      ? Icons.arrow_upward_outlined
                      : Icons.arrow_downward_outlined,
                  size: AppSpacing.iconSmall,
                  color: ink,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                '${flat ? '' : (up ? '+' : '−')}'
                '${(flat ? 0.0 : d.abs()).toStringAsFixed(1)}% $period',
                style: style.copyWith(color: ink),
              ),
            ],
          );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.xs,
      children: [
        if (o != null)
          Text('≈ $o', style: style.copyWith(color: s.inkSecondary)),
        if (o != null && change != null)
          Text('  ·  ', style: style.copyWith(color: s.inkFaint)),
        ?change,
      ],
    );
  }
}

// ── Phone chart controls ──────────────────────────────────────────────────────

/// A row of words, one of them chosen: the phone's quiet stand-in for a
/// segmented track. Each word is a 48 dp target; the chosen one sits on the
/// selected surface in the primary ink, the rest are faint. [spread] shares
/// the row out evenly — for the six ranges — where the default packs the
/// words to the left. A chain may carry its 6 px dot.
class _TextChips<T> extends StatelessWidget {
  const _TextChips({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.spread = false,
  });

  /// (value, label, chain dot).
  final List<(T, String, Color?)> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool spread;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final motion = AppMotion.of(context, AppMotion.quick);
    return Row(
      mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: spread
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      children: [
        for (final (value, label, dot) in options)
          Semantics(
            button: true,
            selected: value == selected,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(value),
              child: ConstrainedBox(
                // A word is a control: it clears the touch floor on both axes
                // even though the chosen surface inside it is smaller.
                constraints: const BoxConstraints(
                  minHeight: AppLayout.minTouchTarget,
                  minWidth: AppLayout.minTouchTarget,
                ),
                child: Center(
                  widthFactor: 1,
                  child: AnimatedContainer(
                    duration: motion,
                    curve: AppMotion.settle,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: value == selected
                          ? s.selected
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (dot != null) ...[
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dot,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        Text(
                          label,
                          style: AppTypography.label.copyWith(
                            color: value == selected ? s.ink : s.inkFaint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Rows ──────────────────────────────────────────────────────────────────────
// The chain cards and the phone's lists share one row: a leading glyph in the
// icon column, a title (with an optional ticker tag), one line under it, and
// an amount column on the right. Same metrics as `ListRow` — which takes only
// an icon — so an asset's own logo can head the row.

class _DataRow extends StatefulWidget {
  const _DataRow({
    required this.leading,
    required this.title,
    this.tag,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.gutter = kListPad,
  });

  /// Sits centred in the 32 px icon column.
  final Widget leading;
  final String title;

  /// A ticker beside the title.
  final String? tag;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  /// The row's side inset: the list's own, or the card's when the row sits
  /// inside a card whose header uses the card padding.
  final double gutter;

  @override
  State<_DataRow> createState() => _DataRowState();
}

class _DataRowState extends State<_DataRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final onTap = widget.onTap;
    final sub = widget.subtitle;

    final content = Row(
      children: [
        SizedBox(
          width: kListTile,
          height: kListTile,
          child: Center(child: widget.leading),
        ),
        const SizedBox(width: kListGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyOf(
                        context,
                      ).copyWith(color: s.ink),
                    ),
                  ),
                  if (widget.tag != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    AssetBadge(ticker: widget.tag!),
                  ],
                ],
              ),
              ?sub,
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          widget.trailing!,
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
      constraints: BoxConstraints(
        minHeight: phone && sub != null
            ? AppSpacing.rowHeight + AppSpacing.sm
            : AppSpacing.rowHeight,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: widget.gutter,
        vertical: AppSpacing.sm,
      ),
      child: content,
    );

    if (onTap == null) return MergeSemantics(child: body);
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
      ),
    );
  }
}

/// A row's subtitle in the caption voice.
Widget _caption(BuildContext context, String text, {Color? color}) {
  final s = AppScheme.of(context);
  return Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppTypography.caption.copyWith(color: color ?? s.inkSecondary),
  );
}

/// Rows of one list, hairlines between them inset past the icon column.
List<Widget> _ruled(BuildContext context, List<Widget> rows, double gutter) {
  final s = AppScheme.of(context);
  return [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0)
        Divider(
          height: 1,
          thickness: 1,
          color: s.edge,
          indent: gutter + kListTile + kListGap,
        ),
      rows[i],
    ],
  ];
}

/// "1 coin" / "3 coins".
String _coins(int n) => '$n coin${n == 1 ? '' : 's'}';

/// BTC or LBTC: the chain's own coin, counted in coins.
Widget _nativeAssetRow(
  BuildContext context, {
  required AssetBalance asset,
  required String title,
  required bool useSats,
  required bool masked,
  double gutter = kListPad,
  VoidCallback? onTap,
}) {
  final s = AppScheme.of(context);
  final price = PriceService.instance;
  final coin = asset.ticker == 'LBTC' ? 'LBTC' : 'BTC';
  final fiat = price.fiatDisplay(asset.amount);
  // 'synced' is the quiet case; anything else is worth a word, and
  // 'unavailable' is worth a red one.
  final unsynced = asset.status != 'synced';
  return _DataRow(
    leading: AssetLogo(ticker: coin, size: 24),
    title: title,
    tag: coin,
    gutter: gutter,
    onTap: onTap,
    subtitle: _caption(
      context,
      unsynced
          ? '${_coins(asset.utxoCount)} · ${asset.status}'
          : _coins(asset.utxoCount),
      color: asset.status == 'unavailable' ? s.danger : null,
    ),
    trailing: ListAmount(
      value: masked
          ? kMaskedAmount
          : PriceService.formatUnit(asset.amount, sat: useSats, coin: coin),
      unit: masked || fiat == null ? null : fiat,
    ),
  );
}

/// Opens a token the way a transaction is opened: the detail dialog (a sheet
/// on a phone), the same one the Liquid page shows. The issuance record, if
/// this wallet issued the asset, is read first so the dialog can say so.
Future<void> _openToken(BuildContext context, AssetGroup g) async {
  final walletId = context.read<AppState>().activeWalletId;
  var issued = const <String, IssuedAssetEntry>{};
  if (walletId != null) {
    try {
      issued = await IssuedAssetStore.instance.getIssuedAssets(walletId);
    } catch (_) {
      // No record readable: the asset still opens, as one merely held.
    }
  }
  if (!context.mounted) return;
  final id = g.main.assetId;
  await showAssetDetailDialog(
    context,
    asset: g.main,
    reissuanceToken: g.reissuanceToken,
    issued: issued[id],
    isReissuanceToken: issued.values.any((e) => e.tokenId == id),
  );
}

/// A Liquid token: named by the registry where it is known, and saying so.
Widget _tokenRow(
  BuildContext context,
  AssetGroup g, {
  required bool masked,
  required bool isHidden,
  double gutter = kListPad,
  VoidCallback? onTap,
}) {
  final registry = AssetRegistryService.instance;
  final asset = g.main;
  final ticker = registry.displayTicker(asset);
  final name = registry.displayName(asset);
  final info = registry.get(asset.assetId);
  final details = <String>[
    if (info?.domain != null && info!.domain!.isNotEmpty) info.domain!,
    if (g.reissuanceToken != null) 'Reissuance token',
    if (isHidden) 'Hidden',
  ];
  return _DataRow(
    leading: AssetLogo(ticker: asset.ticker, size: 24),
    title: name == 'Unknown Asset' ? ticker : name,
    tag: name == 'Unknown Asset' ? null : ticker,
    gutter: gutter,
    onTap: onTap,
    subtitle: _caption(
      context,
      details.isEmpty ? 'Liquid asset' : details.join(' · '),
    ),
    // Room for an eight-decimal token amount and its ticker: a holding is
    // never cut to an ellipsis.
    trailing: ListAmount(
      value: masked ? kMaskedAmount : asset.displayAmount,
      maxWidth: 220,
    ),
  );
}

/// One transaction: which way it went, what it was, how settled it is, and
/// how much.
class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.tx, this.gutter = kListPad});

  final RecentActivityItem tx;
  final double gutter;

  /// "tb1q…4x2p" as the engine gives it, or the txid cut the same way.
  static String _short(String s) =>
      s.length <= 14 ? s : '${s.substring(0, 6)}…${s.substring(s.length - 4)}';

  /// The engine's amount with the direction's sign: "+" for incoming,
  /// a true minus for outgoing. A self-transfer keeps its own string.
  String get _signed {
    final raw = tx.amount.trim();
    if (tx.direction == 'self') return raw;
    final bare = raw.replaceFirst(RegExp(r'^[+\-−]'), '');
    return tx.direction == 'incoming' ? '+$bare' : '−$bare';
  }

  /// The fiat value of a BTC/LBTC amount, read off the engine's own string;
  /// null for a token (no price) or anything that does not parse.
  String? get _fiat {
    final parts = tx.amount
        .trim()
        .replaceFirst(RegExp(r'^[+\-−~]'), '')
        .split(' ');
    if (parts.length != 2) return null;
    final n = double.tryParse(parts[0].replaceAll(',', ''));
    if (n == null) return null;
    final int sats;
    switch (parts[1].toUpperCase()) {
      case 'BTC' || 'LBTC' || 'L-BTC':
        sats = (n * 1e8).round();
      case 'SATS' || 'SAT':
        sats = n.round();
      default:
        return null;
    }
    return PriceService.instance.fiatDisplay(sats);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final masked = balancesHidden(context);
    final isIn = tx.direction == 'incoming';
    final isSelf = tx.direction == 'self';
    final who = tx.counterparty;
    final id = who != null && who.isNotEmpty ? _short(who) : _short(tx.txid);
    final state = tx.isConfirmed
        ? '${tx.confirmations} confirmation${tx.confirmations == 1 ? '' : 's'}'
        : 'Pending';

    return _DataRow(
      gutter: gutter,
      onTap: () => context.go(AppRoutes.history),
      leading: ListIconTile(
        icon: isSelf
            ? Icons.swap_horiz_outlined
            : isIn
            ? Icons.call_received_outlined
            : Icons.arrow_outward_outlined,
      ),
      title:
          tx.note ??
          (isSelf
              ? 'Internal transfer'
              : isIn
              ? 'Received'
              : 'Sent'),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: id,
              style: AppTypography.monoSmall.copyWith(color: s.inkSecondary),
            ),
            TextSpan(
              text: ' · $state',
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: AnimatedBuilder(
        animation: PriceService.instance,
        builder: (_, _) => ListAmount(
          value: masked ? kMaskedAmount : _signed,
          unit: masked ? null : _fiat,
          valueColor: isIn ? s.success : s.ink,
          maxWidth: 160,
        ),
      ),
    );
  }
}

// ── Phone lists: assets, then activity ───────────────────────────────────────

AssetBalance? _assetWithTicker(List<AssetBalance> assets, String ticker) {
  for (final a in assets) {
    if (a.ticker == ticker) return a;
  }
  return null;
}

class _PhoneAssets extends StatelessWidget {
  const _PhoneAssets({
    required this.data,
    required this.issuedAssets,
    required this.hiddenAssets,
  });

  final DashboardData data;
  final Map<String, IssuedAssetEntry> issuedAssets;
  final List<String> hiddenAssets;

  @override
  Widget build(BuildContext context) {
    final useSats = context.select<AppState, bool>((st) => st.useSats);
    final hasLiquid = context.select<AppState, bool>(
      (st) => st.activeWalletLiquid,
    );
    final masked = balancesHidden(context);

    final btc = _assetWithTicker(data.assets, 'BTC');
    final lbtc = _assetWithTicker(data.assets, 'LBTC');
    final tokens = groupAssets(
      data.assets
          .where((a) => a.ticker != 'BTC' && a.ticker != 'LBTC')
          .toList(),
      issuedAssets,
    ).where((g) => !hiddenAssets.contains(g.main.assetId)).toList();

    return AnimatedBuilder(
      animation: PriceService.instance,
      builder: (context, _) {
        final rows = <Widget>[
          if (btc != null)
            _nativeAssetRow(
              context,
              asset: btc,
              title: 'Bitcoin',
              useSats: useSats,
              masked: masked,
            ),
          if (lbtc != null)
            _nativeAssetRow(
              context,
              asset: lbtc,
              title: 'Liquid Bitcoin',
              useSats: useSats,
              masked: masked,
              onTap: () => context.go(AppRoutes.liquid),
            ),
          for (final g in tokens)
            _tokenRow(
              context,
              g,
              masked: masked,
              isHidden: false,
              onTap: () => _openToken(context, g),
            ),
        ];
        if (rows.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListSectionLabel(
              label: 'Assets',
              actionLabel: hasLiquid ? 'Liquid' : null,
              onAction: hasLiquid ? () => context.go(AppRoutes.liquid) : null,
            ),
            ListCard(children: rows),
          ],
        );
      },
    );
  }
}

class _PhoneActivity extends StatelessWidget {
  const _PhoneActivity({required this.data});

  final DashboardData data;

  /// Enough to answer "did it arrive?" without becoming the Activity screen.
  static const int _shown = 4;

  @override
  Widget build(BuildContext context) {
    final items = [...data.recentActivity]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final recent = items.take(_shown).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListSectionLabel(
          label: 'Recent activity',
          actionLabel: recent.isEmpty ? null : 'All',
          onAction: recent.isEmpty ? null : () => context.go(AppRoutes.history),
        ),
        ListCard(
          children: recent.isEmpty
              ? const [
                  ListRow(
                    icon: Icons.inbox_outlined,
                    title: 'Nothing yet',
                    subtitle: 'Received and sent transactions land here',
                  ),
                ]
              : [for (final tx in recent) _ActivityRow(tx: tx)],
        ),
      ],
    );
  }
}

// ── Chain sections (desktop) ──────────────────────────────────────────────────
//
// Below the hero the wallet stops being one number and becomes two chains: a
// row reading "+100 USDT" says nothing about which chain settled it, and BTC
// and LBTC are not interchangeable. One card per chain, in the order the
// chart's filter offers them (Bitcoin, then Liquid), each with its balance and
// its lists inside it. The chain's hue lives in its logo and nowhere else.

class _ChainSections extends StatelessWidget {
  const _ChainSections({
    required this.data,
    required this.issuedAssets,
    required this.hiddenAssets,
    required this.showHidden,
    required this.onToggleShowHidden,
  });

  final DashboardData data;
  final Map<String, IssuedAssetEntry> issuedAssets;
  final List<String> hiddenAssets;
  final bool showHidden;
  final VoidCallback onToggleShowHidden;

  /// Below this the two cards stack — side by side they would each be too
  /// narrow for an amount and an address on one line.
  static const double _sideBySide = 880;

  List<RecentActivityItem> _activity(String chain) =>
      data.recentActivity.where((t) => t.chain == chain).take(3).toList();

  @override
  Widget build(BuildContext context) {
    final btc = _assetWithTicker(data.assets, 'BTC');
    final lbtc = _assetWithTicker(data.assets, 'LBTC');

    final cards = <Widget>[
      if (btc != null)
        _ChainCard(
          title: 'Bitcoin',
          native: btc,
          activity: _activity('bitcoin'),
        ),
      if (lbtc != null)
        _ChainCard(
          title: 'Liquid',
          native: lbtc,
          activity: _activity('liquid'),
          // Optional: Settings › Advanced decides whether Loans exists in the
          // wallet chrome at all, including this dashboard shortcut.
          showLoans: context.select<AppState, bool>(
            (state) => state.loansEnabled,
          ),
          // Everything that is not LBTC on the Liquid side: issued tokens and
          // third-party assets, with their reissuance tokens folded in.
          assets: data.assets
              .where((a) => a.ticker != 'BTC' && a.ticker != 'LBTC')
              .toList(),
          issuedAssets: issuedAssets,
          hiddenAssets: hiddenAssets,
          showHidden: showHidden,
          onToggleShowHidden: onToggleShowHidden,
        ),
    ];

    if (cards.isEmpty) return const SizedBox.shrink();
    if (cards.length == 1) return cards.single;

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < _sideBySide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: AppSpacing.xl),
              cards[1],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: AppSpacing.xl),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _ChainCard extends StatelessWidget {
  const _ChainCard({
    required this.title,
    required this.native,
    required this.activity,
    this.assets,
    this.issuedAssets = const {},
    this.hiddenAssets = const [],
    this.showHidden = false,
    this.onToggleShowHidden,
    this.showLoans = false,
  });

  final String title;

  /// The chain's own coin — BTC or LBTC. This is the card's lead figure.
  final AssetBalance native;

  final List<RecentActivityItem> activity;

  /// Non-native assets on this chain. Null on Bitcoin, which has none.
  final List<AssetBalance>? assets;
  final Map<String, IssuedAssetEntry> issuedAssets;
  final List<String> hiddenAssets;
  final bool showHidden;
  final VoidCallback? onToggleShowHidden;

  /// Whether this chain carries the Templar Protocol row (Liquid does).
  final bool showLoans;

  static const double _pad = AppSpacing.cardPadding;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final useSats = context.select<AppState, bool>((st) => st.useSats);
    final hidden = balancesHidden(context);
    final price = PriceService.instance;
    final coin = native.ticker == 'LBTC' ? 'LBTC' : 'BTC';
    final rule = Divider(height: 1, thickness: 1, color: s.edge);

    return PlainCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: AnimatedBuilder(
          animation: price,
          builder: (context, _) {
            final (value, unit) = _splitUnit(
              PriceService.formatUnit(native.amount, sat: useSats, coin: coin),
            );
            final fiat = price.fiatDisplay(native.amount);
            final caption = [
              if (fiat != null && !hidden) '≈ $fiat',
              _coins(native.utxoCount),
            ].join(' · ');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(_pad),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AssetLogo(ticker: coin, size: 24),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.sectionTitle.copyWith(
                                color: s.ink,
                              ),
                            ),
                          ),
                          if (native.status != 'synced')
                            StatusBadge(
                              label: native.status,
                              variant: native.status == 'unavailable'
                                  ? BadgeVariant.danger
                                  : BadgeVariant.neutral,
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              hidden ? kMaskedAmount : value,
                              maxLines: 1,
                              style: AppTypography.balanceLarge.copyWith(
                                color: s.ink,
                              ),
                            ),
                            if (!hidden && unit != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                unit,
                                maxLines: 1,
                                style: AppTypography.balanceMedium.copyWith(
                                  color: s.inkFaint,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        caption,
                        style: AppTypography.caption.copyWith(
                          color: s.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                // Templar Protocol — Liquid only. A row that goes to the
                // Loans page, where the protocol's state is read.
                if (showLoans) ...[
                  rule,
                  _DataRow(
                    gutter: _pad,
                    leading: const ListIconTile(icon: Icons.handshake_outlined),
                    title: 'Loans',
                    subtitle: _caption(context, 'Templar Protocol'),
                    chevron: true,
                    onTap: () => context.go(AppRoutes.loans),
                  ),
                ],
                if (assets != null) ...[rule, ..._assetBlock(context, hidden)],
                rule,
                _ListHead(
                  label: 'Latest',
                  action: GhostButton(
                    label: 'All activity',
                    onPressed: () => context.go(AppRoutes.history),
                  ),
                ),
                if (activity.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _pad,
                      AppSpacing.xs,
                      _pad,
                      _pad,
                    ),
                    child: Text(
                      'Nothing yet on this chain',
                      style: AppTypography.caption.copyWith(color: s.inkFaint),
                    ),
                  )
                else
                  ..._ruled(context, [
                    for (final tx in activity)
                      _ActivityRow(tx: tx, gutter: _pad),
                  ], _pad),
              ],
            );
          },
        ),
      ),
    );
  }

  /// The Liquid assets as rows, with the switch for hidden ones.
  List<Widget> _assetBlock(BuildContext context, bool masked) {
    final s = AppScheme.of(context);
    final groups = groupAssets(assets!, issuedAssets);
    final visible = showHidden
        ? groups
        : groups.where((g) => !hiddenAssets.contains(g.main.assetId)).toList();
    final hiddenCount = groups
        .where((g) => hiddenAssets.contains(g.main.assetId))
        .length;
    final toggle = onToggleShowHidden;

    return [
      _ListHead(
        label: 'Assets',
        action: hiddenCount > 0 && toggle != null
            ? GhostButton(
                label: showHidden
                    ? 'Hide hidden ($hiddenCount)'
                    : 'Show hidden ($hiddenCount)',
                onPressed: toggle,
              )
            : null,
      ),
      if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(_pad, AppSpacing.xs, _pad, _pad),
          child: Text(
            'No other assets on Liquid',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        )
      else
        ..._ruled(context, [
          for (final g in visible)
            _tokenRow(
              context,
              g,
              masked: masked,
              isHidden: hiddenAssets.contains(g.main.assetId),
              gutter: _pad,
              onTap: () => _openToken(context, g),
            ),
        ], _pad),
    ];
  }
}

/// The quiet name of a list inside a card, with its one way in on the right.
class _ListHead extends StatelessWidget {
  const _ListHead({required this.label, this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: SizedBox(
        height: AppSpacing.controlHeight,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}

/// "0.01734567 BTC" → the number, and its unit.
(String, String?) _splitUnit(String text) {
  final i = text.lastIndexOf(' ');
  if (i <= 0) return (text, null);
  return (text.substring(0, i), text.substring(i + 1));
}

/// The network the dashboard states: `TESTNET`, or `REGTEST` when Bitcoin
/// runs on a joined test server's regtest (Liquid is then on its regtest too).
String networkBadgeLabel(BuildContext context) {
  final st = maybeAppState(context);
  final regtest = (st?.isBitcoinRegtest ?? false) || (st?.isLiquidRegtest ?? false);
  return regtest ? 'REGTEST' : 'TESTNET';
}
