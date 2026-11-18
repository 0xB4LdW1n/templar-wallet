import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/peg_tx_label_store.dart';
import '../../services/fee_bump_store.dart';
import '../../services/price_service.dart';
import '../../shared/relative_time.dart';
import '../../shared/widgets/app_password_gate.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/chain_switch.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/psbt_sign_flow.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../utxos/models/pending_consolidation.dart';
import '../../services/pending_consolidation_store.dart';
import '../hardware/hw_error.dart';
import '../hardware/ledger_connect_dialog.dart';
import '../hardware/ledger_signing_dialog.dart';
import '../psbt/cosign_handoff.dart';
import 'activity_details.dart';
import 'activity_rows.dart';
import 'activity_sources.dart';
import 'fee_bump_dialog.dart';
import 'fee_bump_fold.dart';
import 'liquid_leg_fold.dart';
import 'models/activity_entry.dart';
import 'models/fee_bump_preview.dart';
import 'models/transaction.dart';
import 'speed_up_button.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

/// Activity: one timeline of the wallet's payments on both chains, its
/// Templar Protocol loans, its swaps and its pegs (see
/// models/activity_entry.dart for what each source contributes).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.bridge, this.loans, this.openTxid});

  /// A transaction to open the detail of as soon as it is listed — where
  /// "View in activity" lands after a send. A transaction just broadcast is
  /// in no list until the next sync, so the screen keeps the request until
  /// a load brings it.
  final String? openTxid;

  /// Test seam; the app uses the global engine.
  final WalletBridge? bridge;

  /// Test seam for the loan source; the app reads the protocol store and
  /// the connected sites (or the mock bridge's demo portfolio).
  final LoanActivityLoader? loans;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;
  late final ActivitySources _sources = ActivitySources(
    bridge: _bridge,
    loans: widget.loans,
  );
  List<Transaction> _txs = [];
  ActivityExtras _extras = const ActivityExtras();
  bool _loading = true;
  String? _error;
  String _chainFilter = 'all';

  /// The kind filter; null is "All".
  ActivityKind? _kindFilter;
  final _searchController = TextEditingController();
  String? _feeBumpBusyTxid;

  /// The app state this screen follows: a finished sync bumps its
  /// `syncVersion` and the timeline is read again, so a payment that just
  /// confirmed stops breathing without the user leaving the page.
  AppState? _appState;
  int _lastSyncVersion = 0;

  /// The transaction whose detail is still owed ([HistoryScreen.openTxid]).
  late String? _openTxid = widget.openTxid;

  @override
  void didUpdateWidget(HistoryScreen old) {
    super.didUpdateWidget(old);
    if (widget.openTxid != null && widget.openTxid != old.openTxid) {
      _openTxid = widget.openTxid;
      _scheduleOpen();
    }
  }

  /// Opens the owed detail once the frame that lists it has been built.
  void _scheduleOpen() {
    if (_openTxid == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _openOwedDetail());
  }

  void _openOwedDetail() {
    final txid = _openTxid;
    if (txid == null || !mounted) return;
    final timeline = _timeline(_flags(context.read<AppState>()));
    for (final e in timeline.entries) {
      if (e is PaymentEntry) {
        // A bump's other transaction is folded into this row: asking for
        // the child opens the payment it pays for.
        if (e.tx.txid == txid || e.tx.bump?.otherTxid == txid) {
          _openTxid = null;
          _showDetail(context, e.tx);
          return;
        }
      } else if (e.txids.contains(txid)) {
        _openTxid = null;
        _showEntryDetail(context, e, timeline.linked);
        return;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final appState = context.read<AppState>();
    _appState = appState;
    _lastSyncVersion = appState.syncVersion;
    appState.addListener(_onAppStateChanged);
    if (appState.cachedTransactions != null) {
      _txs = appState.cachedTransactions!;
      _loading = false;
      _scheduleOpen();
    }
    final walletId = appState.activeWalletId;
    final cachedExtras = walletId == null
        ? null
        : ActivitySources.cached(walletId);
    if (cachedExtras != null) _extras = cachedExtras;
    _load();
  }

  ActivitySourceFlags _flags(AppState st) => ActivitySourceFlags(
    bitcoin: st.activeWalletBitcoin,
    liquid: st.activeWalletLiquid,
    loans: st.loansEnabled,
    liquidDex: st.liquidDexEnabled,
    peg: st.pegEnabled,
  );

  /// Loans, swaps and pegs, beside `list_activity` and never in its way:
  /// each source fails alone, and the rows already on screen stay.
  Future<void> _loadExtras(AppState appState, String walletId) async {
    final ActivityExtras extras;
    try {
      extras = await _sources.load(
        walletId,
        _flags(appState),
        walletName: appState.activeWalletName,
      );
    } catch (_) {
      return;
    }
    if (mounted) setState(() => _extras = extras);
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final version = _appState?.syncVersion ?? 0;
    if (version == _lastSyncVersion || !mounted) return;
    _lastSyncVersion = version;
    _load();
  }

  Future<void> _load() async {
    final appState = context.read<AppState>();
    final walletId = appState.activeWalletId ?? 'wallet-1';
    final extras = _loadExtras(appState, walletId);
    // A bridge failure must not strand the spinner; cached rows (if any)
    // keep showing, otherwise the error card takes over.
    final List<Transaction> txs;
    try {
      // One row per Liquid transaction, not one per asset it moved.
      txs = foldLiquidLegs(await _bridge.listActivity(walletId));
    } catch (e) {
      if (mounted && appState.cachedTransactions == null) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
      return;
    }
    // A just-broadcast consolidation is in no node's answer yet — BDK only
    // learns about it on the next sync. Without this the coins vanish from
    // UTXOs while Activity shows nothing at all, which reads as a lost
    // transaction.
    final withConsolidations = await _withPendingConsolidations(walletId, txs);
    final bumped = await _withFeeBumps(walletId, withConsolidations);
    final merged = await _withPegLabels(walletId, bumped);
    if (mounted) {
      appState.cachedTransactions = merged;
      setState(() {
        _txs = merged;
        _loading = false;
        _error = null;
      });
      _scheduleOpen();
    }
    await extras;
    if (mounted) _scheduleOpen();
  }

  /// Names the transactions of a peg ("Peg-in deposit", "Peg-in claim", …)
  /// from the local index the Peg screen keeps; no server is asked. A note
  /// the engine already has wins.
  Future<List<Transaction>> _withPegLabels(
    String walletId,
    List<Transaction> txs,
  ) async {
    final Map<String, String> labels;
    try {
      labels = await PegTxLabelStore.instance.labelsFor(walletId);
    } catch (_) {
      return txs;
    }
    if (labels.isEmpty) return txs;
    return [
      for (final tx in txs)
        switch (labels[tx.txid]) {
          final label? when tx.note == null => tx.withNote(label),
          _ => tx,
        },
    ];
  }

  /// Folds every fee bump this app made into the transaction it was done
  /// to (fee_bump_fold.dart): a sped-up payment is one row, not a payment
  /// and its child, or a payment and its replacement.
  Future<List<Transaction>> _withFeeBumps(
    String walletId,
    List<Transaction> txs,
  ) async {
    final List<FeeBumpRecord> records;
    try {
      records = await FeeBumpStore.instance.listFor(walletId);
    } catch (_) {
      return txs;
    }
    return foldFeeBumps(txs, records);
  }

  /// Prepends rows for consolidations the wallet engine has not caught up
  /// with. Once a sync returns the real transaction the placeholder is
  /// dropped, because the txid is then already in [txs].
  Future<List<Transaction>> _withPendingConsolidations(
    String walletId,
    List<Transaction> txs,
  ) async {
    final List<PendingConsolidation> pending;
    try {
      pending = await PendingConsolidationStore.instance.listAllFor(walletId);
    } catch (_) {
      return txs;
    }
    if (pending.isEmpty) return txs;
    final known = txs.map((t) => t.txid).toSet();
    final extra =
        pending
            .where((p) => !known.contains(p.txid))
            .map(
              (p) => Transaction(
                txid: p.txid,
                direction: TxDirection.self,
                chain: p.chainKey == 'liquid'
                    ? TxChain.liquid
                    : TxChain.bitcoin,
                // Approximate: the real output is the inputs minus the fee, and
                // the exact figure only exists once the tx confirms.
                amount: '~${p.displayAmount}',
                ticker: p.ticker ?? 'BTC',
                timestamp: p.startedAt,
                confirmations: 0,
                note: p.activityNote,
              ),
            )
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return [...extra, ...txs];
  }

  /// The kind filter's value, dropped when its kind is switched off.
  ActivityKind? _effectiveKind(ActivitySourceFlags flags) =>
      flags.kinds.contains(_kindFilter) ? _kindFilter : null;

  bool _hasFilter(ActivitySourceFlags flags) =>
      _chainFilter != 'all' ||
      _effectiveKind(flags) != null ||
      _searchController.text.isNotEmpty;

  /// Payments, loans, swaps and pegs in one list: an on-chain transaction
  /// that another entry owns (same txid) is folded into it. Only the
  /// sources the wallet has right now count, so switching a module off
  /// hides its rows at once.
  ActivityTimeline _timeline(ActivitySourceFlags flags) {
    final kinds = flags.kinds.toSet();
    return mergeActivity(_txs, [
      for (final e in _extras.entries)
        if (kinds.contains(e.kind)) e,
    ]);
  }

  /// Day sections over the filtered timeline: "Pending" first, then
  /// "Today", "Yesterday", "12 Sep 2026", and "Undated" last.
  List<({String label, List<ActivityEntry> entries})> _grouped(
    ActivityTimeline timeline,
    ActivitySourceFlags flags,
  ) => groupActivity(
    filterActivity(
      timeline.entries,
      chain: _chainFilter,
      kind: _effectiveKind(flags),
      query: _searchController.text,
    ),
  );

  Future<void> _startFeeBump(Transaction tx, {required bool cancel}) async {
    final available = cancel ? tx.canCancel : tx.canSpeedUp;
    if (!available) {
      final reason =
          tx.feeBumpUnavailableReason ??
          (cancel
              ? 'This transaction cannot be cancelled with RBF'
              : 'This transaction cannot be sped up with RBF or CPFP');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    final appState = context.read<AppState>();
    final walletId = appState.activeWalletId ?? 'wallet-1';
    final preview = await showFeeBumpDialog(
      context,
      bridge: _bridge,
      walletId: walletId,
      transaction: tx,
      cancel: cancel,
    );
    if (preview == null || !mounted) return;

    final type = (appState.activeWalletType ?? '').toLowerCase();
    if (type == 'watch-only') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This watch-only wallet cannot sign transactions'),
        ),
      );
      return;
    }

    if (type.contains('air-gap') || type.contains('airgap')) {
      _showFeeBumpHandoff(walletId, preview, preview.psbtBase64);
      return;
    }
    if (appState.isActiveWalletHardware) {
      await _runHardwareFeeBump(walletId, tx, preview);
      return;
    }
    if (type.contains('multisig') || type.contains('policy')) {
      await _runCoordinatedFeeBump(walletId, tx, preview);
      return;
    }

    final txid = await showPsbtSignFlow(
      context,
      walletId: walletId,
      unsignedPsbt: preview.psbtBase64,
      title: preview.isCancel ? 'Review cancellation' : 'Review fee bump',
      summary: _feeBumpSummary(preview),
      bridge: _bridge,
    );
    if (txid != null && mounted) {
      await _finishFeeBump(walletId, tx, preview, txid);
    }
  }

  Future<void> _runHardwareFeeBump(
    String walletId,
    Transaction tx,
    FeeBumpPreview preview,
  ) async {
    final appState = context.read<AppState>();
    final device = await showHwDevicePickerDialog(
      context,
      expectedFingerprint: fingerprintFromTypeLabel(appState.activeWalletType),
      title: 'Connect your device to sign',
      confirmLabel: 'Continue',
    );
    if (device == null || !mounted) return;
    setState(() => _feeBumpBusyTxid = tx.txid);
    final txid = await showLedgerSigningDialog(
      context,
      verifyTask: () => _bridge.verifyHwAddress(walletId),
      // The address `verify_hw_address` puts on the device: the wallet's
      // current receive address (the engine reads the same one).
      verifyAddress: () async =>
          (await _bridge.generateReceiveAddress(walletId, 'BTC')).address,
      task: () async {
        final signed = await _bridge.signPsbtHw(
          device.fingerprint,
          preview.psbtBase64,
        );
        return _bridge.broadcastSignedPsbt(
          walletId: walletId,
          psbtBase64: signed,
        );
      },
      formatError: friendlyHwError,
    );
    if (!mounted) return;
    setState(() => _feeBumpBusyTxid = null);
    if (txid != null) await _finishFeeBump(walletId, tx, preview, txid);
  }

  Future<void> _runCoordinatedFeeBump(
    String walletId,
    Transaction tx,
    FeeBumpPreview preview,
  ) async {
    final allowed = await showSpendPasswordGate(
      context,
      message:
          'Templar is about to add this wallet\'s signature to the '
          'fee-bump PSBT. Nothing is broadcast until the policy is complete.',
    );
    if (!allowed || !mounted) return;
    setState(() => _feeBumpBusyTxid = tx.txid);
    try {
      final signed = await _bridge.signPsbt(walletId, preview.psbtBase64);
      final inspection = await _bridge.inspectPsbt(signed);
      if (!mounted) return;
      setState(() => _feeBumpBusyTxid = null);
      _showFeeBumpHandoff(
        walletId,
        preview,
        signed,
        have: inspection.sigsPresent,
        needed: inspection.sigsRequired,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _feeBumpBusyTxid = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _showFeeBumpHandoff(
    String walletId,
    FeeBumpPreview preview,
    String psbt, {
    int? have,
    int? needed,
  }) {
    showAppDialog<void>(
      context,
      builder: (ctx) => PsbtHandoffSheet(
        unsignedPsbt: psbt,
        title: preview.isCancel ? 'Cancellation PSBT' : 'Fee-bump PSBT',
        progressNote: have == null
            ? _feeBumpSummary(preview)
            : '${_feeBumpSummary(preview)} · $have of ${needed ?? '?'} signatures collected',
        quorumHave: have,
        quorumNeeded: needed,
        onBroadcast: (signed) =>
            _broadcastFeeBump(ctx, walletId, preview, signed),
      ),
    );
  }

  Future<void> _broadcastFeeBump(
    BuildContext dialogContext,
    String walletId,
    FeeBumpPreview preview,
    String signedPsbt,
  ) async {
    Navigator.of(dialogContext).pop();
    setState(() => _feeBumpBusyTxid = preview.originalTxid);
    try {
      final txid = await _bridge.broadcastSignedPsbt(
        walletId: walletId,
        psbtBase64: signedPsbt,
      );
      Transaction? original;
      for (final tx in _txs) {
        if (tx.txid == preview.originalTxid) {
          original = tx;
          break;
        }
      }
      if (!mounted) return;
      await _finishFeeBump(
        walletId,
        original ?? _fallbackOriginal(preview.originalTxid),
        preview,
        txid,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _feeBumpBusyTxid = null);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Transaction _fallbackOriginal(String txid) => Transaction(
    txid: txid,
    direction: TxDirection.outgoing,
    chain: TxChain.bitcoin,
    amount: '—',
    ticker: 'BTC',
    timestamp: DateTime.now(),
    confirmations: 0,
  );

  static String _feeBumpSummary(FeeBumpPreview p) =>
      '${p.method.toUpperCase()} · ${p.oldFeeRate.toStringAsFixed(2)} → '
      '${p.effectiveFeeRate.toStringAsFixed(2)} sat/vB · '
      '+${p.extraFeeSats} sats';

  Future<void> _finishFeeBump(
    String walletId,
    Transaction original,
    FeeBumpPreview preview,
    String replacementTxid,
  ) async {
    final appState = context.read<AppState>();
    await FeeBumpStore.instance.add(
      FeeBumpRecord(
        walletId: walletId,
        originalTxid: original.txid,
        replacementTxid: replacementTxid,
        method: preview.method,
        targetFeeRate: preview.effectiveFeeRate,
        newFeeSats: preview.newFeeSats,
        newFeeRate: preview.newFeeRate,
        createdAt: DateTime.now(),
      ),
    );
    appState.cachedTransactions = null;
    try {
      await _bridge.syncWallet(walletId);
    } catch (_) {
      // Broadcast succeeded. The local relationship store keeps the new tx
      // visible until a later sync can replace its placeholder with chain data.
    }
    if (!mounted) return;
    setState(() => _feeBumpBusyTxid = null);
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          preview.isCancel
              ? 'Cancellation replacement broadcast'
              : '${preview.method.toUpperCase()} transaction broadcast',
        ),
      ),
    );
  }

  void _clearFilters() => setState(() {
    _chainFilter = 'all';
    _kindFilter = null;
    _searchController.clear();
  });

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final flags = _flags(st);
    final timeline = _timeline(flags);
    final grouped = _grouped(timeline, flags);
    final useSats = st.useSats;
    final phone = AppSpacing.isPhone(context);
    final pad = AppSpacing.pagePadding(context);
    final kinds = flags.kinds;
    final kind = _effectiveKind(flags);

    // Payments only: no kind filter, the page is what it always was.
    final Widget? kindFilter = kinds.length < 2
        ? null
        : phone
        // A chip row that scrolls sideways: five 48 dp chips do not fit
        // a phone's width, and a squeezed segmented track would cut them.
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final k in <ActivityKind?>[null, ...kinds]) ...[
                  if (k != null) const SizedBox(width: AppSpacing.sm),
                  ChoiceTile(
                    label: k?.filterLabel ?? 'All',
                    selected: kind == k,
                    onSelected: () => setState(() => _kindFilter = k),
                  ),
                ],
              ],
            ),
          )
        : SegmentedSwitch<ActivityKind?>(
            selected: kind,
            onChanged: (v) => setState(() => _kindFilter = v),
            options: [
              const SegOption(value: null, label: 'All'),
              for (final k in kinds) SegOption(value: k, label: k.filterLabel),
            ],
          );

    // A source that failed is named, so a missing row is not mistaken for
    // a missing event.
    final s = AppScheme.of(context);
    final failed = [
      for (final f in _extras.failed)
        if (_sourceShown(f, flags)) f,
    ];
    final Widget? failedNote = failed.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.info_outlined,
                  size: AppSpacing.iconSmall,
                  color: s.inkSecondary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Could not load ${failed.join(', ')}',
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ),
                GhostButton(label: 'Retry', onPressed: _retryExtras),
              ],
            ),
          );

    final chainFilter = ChainSwitch<String>(
      selected: _chainFilter,
      onChanged: (v) => setState(() => _chainFilter = v),
      all: 'all',
      bitcoin: 'bitcoin',
      liquid: 'liquid',
      bitcoinEnabled: st.activeWalletBitcoin,
      liquidEnabled: st.activeWalletLiquid,
      expand: phone,
    );

    final search = _SearchField(
      controller: _searchController,
      onChanged: () => setState(() {}),
    );

    // Title, privacy eye and the chain filter; the search under them with
    // the kind filter at its right. On a phone each control takes its own
    // full-width row under the title: chain, kinds, search.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Activity',
          actions: [const PrivacyToggle(), if (!phone) chainFilter],
        ),
        if (phone) ...[
          chainFilter,
          const SizedBox(height: AppSpacing.md),
          if (kindFilter != null) ...[
            kindFilter,
            const SizedBox(height: AppSpacing.md),
          ],
          search,
        ] else
          Row(
            children: [
              Expanded(child: search),
              if (kindFilter != null) ...[
                const SizedBox(width: AppSpacing.md),
                kindFilter,
              ],
            ],
          ),
        ?failedNote,
      ],
    );

    Widget row(ActivityEntry e) => switch (e) {
      PaymentEntry(:final tx) => _TxRow(
        tx: tx,
        useSats: useSats,
        onTap: () => _showDetail(context, tx),
        showPendingActions: !tx.isConfirmed && tx.chain == TxChain.bitcoin,
        onSpeedUp: tx.canSpeedUp
            ? () => _startFeeBump(tx, cancel: false)
            : null,
        onCancel: tx.canCancel ? () => _startFeeBump(tx, cancel: true) : null,
        unavailableReason: tx.feeBumpUnavailableReason,
        busy: _feeBumpBusyTxid == tx.txid,
      ),
      _ => ActivityEntryRow(
        entry: e,
        useSats: useSats,
        onTap: () => _showEntryDetail(context, e, timeline.linked),
      ),
    };

    Widget section(int i) {
      final g = grouped[i];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          ListSectionLabel(label: g.label),
          ListCard(children: [for (final e in g.entries) row(e)]),
        ],
      );
    }

    final Widget? state = _loading
        ? null
        : _error != null
        ? _LoadError(message: _error!, onRetry: _retry)
        : grouped.isEmpty
        ? _EmptyState(filtered: _hasFilter(flags), onClear: _clearFilters)
        : null;

    // One scroll view: the header scrolls away with the list, so with the
    // keyboard up for a txid search the rows keep most of the screen. It is
    // the depth-0 vertical scrollable, which is what the phone shell's
    // scroll-to-top listens for.
    return Scaffold(
      body: PageBackground.flat(
        child: CustomScrollView(
          keyboardDismissBehavior: phone
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
              sliver: SliverToBoxAdapter(child: header),
            ),
            if (_loading)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.xl),
                sliver: const SliverToBoxAdapter(child: _LoadingList()),
              )
            else if (state != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(padding: EdgeInsets.all(pad), child: state),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.xxl),
                sliver: SliverList.builder(
                  itemCount: grouped.length,
                  itemBuilder: (context, i) => section(i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _sourceShown(String source, ActivitySourceFlags flags) =>
      flags.kinds.contains(ActivitySources.kindOf(source));

  void _retryExtras() {
    final appState = context.read<AppState>();
    final walletId = appState.activeWalletId;
    if (walletId == null) return;
    _loadExtras(appState, walletId);
  }

  /// A loan's, a swap's or a peg's detail, on the same material as a
  /// payment's. A pending Bitcoin transaction folded into it keeps its
  /// "Speed up".
  void _showEntryDetail(
    BuildContext context,
    ActivityEntry entry,
    Map<String, Transaction> linked,
  ) {
    final appState = context.read<AppState>();
    Transaction? bumpable;
    for (final txid in entry.txids) {
      final tx = linked[txid];
      if (tx != null &&
          !tx.isConfirmed &&
          tx.chain == TxChain.bitcoin &&
          tx.canSpeedUp) {
        bumpable = tx;
        break;
      }
    }
    final target = activityManageTarget(entry);
    showAppDialog<void>(
      context,
      builder: (ctx) => ActivityEntryDetail(
        entry: entry,
        useSats: appState.useSats,
        btcExplorerUrl: appState.btcExplorerBase,
        liquidExplorerUrl: appState.liquidExplorerBase,
        linked: linked,
        onManage: () {
          Navigator.of(ctx).pop();
          context.go(target.route);
        },
        onSpeedUp: bumpable != null && _feeBumpBusyTxid != bumpable.txid
            ? () {
                Navigator.of(ctx).pop();
                _startFeeBump(bumpable!, cancel: false);
              }
            : null,
      ),
    );
  }

  /// The detail: a dialog on desktop, a sheet over everything on a phone
  /// (root navigator, so the tab bar does not stay live under it).
  void _showDetail(BuildContext context, Transaction tx) {
    final appState = context.read<AppState>();
    final canBump =
        !tx.isConfirmed && tx.chain == TxChain.bitcoin && tx.canSpeedUp;
    showAppDialog<void>(
      context,
      builder: (ctx) => _TxDetail(
        tx: tx,
        useSats: appState.useSats,
        btcExplorerUrl: appState.btcExplorerBase,
        liquidExplorerUrl: appState.liquidExplorerBase,
        onSpeedUp: canBump && _feeBumpBusyTxid != tx.txid
            ? () {
                Navigator.of(ctx).pop();
                _startFeeBump(tx, cancel: false);
              }
            : null,
      ),
    );
  }
}

// ── Amounts ───────────────────────────────────────────────────────────────────

/// The true minus sign: a hyphen is narrower than a digit and breaks a
/// tabular column.
const String _minus = '−';

/// One number format for the whole list. A bitcoin amount (BTC, LBTC, sats)
/// is re-written in the user's unit — eight decimals or grouped sats; an
/// issued asset keeps the figure and ticker the engine gave, since only the
/// engine knows its precision. Incoming carries `+`, outgoing `−`.
String formatTxAmount(Transaction tx, {required bool useSats}) =>
    _formatAmount(tx.amount, tx.ticker, tx.direction, tx.chain, useSats);

/// The same format for another asset the transaction moved.
String formatLegAmount(
  TxLeg leg, {
  required TxChain chain,
  required bool useSats,
}) => _formatAmount(leg.amount, leg.ticker, leg.direction, chain, useSats);

/// A fee in the user's unit: `33 sats`, `0.00000033 LBTC`.
String formatTxFee(Transaction tx, {required bool useSats}) {
  final sats = tx.feeSats;
  if (sats == null) return tx.fee ?? '—';
  return PriceService.formatUnit(
    sats,
    sat: useSats,
    coin: tx.chain == TxChain.liquid ? 'LBTC' : 'BTC',
  );
}

String _formatAmount(
  String amount,
  String ticker,
  TxDirection direction,
  TxChain chain,
  bool useSats,
) {
  var raw = amount.trim();
  if (raw.isEmpty) return '—';
  var approx = '';
  if (raw.startsWith('~')) {
    approx = '~';
    raw = raw.substring(1).trim();
  }
  var sign = '';
  if (raw.startsWith('+')) {
    sign = '+';
    raw = raw.substring(1).trim();
  } else if (raw.startsWith('-') || raw.startsWith(_minus)) {
    sign = _minus;
    raw = raw.substring(1).trim();
  }
  // A figure with no digits ('—' on a placeholder) has nothing to sign.
  if (!raw.contains(RegExp(r'\d'))) return '$approx$raw';
  sign = switch (direction) {
    TxDirection.incoming => '+',
    TxDirection.outgoing => _minus,
    TxDirection.self => sign,
  };
  final space = raw.lastIndexOf(' ');
  final number = (space < 0 ? raw : raw.substring(0, space)).trim();
  final unit = space < 0 ? ticker : raw.substring(space + 1).trim();
  final coin = chain == TxChain.liquid ? 'LBTC' : 'BTC';
  final sats = bitcoinAmountSats('$number $unit');
  final body = sats == null
      ? '$number $unit'
      : PriceService.formatUnit(
          sats,
          sat: useSats,
          coin: unit.toUpperCase() == 'SAT' || unit.toUpperCase() == 'SATS'
              ? coin
              : unit,
        );
  return '$approx$sign$body';
}

// ── Search ────────────────────────────────────────────────────────────────────

/// The search: a short placeholder, and what it searches in the tooltip
/// and the semantic label. 36 tall and at most 320 wide on desktop; the
/// full column, with a clear button and a search key, on a phone.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final VoidCallback onChanged;

  static const String _what = 'Search by txid, note, asset, loan or order';

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final field = TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      enableSuggestions: false,
      style: AppTypography.bodyOf(context).copyWith(color: s.ink),
      decoration: InputDecoration(
        hintText: 'Search',
        isDense: !phone,
        contentPadding: phone
            ? null
            : const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
        prefixIcon: Icon(
          Icons.search_outlined,
          size: phone ? AppSpacing.icon : AppSpacing.iconSmall,
          color: s.inkSecondary,
        ),
        prefixIconConstraints: phone
            ? null
            : const BoxConstraints(
                minWidth: AppSpacing.controlHeight,
                minHeight: AppSpacing.controlHeight,
              ),
        suffixIcon: !phone || controller.text.isEmpty
            ? null
            : IconButton(
                icon: Icon(
                  Icons.close_outlined,
                  size: AppSpacing.icon,
                  color: s.inkSecondary,
                ),
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged();
                },
              ),
      ),
      onChanged: (_) => onChanged(),
    );
    final labelled = Semantics(label: _what, textField: true, child: field);
    if (phone) return labelled;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: SizedBox(
          height: AppSpacing.controlHeight,
          child: Tooltip(message: _what, child: labelled),
        ),
      ),
    );
  }
}

// ── Load failure ──────────────────────────────────────────────────────────────
// Shown only when the load failed and there is no cached history to fall
// back on — an empty list is NOT an error and keeps its own message.

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: AppSpacing.icon, color: s.danger),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Could not load activity',
              style: AppTypography.sectionTitle.copyWith(color: s.ink),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.body.copyWith(color: s.inkSecondary),
              textAlign: TextAlign.center,
              // A raw FFI error can run for paragraphs; on a phone it must
              // not push the Retry button under the tab bar.
              maxLines: phone ? 6 : null,
              overflow: phone ? TextOverflow.ellipsis : null,
            ),
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: 'Retry',
              icon: Icons.refresh_outlined,
              onPressed: onRetry,
              isFullWidth: phone,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
// Tells "no transactions yet" apart from "nothing matches the filter", and
// offers the way on from each.

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClear});
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            filtered ? 'Nothing matches' : 'No activity yet',
            style: AppTypography.bodyOf(
              context,
            ).copyWith(color: s.inkSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          if (filtered)
            GhostButton(label: 'Clear filters', onPressed: onClear)
          else
            SecondaryButton(
              label: 'Receive',
              icon: Icons.call_received_outlined,
              onPressed: () => context.go(AppRoutes.receive),
            ),
        ],
      ),
    );
  }
}

// ── Loading ───────────────────────────────────────────────────────────────────

/// Quiet placeholders in the list's shape: a label, a card, rows with a
/// tile, two lines and an amount. Still — the wait is short and a shimmer
/// would be motion that states nothing.
class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
    );
    return Semantics(
      label: 'Loading activity',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.xl),
          bar(64, AppSpacing.md),
          const SizedBox(height: AppSpacing.md),
          ListCard(
            children: [
              for (var i = 0; i < 4; i++)
                SizedBox(
                  height: phone ? _rowHeightPhone : _rowHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: kListPad),
                    child: Row(
                      children: [
                        bar(kListTile, kListTile),
                        const SizedBox(width: kListGap),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(120, AppSpacing.md),
                              const SizedBox(height: AppSpacing.sm),
                              bar(180, AppSpacing.sm),
                            ],
                          ),
                        ),
                        bar(96, AppSpacing.md),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Transaction row ───────────────────────────────────────────────────────────

/// A row's height: 60 on desktop, 64 on a phone (a touch row clears 48 with
/// room for two lines).
const double _rowHeight = 60;
const double _rowHeightPhone = 64;

/// The row's glyph: an outlined arrow for the direction.
IconData _directionIcon(TxDirection d) => switch (d) {
  TxDirection.incoming => Icons.call_received_outlined,
  TxDirection.outgoing => Icons.arrow_outward_outlined,
  TxDirection.self => Icons.swap_horiz_outlined,
};

/// The chain's mark for the corner badge: Bitcoin's glyph for the Bitcoin
/// chain, the asset's own (teal either way) on Liquid.
String _chainTicker(Transaction tx) =>
    tx.chain == TxChain.bitcoin ? 'BTC' : tx.ticker;

/// `1,787` — a fee is money, grouped.
String _groupSats(int n) {
  final digits = n.abs().toString();
  final b = StringBuffer(n < 0 ? '−' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

/// What a row says of the bump folded into it: `CPFP · fee 1,787 sats`.
/// A cancellation is named by the row's title instead.
String? _bumpWords(FeeBump bump, {required bool withFee}) {
  if (bump.isCancel) return bump.awaitingSync ? 'Cancelling' : null;
  final fee = bump.feeSats;
  return withFee && fee != null
      ? '${bump.label} · fee ${_groupSats(fee)} sats'
      : bump.label;
}

/// The direction tile with the chain's glyph on its corner — the one place
/// a chain hue appears in the row.
class _TxGlyph extends StatelessWidget {
  const _TxGlyph({required this.tx});
  final Transaction tx;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return SizedBox.square(
      dimension: kListTile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ListIconTile(
            // Assets went both ways: neither arrow is the truth.
            icon: tx.isExchange
                ? Icons.swap_horiz_outlined
                : _directionIcon(tx.direction),
          ),
          Positioned(
            right: -AppSpacing.xs,
            bottom: -AppSpacing.xs,
            // A ring of the card's own tone keeps the badge off the tile.
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: s.panel, shape: BoxShape.circle),
              child: AssetLogo(ticker: _chainTicker(tx), size: AppSpacing.lg),
            ),
          ),
        ],
      ),
    );
  }
}

/// 6 px status dot, inline with the text it qualifies.
InlineSpan _dotSpan(Color color) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Padding(
    padding: const EdgeInsets.only(right: AppSpacing.xs),
    child: Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    ),
  ),
);

class _TxRow extends StatefulWidget {
  const _TxRow({
    required this.tx,
    required this.useSats,
    required this.onTap,
    required this.showPendingActions,
    required this.onSpeedUp,
    required this.onCancel,
    required this.unavailableReason,
    required this.busy,
  });
  final Transaction tx;
  final bool useSats;
  final VoidCallback onTap;
  final bool showPendingActions;
  final VoidCallback? onSpeedUp;
  final VoidCallback? onCancel;
  final String? unavailableReason;
  final bool busy;

  @override
  State<_TxRow> createState() => _TxRowState();
}

class _TxRowState extends State<_TxRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final tx = widget.tx;
    final isIn = tx.direction == TxDirection.incoming;
    final faint = AppTypography.caption.copyWith(color: s.inkFaint);
    final bump = tx.bump;
    // A phone's line has no room for it beside a pending state — and there
    // the filled "Sped up" under the row already says it.
    final bumpWords = bump == null || (phone && !tx.isConfirmed)
        ? null
        : _bumpWords(bump, withFee: !phone);

    // Confirmed is the normal state and needs no colour: only a wait or a
    // loss earns a dot.
    final List<InlineSpan> state;
    if (!tx.isConfirmed) {
      state = [_dotSpan(s.pending), TextSpan(text: 'Pending', style: faint)];
    } else {
      final n = tx.confirmations;
      final when = relativeTimeShort(tx.timestamp);
      state = [
        TextSpan(
          text: phone ? when : '$n confirmation${n == 1 ? '' : 's'} · $when',
          style: faint,
        ),
      ];
    }
    final subtitle = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            // Four each side on a phone: the column beside the amount holds
            // ~140 dp, and the state after the txid must not be cut.
            text: phone && tx.txid.length > 9
                ? '${tx.txid.substring(0, 4)}…'
                      '${tx.txid.substring(tx.txid.length - 4)}'
                : tx.shortTxidCompact,
            style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
          ),
          TextSpan(text: ' · ', style: faint),
          ...state,
          // The fee bump folded into this row: the double bolt, the method
          // and — where there is room — what it cost.
          if (bumpWords != null) ...[
            TextSpan(text: ' · ', style: faint),
            if (!tx.bump!.isCancel)
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: AppSpacing.xs),
                  child: DoubleBolt(size: AppSpacing.md),
                ),
              ),
            TextSpan(text: bumpWords, style: faint),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final amountColor = !tx.isConfirmed
        ? s.inkSecondary
        : (isIn ? s.success : s.ink);
    final fiat = tx.fiatEstimate;
    final amount = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: phone ? 144 : 240),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Amount(
            formatTxAmount(tx, useSats: widget.useSats),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: AppTypography.numeric.copyWith(color: amountColor),
          ),
          if (fiat != null)
            Amount(
              fiat,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            ),
          // The same transaction's other figures: every other asset it
          // moved, and the fee when that was paid in another asset than the
          // one above.
          for (final leg in tx.legs)
            Amount(
              formatLegAmount(leg, chain: tx.chain, useSats: widget.useSats),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.numericSmall.copyWith(
                color: tx.isConfirmed && leg.direction == TxDirection.incoming
                    ? s.success
                    : s.inkSecondary,
              ),
            ),
          if (tx.feeLegFolded)
            Amount(
              'Fee ${formatTxFee(tx, useSats: widget.useSats)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            ),
        ],
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          tx.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodyOf(context).copyWith(color: s.ink),
        ),
        subtitle,
        if (widget.showPendingActions && !phone) ...[
          const SizedBox(height: AppSpacing.sm),
          _PendingActions(
            tx: tx,
            onSpeedUp: widget.busy ? null : widget.onSpeedUp,
            onCancel: widget.busy ? null : widget.onCancel,
            onDetails: widget.onTap,
            unavailableReason: widget.unavailableReason,
            busy: widget.busy,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      constraints: BoxConstraints(
        minHeight: phone ? _rowHeightPhone : _rowHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      color: _down ? s.pressed : (_hover ? s.hover : Colors.transparent),
      foregroundDecoration: _focus
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: widget.showPendingActions && !phone
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  top: widget.showPendingActions && !phone ? AppSpacing.xs : 0,
                ),
                child: _TxGlyph(tx: tx),
              ),
              const SizedBox(width: kListGap),
              Expanded(child: text),
              const SizedBox(width: AppSpacing.md),
              amount,
              const SizedBox(width: AppSpacing.xs),
              Padding(
                padding: EdgeInsets.only(
                  top: widget.showPendingActions && !phone ? AppSpacing.sm : 0,
                ),
                child: Icon(
                  Icons.chevron_right_outlined,
                  size: AppSpacing.icon,
                  color: s.inkFaint,
                ),
              ),
            ],
          ),
          // On a phone the actions take the row's width under it, from the
          // text's edge: two equal 44 dp slabs instead of a cramped pair
          // beside the amount column.
          if (widget.showPendingActions && phone)
            Padding(
              padding: const EdgeInsets.only(
                left: kListTile + kListGap,
                top: AppSpacing.sm,
              ),
              child: _PendingActions(
                tx: tx,
                onSpeedUp: widget.busy ? null : widget.onSpeedUp,
                onCancel: widget.busy ? null : widget.onCancel,
                onDetails: widget.onTap,
                unavailableReason: widget.unavailableReason,
                busy: widget.busy,
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
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
          // Unconfirmed: the row breathes.
          child: PendingEdge(pending: !tx.isConfirmed, child: body),
        ),
      ),
    );
  }
}

/// The fee actions under a pending row's text.
///
/// What is offered follows what is possible. A payment that came in can
/// only be sped up by a child (CPFP) and can never be cancelled — it is not
/// ours to replace — so it shows "Speed up" alone. One of ours shows
/// "Cancel" beside it. Once the fee was raised the "Speed up" slot is the
/// filled yellow "Sped up", which opens the detail where the bump is
/// spelled out.
class _PendingActions extends StatelessWidget {
  const _PendingActions({
    required this.tx,
    required this.onSpeedUp,
    required this.onCancel,
    required this.onDetails,
    required this.unavailableReason,
    required this.busy,
  });

  final Transaction tx;
  final VoidCallback? onSpeedUp;
  final VoidCallback? onCancel;

  /// Opens the transaction's detail.
  final VoidCallback onDetails;
  final String? unavailableReason;
  final bool busy;

  String get _speedUpTip {
    if (onSpeedUp == null) {
      return unavailableReason ??
          (tx.direction == TxDirection.incoming
              ? 'CPFP is unavailable: no coin of this payment is spendable'
              : 'RBF and CPFP are unavailable');
    }
    if (tx.canRbf && tx.canCpfp) {
      return 'Raise the confirmation fee with RBF or CPFP';
    }
    return tx.canRbf
        ? 'Replace it with a higher-fee transaction (RBF)'
        : 'A child transaction pays the fee for both (CPFP)';
  }

  @override
  Widget build(BuildContext context) {
    final phone = AppSpacing.isPhone(context);
    final bump = tx.bump;
    // A fee that was raised is a state; a cancellation in flight is not a
    // speed-up, and keeps the ordinary button.
    final spedUp = bump != null && !bump.isCancel;
    final ours = tx.direction != TxDirection.incoming;

    final Widget speed = spedUp
        ? Tooltip(
            message: 'Fee raised with ${bump.label} — show details',
            child: SpedUpButton(onPressed: onDetails, isFullWidth: phone),
          )
        : Tooltip(
            message: _speedUpTip,
            child: SpeedUpButton(
              label: busy ? 'Working…' : 'Speed up',
              isLoading: busy,
              isFullWidth: phone,
              onPressed: onSpeedUp,
            ),
          );
    // Only what this wallet sent can be cancelled; an incoming payment
    // shows no Cancel at all rather than one that can never work.
    final Widget? cancel = !ours
        ? null
        : Tooltip(
            message: onCancel == null
                ? (unavailableReason ??
                      'Only replaceable outgoing transactions can be cancelled')
                : 'Attempt an RBF replacement back to your wallet',
            child: GhostButton(
              label: 'Cancel',
              isFullWidth: phone,
              onPressed: onCancel,
            ),
          );
    if (phone) {
      return Row(
        children: [
          Expanded(child: speed),
          if (cancel != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: cancel),
          ],
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [speed, ?cancel],
    );
  }
}

// ── Detail ────────────────────────────────────────────────────────────────────

/// The transaction's detail on the dialog material (a sheet on a phone):
/// the amount, its facts as key/value rows, the txid in a code box, and the
/// way out to an explorer.
class _TxDetail extends StatelessWidget {
  const _TxDetail({
    required this.tx,
    required this.useSats,
    required this.btcExplorerUrl,
    required this.liquidExplorerUrl,
    this.onSpeedUp,
  });

  final Transaction tx;
  final bool useSats;

  /// Null on a regtest: no public explorer knows the chain, so no link.
  final String? btcExplorerUrl;
  final String? liquidExplorerUrl;

  /// Opens the fee-bump flow; null when this transaction cannot take one.
  final VoidCallback? onSpeedUp;

  String? get _explorerBase =>
      tx.chain == TxChain.liquid ? liquidExplorerUrl : btcExplorerUrl;

  String _explorerUrl(String txid) {
    final base = _explorerBase!;
    final baseTrimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$baseTrimmed/tx/$txid';
  }

  /// Opens this transaction in the explorer, or [txid] — the other
  /// transaction of its fee bump.
  Future<void> _openExplorer(BuildContext context, {String? txid}) async {
    final url = _explorerUrl(txid ?? tx.txid);
    final uri = Uri.parse(url);
    // launchUrl answers false (or throws on some OEM builds and restricted
    // work profiles) when nothing can take an https VIEW intent; a silent
    // no-op there reads as a dead button, so the link goes to the clipboard
    // with a word about it.
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text("Couldn't open a browser — explorer link copied"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final isIn = tx.direction == TxDirection.incoming;
    final amountColor = !tx.isConfirmed
        ? s.inkSecondary
        : (isIn ? s.success : s.ink);
    final fiat = tx.fiatEstimate;

    final figure = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(
              formatTxAmount(tx, useSats: useSats),
              maxLines: 1,
              style: AppTypography.numericLargeOf(
                context,
              ).copyWith(color: amountColor),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        const PrivacyToggle(),
      ],
    );

    final content = SizedBox(
      width: phone ? null : 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _TxGlyph(tx: tx),
              const SizedBox(width: AppSpacing.md),
              Text(
                tx.chain == TxChain.bitcoin ? 'Bitcoin' : 'Liquid',
                style: AppTypography.body.copyWith(color: s.inkSecondary),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          figure,
          if (fiat != null)
            Amount(
              fiat,
              style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            ),
          const SizedBox(height: AppSpacing.lg),
          KvRow(
            label: 'Status',
            value: tx.isConfirmed
                ? '${tx.confirmations} confirmation'
                      '${tx.confirmations == 1 ? '' : 's'}'
                : 'Unconfirmed',
            divider: true,
          ),
          KvRow(
            label: 'Date',
            value: tx.isConfirmed ? _formatDate(tx.timestamp) : 'Pending',
            divider: true,
          ),
          KvRow(label: 'Ticker', value: tx.ticker, divider: true),
          // The other assets the same transaction moved.
          for (final leg in tx.legs)
            KvRow(
              label: leg.direction == TxDirection.incoming
                  ? 'Also received'
                  : 'Also sent',
              value: maskAmount(
                context,
                formatLegAmount(leg, chain: tx.chain, useSats: useSats),
              ),
              divider: true,
            ),
          if (tx.fee != null)
            KvRow(
              // Paid in L-BTC, whatever asset the transaction moved.
              label: tx.feeLegFolded ? 'Network fee' : 'Fee',
              value: tx.feeLegFolded
                  ? formatTxFee(tx, useSats: useSats)
                  : tx.fee!,
              divider: true,
            ),
          if (tx.feeRate != null)
            KvRow(
              label: 'Fee rate',
              value: '${tx.feeRate!.toStringAsFixed(2)} sat/vB',
              divider: true,
            ),
          if (tx.note != null)
            KvRow(label: 'Note', value: tx.note!, divider: true),
          if (tx.counterparty != null)
            KvRow(
              label: 'Counterparty',
              value: tx.counterparty!,
              divider: true,
            ),
          const SizedBox(height: AppSpacing.lg),
          CodeBox(value: tx.txid, label: 'Transaction ID'),
          // The fee bump folded into this transaction: what was done, with
          // which other transaction, and what it cost — the second txid
          // that would otherwise be a row of its own in the list.
          if (tx.bump case final bump?) ...[
            const SizedBox(height: AppSpacing.xl),
            _BumpSection(
              bump: bump,
              incoming: isIn,
              onExplorer: _explorerBase == null
                  ? null
                  : () => _openExplorer(context, txid: bump.otherTxid),
            ),
          ],
        ],
      ),
    );

    return AppDialog(
      title: Text(tx.title),
      scrollable: true,
      content: content,
      actions: [
        if (_explorerBase != null)
          GhostButton(
            label: 'View in explorer',
            icon: Icons.open_in_new_outlined,
            onPressed: () => _openExplorer(context),
          ),
        if (onSpeedUp != null)
          SpeedUpButton(
            // A replacement can be replaced again; say so.
            label: tx.bump == null ? 'Speed up' : 'Speed up again',
            dense: false,
            onPressed: onSpeedUp,
          ),
        SecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  static String _formatDate(DateTime dt) {
    const months = [
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
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} $h:$m';
  }
}

/// "Fee raised": the bump folded into a transaction, in its detail — the
/// method under the double bolt, a sentence saying what it did, what it
/// cost, and the other transaction it put on the chain.
class _BumpSection extends StatelessWidget {
  const _BumpSection({
    required this.bump,
    required this.incoming,
    required this.onExplorer,
  });

  final FeeBump bump;

  /// The bumped transaction is a payment that came in.
  final bool incoming;

  /// Opens the bump's other transaction in the explorer; null on a regtest,
  /// where no public explorer knows the chain.
  final VoidCallback? onExplorer;

  String get _headline => switch (bump.method) {
    'cpfp' => 'Fee raised with CPFP',
    'cancel' => bump.awaitingSync ? 'Cancellation sent' : 'Cancellation',
    _ => bump.awaitingSync ? 'Replacement sent (RBF)' : 'Fee raised with RBF',
  };

  String get _what {
    if (bump.isCpfp) {
      return incoming
          ? 'A child transaction spends the coin this payment sent you and '
                'pays a fee for both, so the two confirm together. The '
                'payment itself is unchanged.'
          : 'A child transaction spends this payment\'s change and pays a '
                'fee for both, so the two confirm together. The payment '
                'itself is unchanged.';
    }
    if (bump.isCancel) {
      return bump.awaitingSync
          ? 'A replacement that sends these coins back to this wallet was '
                'broadcast. It is a race: whichever confirms first stands.'
          : 'This transaction sends the coins of the cancelled payment '
                'back to this wallet.';
    }
    return bump.awaitingSync
        ? 'A replacement paying a higher fee was broadcast. It takes this '
              'transaction\'s place once the wallet has synced.'
        : 'This transaction replaced an earlier one that paid a lower fee. '
              'Same coins, same payment.';
  }

  String get _otherLabel => switch (bump.method) {
    'cpfp' => 'Child transaction',
    'cancel' =>
      bump.awaitingSync ? 'Cancelling transaction' : 'Cancelled transaction',
    _ => bump.awaitingSync ? 'Replacement' : 'Replaced transaction',
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final fee = bump.feeSats;
    final rate = bump.feeRate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (!bump.isCancel) ...[
              const DoubleBolt(size: AppSpacing.icon),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Text(
                _headline,
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _what,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.sm),
        KvRow(label: 'Method', value: bump.label, divider: true),
        if (fee != null)
          KvRow(
            label: bump.isCpfp ? 'Child fee' : 'New fee',
            value: '${_groupSats(fee)} sats',
            divider: true,
          ),
        if (rate != null)
          KvRow(
            label: bump.isCpfp ? 'Pair rate' : 'New rate',
            value: '${rate.toStringAsFixed(2)} sat/vB',
            divider: true,
          ),
        if (bump.isCpfp)
          KvRow(
            label: 'Child',
            value: bump.otherConfirmed ? 'Confirmed' : 'Unconfirmed',
            divider: true,
          ),
        const SizedBox(height: AppSpacing.md),
        CodeBox(value: bump.otherTxid, label: _otherLabel),
        if (onExplorer != null)
          Align(
            alignment: Alignment.centerRight,
            child: GhostButton(
              label: 'View in explorer',
              icon: Icons.open_in_new_outlined,
              onPressed: onExplorer,
            ),
          ),
      ],
    );
  }
}
