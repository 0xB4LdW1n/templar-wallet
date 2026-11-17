import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/address_label_store.dart';
import '../../services/pending_consolidation_store.dart';
import '../../services/price_service.dart';
import '../../services/utxo_label_store.dart';
import '../../shared/widgets/psbt_sign_flow.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/chain_switch.dart';
import '../../shared/widgets/plain_card.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../shared/widgets/privacy.dart';
import '../../shared/widgets/utxo_details.dart';
import '../../shared/widgets/utxo_views.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../receive/address_dialogs.dart' show showAddressLabelPrompt;
import 'models/pending_consolidation.dart';
import 'models/utxo.dart';
import 'utxo_wall.dart';

/// How the UTXO set is rendered.
enum UtxoViewMode { notes, list }

class UtxoScreen extends StatefulWidget {
  const UtxoScreen({super.key, this.bridge});

  /// Test seam; the app uses the global [walletBridge].
  final WalletBridge? bridge;

  @override
  State<UtxoScreen> createState() => _UtxoScreenState();
}

class _UtxoScreenState extends State<UtxoScreen> with WidgetsBindingObserver {
  static const _kViewModePref = 'pref_utxo_view_mode';

  late final WalletBridge _bridge = widget.bridge ?? walletBridge;
  List<Utxo> _utxos = [];
  bool _loading = true;
  String? _error;
  String _chain = 'BTC';

  UtxoViewMode _viewMode = UtxoViewMode.notes;
  String _sortBy = 'amount'; // 'amount' | 'label' | 'address'
  bool _sortAsc = false;

  // ── Consolidation (inline, no separate screen) ──────────────────────────
  bool _consolidateMode = false;
  bool _sending = false;
  String? _consolidateError;
  String _feePreset = 'normal'; // 'slow' | 'normal' | 'fast' | 'custom'
  final _customFeeCtrl = TextEditingController();

  /// Consolidations broadcast but not yet confirmed. Their inputs are hidden
  /// and replaced by one grey placeholder each.
  List<PendingConsolidation> _pending = [];

  /// The app state this screen follows: a finished sync bumps its
  /// `syncVersion`, and the coins are read again. Without it a payment sent
  /// a moment ago — its change, the coin it is paying in — stayed off the
  /// screen until the user left and came back.
  AppState? _appState;
  int _lastSyncVersion = 0;

  @override
  void initState() {
    super.initState();
    // A wallet without a Bitcoin side has nothing to show on the default
    // chain; open on the one it has.
    final st = context.read<AppState>();
    if (!st.activeWalletBitcoin && st.activeWalletLiquid) _chain = 'Liquid';
    _appState = st;
    _lastSyncVersion = st.syncVersion;
    st.addListener(_onAppStateChanged);
    // A phone is backgrounded for hours; the pending-consolidation poll must
    // not keep hitting Electrum from a pocket. Desktop windows stay as they
    // were.
    if (AppLayout.isMobilePlatform) WidgetsBinding.instance.addObserver(this);
    _loadViewPref();
    // The labels Receive gave this wallet's addresses: the wall's trays and
    // the list's address column show them.
    AddressLabelStore.instance.load();
    _load();
  }

  @override
  void dispose() {
    if (AppLayout.isMobilePlatform) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _appState?.removeListener(_onAppStateChanged);
    _pendingPoll?.cancel();
    _customFeeCtrl.dispose();
    super.dispose();
  }

  /// A sync finished (the footer's, or the one a broadcast starts): what
  /// the engine knows about the coins may have changed.
  void _onAppStateChanged() {
    final version = _appState?.syncVersion ?? 0;
    if (version == _lastSyncVersion || !mounted) return;
    _lastSyncVersion = version;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pendingPoll?.cancel();
        _pendingPoll = null;
      case AppLifecycleState.resumed:
        // One immediate check — a block may well have landed meanwhile —
        // then the periodic poll resumes if anything is still in flight.
        if (_pending.isNotEmpty && mounted) _load();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Re-checks the node while a consolidation is in flight. Without this the
  /// grey block would sit there until the user navigated away and back, even
  /// after the transaction confirmed.
  Timer? _pendingPoll;

  void _syncPendingPoll() {
    if (_pending.isEmpty) {
      _pendingPoll?.cancel();
      _pendingPoll = null;
      return;
    }
    // A block is ~10 minutes; a minute is responsive without hammering
    // Electrum, and each tick is the same call the screen already makes.
    _pendingPoll ??= Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _load();
    });
  }

  Future<void> _loadViewPref() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kViewModePref);
    final mode = UtxoViewMode.values.where((m) => m.name == saved).firstOrNull;
    if (mode != null && mounted) setState(() => _viewMode = mode);
  }

  Future<void> _setViewMode(UtxoViewMode mode) async {
    setState(() => _viewMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kViewModePref, mode.name);
  }

  Future<void> _load() async {
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    final List<Utxo> utxos;
    try {
      utxos = await _bridge.listUtxos(walletId, _chain);
    } catch (e) {
      // Drop coins from the previous chain — an error card floating over
      // another chain's UTXOs would misattribute them.
      if (mounted) {
        setState(() {
          _utxos = [];
          _loading = false;
          _error = e.toString();
        });
      }
      return;
    }
    // Merge persisted labels, and keep what the user had picked: a reload
    // behind a sync must not drop a selection made a second before it.
    final labels = await UtxoLabelStore.instance.getAllLabels();
    final picked = {
      for (final u in _utxos)
        if (u.isSelected) u.outpoint,
    };
    final withLabels = utxos.map((u) {
      final saved = labels[u.outpoint];
      final labelled = saved != null ? u.copyWith(label: saved) : u;
      return picked.contains(u.outpoint) && !u.isPending
          ? labelled.copyWith(isSelected: true)
          : labelled;
    }).toList();

    final pending = await _reconcilePending(walletId, withLabels);

    if (mounted) {
      setState(() {
        _utxos = _withoutPending(withLabels, pending);
        _pending = pending;
        _loading = false;
        _error = null;
      });
      _syncPendingPoll();
    }
  }

  /// Drops any consolidation whose output has landed AND confirmed, and returns
  /// the ones still in flight.
  ///
  /// Confirmation is the bar, not mere appearance: between broadcast and the
  /// first block the output shows up as unconfirmed, and swapping the
  /// placeholder for a coin that can still be replaced would be a lie.
  Future<List<PendingConsolidation>> _reconcilePending(
    String walletId,
    List<Utxo> utxos,
  ) async {
    final store = PendingConsolidationStore.instance;
    final live = await store.listFor(walletId: walletId, chain: _chain);
    final stillPending = <PendingConsolidation>[];
    for (final p in live) {
      final settled = utxos.any(
        (u) => p.isSettledBy(u.outpoint) && u.state != UtxoState.unconfirmed,
      );
      if (settled) {
        await store.remove(p.txid);
      } else {
        stillPending.add(p);
      }
    }
    return stillPending;
  }

  /// Hides the coins a pending consolidation spends, plus its own unconfirmed
  /// output — otherwise the wall would briefly show both the inputs' successor
  /// and the placeholder standing for it.
  List<Utxo> _withoutPending(
    List<Utxo> utxos,
    List<PendingConsolidation> pending,
  ) {
    if (pending.isEmpty) return utxos;
    final spent = <String>{for (final p in pending) ...p.inputs};
    return utxos
        .where(
          (u) =>
              !spent.contains(u.outpoint) &&
              !pending.any((p) => p.isSettledBy(u.outpoint)),
        )
        .toList();
  }

  void _toggle(int i) {
    // A coin still in the mempool cannot be tagged or merged; the row and
    // the note already refuse the tap, this is the belt to their braces.
    if (_utxos[i].isPending) return;
    // Merging spends, and a frozen coin is never spent: say so rather than
    // let the selection count up coins the transaction will leave behind.
    if (_consolidateMode && _utxos[i].isFrozen && !_utxos[i].isSelected) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Frozen coins are not consolidated — unfreeze it first',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(
      () => _utxos[i] = _utxos[i].copyWith(isSelected: !_utxos[i].isSelected),
    );
  }

  bool _freezing = false;

  /// Freezes [coins], or unfreezes them when [frozen] is false. The engine
  /// keeps the list; the screen reloads from it so what it shows is what
  /// the engine will enforce.
  Future<void> _setFrozen(List<Utxo> coins, {required bool frozen}) async {
    if (coins.isEmpty || _freezing) return;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    setState(() => _freezing = true);
    try {
      await _bridge.setUtxosFrozen(
        walletId: walletId,
        chain: _chain,
        outpoints: [for (final u in coins) u.outpoint],
        frozen: frozen,
      );
      if (!mounted) return;
      final n = coins.length;
      final what = n == 1 ? '1 coin' : '$n coins';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              frozen
                  ? 'Froze $what — the wallet will not spend ${n == 1 ? 'it' : 'them'}'
                  : 'Unfroze $what',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      _clearSelection();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not ${frozen ? 'freeze' : 'unfreeze'}: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _freezing = false);
    }
  }

  /// One coin, from its details sheet.
  VoidCallback _toggleFrozenOf(Utxo u) =>
      () => _setFrozen([u], frozen: !u.isFrozen);

  /// The selection's freeze action: Unfreeze when every selected coin is
  /// frozen, Freeze otherwise (freezing one that already is changes
  /// nothing).
  bool get _selectionAllFrozen =>
      _selected.isNotEmpty && _selected.every((u) => u.isFrozen);

  void _clearSelection() {
    setState(
      () => _utxos = _utxos.map((u) => u.copyWith(isSelected: false)).toList(),
    );
  }

  /// Labels every selected coin at once, from the selection bar.
  Future<void> _labelSelected() async {
    final selected = _selected;
    if (selected.isEmpty) return;
    final one = selected.length == 1 ? selected.first : null;
    final label = await showUtxoLabelPrompt(
      context,
      current: one?.label,
      count: selected.length,
      outpoint: one?.outpoint,
    );
    if (label == null || !mounted) return;
    await _applyLabel({for (final u in selected) u.outpoint}, label);
  }

  /// Labels one coin, from its note or its row.
  Future<void> _editLabel(Utxo coin) async {
    final label = await showUtxoLabelPrompt(
      context,
      current: coin.label,
      outpoint: coin.outpoint,
    );
    if (label == null || !mounted) return;
    await _applyLabel({coin.outpoint}, label);
  }

  /// Shows [label] on [outpoints] at once, then keeps it in the label
  /// store; an empty label clears it. Display metadata only: the engine
  /// never sees it.
  Future<void> _applyLabel(Set<String> outpoints, String label) async {
    final text = label.trim();
    setState(() {
      _utxos = [
        for (final u in _utxos)
          if (!outpoints.contains(u.outpoint))
            u
          else if (text.isEmpty)
            u.copyWith(clearLabel: true)
          else
            u.copyWith(label: text),
      ];
    });
    try {
      for (final outpoint in outpoints) {
        await UtxoLabelStore.instance.setLabel(outpoint, text);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Could not save the label: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  /// Enters inline consolidation mode. Selection happens directly in the
  /// active view (banknotes or list) — no separate screen.
  void _enterConsolidate() {
    setState(() {
      _consolidateMode = true;
      _consolidateError = null;
    });
  }

  void _exitConsolidate() {
    setState(() {
      _consolidateMode = false;
      _sending = false;
      _consolidateError = null;
    });
  }

  /// Only spendable coins can be consolidated.
  List<Utxo> get _spendableSelected => _selected
      .where(
        (u) => u.state == UtxoState.available || u.state == UtxoState.dusty,
      )
      .toList();

  /// Fee presets per chain. Liquid fees are near-flat and tiny; BTC varies.
  List<(String, String, String, double)> get _feePresets => _chain == 'Liquid'
      ? const [
          ('slow', 'Slow', 'min relay', 0.1),
          ('normal', 'Normal', 'standard', 0.5),
          ('fast', 'Fast', 'priority', 1.0),
        ]
      : const [
          ('slow', 'Slow', '~60 min', 1.0),
          ('normal', 'Normal', '~30 min', 3.0),
          ('fast', 'Fast', '~10 min', 8.0),
        ];

  double get _feeRate {
    if (_feePreset == 'custom') {
      return double.tryParse(_customFeeCtrl.text.trim()) ?? 0;
    }
    return _feePresets.firstWhere((p) => p.$1 == _feePreset).$4;
  }

  /// Rough vsize for n P2WPKH/P2WSH inputs → 1 output.
  int get _estFeeSats {
    final n = _spendableSelected.length;
    if (n == 0) return 0;
    final vsize = 11 + 68 * n + 31;
    return (_feeRate * vsize).round();
  }

  Future<void> _runConsolidate() async {
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    final merged = _spendableSelected;
    final outpoints = merged.map((u) => u.outpoint).toList();
    setState(() {
      _sending = true;
      _consolidateError = null;
    });
    try {
      // Two passes, never one: build the PSBT, show what it does with its QR,
      // sign it behind the app password, review the signed transaction, and
      // only then broadcast. A consolidation moves every selected coin at
      // once — it is the last thing that should happen on a single click.
      final unsigned = await _bridge.buildConsolidationPsbt(
        walletId: walletId,
        outpoints: outpoints,
        chain: _chain,
        feeRate: _feeRate,
      );
      if (!mounted) return;
      setState(() => _sending = false);
      final txid = await showPsbtSignFlow(
        context,
        walletId: walletId,
        unsignedPsbt: unsigned,
        title: 'Consolidate coins',
        summary:
            'Merging ${merged.length} coins into a single new coin of '
            'this wallet, minus the fee.',
      );
      // Cancelled at the review or the signature: nothing was broadcast, and
      // the selection stays exactly as the user left it.
      if (txid == null || !mounted) return;

      // Record BEFORE reloading: the merged coins have to disappear behind the
      // placeholder in the same frame the user sees, not after a round trip.
      final total = merged.fold<int>(0, (sum, u) => sum + u.amount);
      final pending = PendingConsolidation(
        txid: txid,
        walletId: walletId,
        chain: _chain,
        inputs: outpoints,
        amount: total,
        displayAmount: _formatSats(total),
        ticker: merged.isNotEmpty ? merged.first.ticker : null,
        startedAt: DateTime.now(),
      );
      await PendingConsolidationStore.instance.add(pending);
      if (!mounted) return;

      setState(() {
        _pending = [..._pending, pending];
        _utxos = _withoutPending(_utxos, _pending);
        _sending = false;
        _consolidateMode = false;
        _consolidateError = null;
      });
      _syncPendingPoll();

      // A blocking dialog here would hide the very thing it is announcing.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Consolidating ${merged.length} coins — '
            '${txid.substring(0, 12)}…',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _consolidateError = e.toString();
        });
      }
    }
  }

  static String _formatSats(int sats) {
    if (sats >= 100000000) return '${(sats / 1e8).toStringAsFixed(8)} BTC';
    return '$sats sats';
  }

  List<Utxo> get _selected => _utxos.where((u) => u.isSelected).toList();

  /// Share/tier math is shared with [UtxoPicker] (utxo_views.dart).
  Map<String, int> get _assetTotals => utxoAssetTotals(_utxos);

  double _shareOf(Utxo u) => utxoShareOf(u, _assetTotals);

  /// How many coins are still on their way in.
  int get _pendingCount => _utxos.where((u) => u.isPending).length;

  /// How many coins the user froze.
  int get _frozenCount => _utxos.where((u) => u.isFrozen).length;

  /// What the address column sorts on: an address the user named leads, by
  /// its name; the rest follow by the address itself, and coins with no
  /// address come last. Coins on one address always end up together.
  static String _addressSortKey(Utxo u) {
    final a = u.address;
    if (a == null || a.isEmpty) return '\u{10FFFF}';
    final name = AddressLabelStore.instance.labelFor(a);
    return name == null ? '\u{FFFF}$a' : '${name.toLowerCase()}\u0000$a';
  }

  /// UTXOs ordered for the table view by the active sort column. Coins that
  /// have not confirmed lead whatever the sort: they are the newest thing
  /// that happened to this wallet, the same place Activity puts them.
  List<int> get _sortedIndices {
    final idx = List<int>.generate(_utxos.length, (i) => i);
    int cmp(Utxo a, Utxo b) => switch (_sortBy) {
      'label' => (a.label ?? '').compareTo(b.label ?? ''),
      'address' => _addressSortKey(a).compareTo(_addressSortKey(b)),
      _ => a.amount.compareTo(b.amount),
    };
    idx.sort((a, b) {
      final ua = _utxos[a];
      final ub = _utxos[b];
      if (ua.isPending != ub.isPending) return ua.isPending ? -1 : 1;
      final c = cmp(ua, ub);
      // Equal on the sorted column (two coins on one address, two with no
      // label): the larger first, so the order never depends on the sort's
      // whim.
      if (c == 0) return ub.amount.compareTo(ua.amount);
      return _sortAsc ? c : -c;
    });
    return idx;
  }

  /// One coin on the wall: a provisional dashed note while it is pending, a
  /// banknote as long as its tier once it has confirmed.
  Widget _wallNote(int i) {
    final u = _utxos[i];
    final share = _shareOf(u);
    if (u.isPending) return PendingCoinNote(utxo: u, share: share);
    return UtxoBanknote(
      utxo: u,
      tier: utxoTier(u, share),
      share: share,
      onTap: () => _toggle(i),
      onToggleFrozen: _toggleFrozenOf(u),
      onEditLabel: () => _editLabel(u),
    );
  }

  /// Labels the address a coin sits on, from its tray or its list cell.
  void _editAddressLabel(String address) =>
      showAddressLabelPrompt(context, address: address);

  void _setSort(String by) {
    setState(() {
      if (_sortBy == by) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = by;
        _sortAsc = false;
      }
    });
  }

  // ── View modes ─────────────────────────────────────────────────────────────

  /// Desktop: the wall. A card per address, the coins that sit on it as
  /// the notes inside it. The fullest address leads, and a consolidation in
  /// flight comes before them all.
  Widget _notesView() {
    final pad = AppSpacing.pagePadding(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, pad),
      child: ListenableBuilder(
        // A label written here or on Receive lands on its tray at once.
        listenable: AddressLabelStore.instance,
        builder: (context, _) => AddressCards(
          children: [
            // In-flight consolidations first: they are the most recent
            // thing the user did, and the coins they replace are gone
            // from the wall.
            for (final p in _pending)
              ConsolidationTray(
                count: p.count,
                displayAmount: p.displayAmount,
                txid: p.txid,
              ),
            for (final g in groupCoinsByAddress(_utxos))
              AddressTray(
                key: ValueKey(g.address ?? ''),
                address: g.address,
                notes: [for (final i in g.indices) _wallNote(i)],
                count: g.indices.length,
                total: _groupTotal(context, g),
                onEditLabel: g.address == null
                    ? null
                    : () => _editAddressLabel(g.address!),
              ),
          ],
        ),
      ),
    );
  }

  /// What the coins on one address add up to, masked like every amount;
  /// null when they are not one asset.
  String? _groupTotal(BuildContext context, AddressGroup g) {
    final sum = coinSumText([for (final i in g.indices) _utxos[i]]);
    return sum == null ? null : maskAmount(context, sum);
  }

  /// Desktop: one card with a table head, consolidations in flight and
  /// pending coins leading the rows.
  Widget _listView() {
    final pad = AppSpacing.pagePadding(context);
    final showShare = _chain != 'Liquid';
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, AppSpacing.xl),
      children: [
        Reveal(
          child: ListenableBuilder(
            // The address column prints the labels, the amount column the
            // fiat value: both redraw when theirs changes.
            listenable: Listenable.merge([
              AddressLabelStore.instance,
              PriceService.instance,
            ]),
            builder: (context, _) => CoinListCard(
              header: CoinTableHeader(
                sortBy: _sortBy,
                sortAsc: _sortAsc,
                onSort: _setSort,
                showShare: showShare,
              ),
              children: [
                for (final p in _pending)
                  ConsolidatingCoinRow(
                    count: p.count,
                    displayAmount: p.displayAmount,
                    txid: p.txid,
                    compact: false,
                  ),
                for (final i in _sortedIndices)
                  CoinRow(
                    utxo: _utxos[i],
                    share: _shareOf(_utxos[i]),
                    // Shares across mixed Liquid assets read as noise: a
                    // wall of "100%" for single-coin tokens says nothing.
                    showShare: showShare,
                    onTap: () => _toggle(i),
                    compact: false,
                    onToggleFrozen: _toggleFrozenOf(_utxos[i]),
                    onEditLabel: () => _editLabel(_utxos[i]),
                    onEditAddressLabel: _utxos[i].address == null
                        ? null
                        : () => _editAddressLabel(_utxos[i].address!),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Phone: the coins grouped by the address they sit on — a card per
  /// address, its coins as the rows under its head. The row opens the coin's
  /// details, the checkbox selects it, the head labels the address.
  /// [bottom] keeps the last row clear of the selection bar.
  Widget _phoneList({required double bottom}) {
    final pad = AppSpacing.pagePadding(context);
    final showShare = _chain != 'Liquid';
    // The active sort orders the coins inside each address; the addresses
    // themselves go fullest first, as the trays do on the wall.
    final order = _sortedIndices;
    final rank = {for (var n = 0; n < order.length; n++) order[n]: n};
    final groups = groupCoinsByAddress(_utxos);
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.sm, pad, bottom),
      children: [
        Reveal(
          child: ListenableBuilder(
            // A label or a colour given here or on Receive lands at once.
            listenable: AddressLabelStore.instance,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_pending.isNotEmpty) ...[
                  CoinListCard(
                    children: [
                      for (final p in _pending)
                        ConsolidatingCoinRow(
                          count: p.count,
                          displayAmount: p.displayAmount,
                          txid: p.txid,
                          compact: true,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                AddressCards(
                  children: [
                    for (final g in groups)
                      AddressCoinGroup(
                        key: ValueKey(g.address ?? ''),
                        address: g.address,
                        rowInset: kPhoneCoinTextInset,
                        count: g.indices.length,
                        total: _groupTotal(context, g),
                        onEditLabel: g.address == null
                            ? null
                            : () => _editAddressLabel(g.address!),
                        rows: [
                          for (final i in [
                            ...g.indices,
                          ]..sort((a, b) => rank[a]!.compareTo(rank[b]!)))
                            CoinRow(
                              utxo: _utxos[i],
                              share: _shareOf(_utxos[i]),
                              showShare: showShare,
                              onTap: () => _toggle(i),
                              compact: true,
                              tapOpensDetails: true,
                              onToggleFrozen: _toggleFrozenOf(_utxos[i]),
                              onEditLabel: () => _editLabel(_utxos[i]),
                            ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _switchChain(String chain) {
    setState(() {
      _chain = chain;
      _loading = true;
      _error = null;
      // Consolidate mode is chain-specific (and Liquid never offers it).
      _consolidateMode = false;
      _sending = false;
      _consolidateError = null;
    });
    _load();
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _load();
  }

  /// The one quiet line under the title: what is on screen, or what is
  /// selected once something is.
  String _summary(
    BuildContext context, {
    bool withStates = true,
    bool followSelection = true,
  }) {
    if (followSelection && _selected.isNotEmpty) {
      return _selectionSummary(context);
    }
    final n = _utxos.length;
    final sum = coinSumText(_utxos);
    return [
      n == 1 ? '1 coin' : '$n coins',
      if (withStates && _pendingCount > 0) '$_pendingCount pending',
      if (withStates && _frozenCount > 0) '$_frozenCount frozen',
      if (sum != null) maskAmount(context, sum),
    ].join(' · ');
  }

  String _selectionSummary(BuildContext context) {
    final selected = _selected;
    final sum = coinSumText(selected);
    return [
      '${selected.length} selected',
      if (sum != null) maskAmount(context, sum),
    ].join(' · ');
  }

  /// Consolidation merges spendable coins, two at least; BTC only — the
  /// backend rejects it for Liquid.
  bool get _canConsolidate =>
      _chain != 'Liquid' && !_consolidateMode && _spendableSelected.length >= 2;

  String get _consolidateTip => _canConsolidate
      ? 'Merge the selected coins into one'
      : 'Select at least two spendable coins';

  /// What fills the space under the header: a spinner, the load error, the
  /// empty line, or [coins].
  Widget _body(Widget Function() coins) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _LoadError(message: _error!, onRetry: _retry);
    if (_utxos.isEmpty && _pending.isEmpty) return const _EmptyCoins();
    return coins();
  }

  @override
  Widget build(BuildContext context) {
    // A chain the wallet lacks has no switch at all: asking the bridge for
    // its coins would only yield a "wallet not open" error.
    final liquidEnabled = context.select<AppState, bool>(
      (st) => st.activeWalletLiquid,
    );
    final bitcoinEnabled = context.select<AppState, bool>(
      (st) => st.activeWalletBitcoin,
    );
    final bothChains = liquidEnabled && bitcoinEnabled;
    if (AppLayout.isPhone(context)) {
      return _buildPhone(context, bothChains: bothChains);
    }
    final chainSwitch = ChainSwitch<String>(
      selected: _chain,
      onChanged: _switchChain,
      bitcoin: 'BTC',
      liquid: 'Liquid',
    );
    final pad = AppSpacing.pagePadding(context);
    return Scaffold(
      body: PageBackground.flat(
        child: Column(
          // Stretch: the wall's scroll view must span the page so the notes
          // start on the title's left edge instead of centring as a block.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
              child: PageHeader(
                title: 'UTXOs',
                subtitle: _loading || _error != null ? null : _summary(context),
                actions: [
                  if (_chain != 'Liquid')
                    Tooltip(
                      message: _consolidateTip,
                      child: SecondaryButton(
                        label: 'Consolidate',
                        onPressed: _canConsolidate ? _enterConsolidate : null,
                      ),
                    ),
                  const PrivacyToggle(),
                  if (bothChains) chainSwitch,
                  SegmentedSwitch<UtxoViewMode>(
                    selected: _viewMode,
                    onChanged: _setViewMode,
                    options: const [
                      SegOption(
                        value: UtxoViewMode.notes,
                        label: 'Notes',
                        tooltip: 'Coins as banknotes',
                      ),
                      SegOption(
                        value: UtxoViewMode.list,
                        label: 'List',
                        tooltip: 'Coins as a sortable table',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _body(
                () => switch (_viewMode) {
                  UtxoViewMode.notes => _notesView(),
                  UtxoViewMode.list => _listView(),
                },
              ),
            ),
            if (_consolidateMode)
              _buildConsolidateBar()
            else if (_selected.isNotEmpty)
              _BottomActionBar(
                summary: _selectionSummary(context),
                allFrozen: _selectionAllFrozen,
                busy: _freezing,
                showConsolidate: _chain != 'Liquid',
                consolidateTip: _consolidateTip,
                onTag: _labelSelected,
                onFreeze: () =>
                    _setFrozen(_selected, frozen: !_selectionAllFrozen),
                onClear: _clearSelection,
                onConsolidate: _canConsolidate ? _enterConsolidate : null,
              ),
          ],
        ),
      ),
    );
  }

  /// The phone: "Coins". Title and the privacy eye, the chain switch on its
  /// own row, one summary line with the sort, then the coins — the first
  /// screen already shows them. Selecting raises a bar over the list.
  Widget _buildPhone(BuildContext context, {required bool bothChains}) {
    final s = AppScheme.of(context);
    final pad = AppSpacing.pagePadding(context);
    final selecting = _selected.isNotEmpty && !_consolidateMode;
    final ready = !_loading && _error == null;
    return Scaffold(
      body: PageBackground.flat(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Coins',
                          style: AppTypography.pageTitleOf(
                            context,
                          ).copyWith(color: s.ink),
                        ),
                      ),
                      const PrivacyToggle(),
                    ],
                  ),
                  if (bothChains) ...[
                    const SizedBox(height: AppSpacing.md),
                    ChainSwitch<String>(
                      selected: _chain,
                      onChanged: _switchChain,
                      bitcoin: 'BTC',
                      liquid: 'Liquid',
                      expand: true,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  if (ready)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _summary(
                              context,
                              withStates: false,
                              // The rising bar states the selection.
                              followSelection: false,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              color: s.inkSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        _SortMenu(
                          sortBy: _sortBy,
                          sortAsc: _sortAsc,
                          onChanged: (by, asc) => setState(() {
                            _sortBy = by;
                            _sortAsc = asc;
                          }),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _body(
                      () => _phoneList(
                        bottom: selecting
                            ? _PhoneSelectionBar.reserve
                            : AppSpacing.xl,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedSwitcher(
                      duration: AppMotion.of(context, AppMotion.standard),
                      switchInCurve: AppMotion.settle,
                      switchOutCurve: AppMotion.exit,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: AnimatedBuilder(
                          animation: anim,
                          builder: (_, c) => Transform.translate(
                            offset: Offset(0, AppSpacing.sm * (1 - anim.value)),
                            child: c,
                          ),
                          child: child,
                        ),
                      ),
                      child: selecting
                          ? _PhoneSelectionBar(
                              key: const ValueKey('selection'),
                              summary: _selectionSummary(context),
                              allFrozen: _selectionAllFrozen,
                              busy: _freezing,
                              showConsolidate: _chain != 'Liquid',
                              onTag: _labelSelected,
                              onClear: _clearSelection,
                              onFreeze: () => _setFrozen(
                                _selected,
                                frozen: !_selectionAllFrozen,
                              ),
                              onConsolidate: _canConsolidate
                                  ? _enterConsolidate
                                  : null,
                            )
                          : const SizedBox.shrink(key: ValueKey('none')),
                    ),
                  ),
                ],
              ),
            ),
            if (_consolidateMode) _buildConsolidateBar(),
          ],
        ),
      ),
    );
  }

  /// Inline fee picker + confirm bar shown while in consolidate mode.
  /// BTC-only: the backend rejects Liquid consolidation, so this bar is
  /// unreachable on the Liquid chain.
  Widget _buildConsolidateBar() {
    final s = AppScheme.of(context);
    final count = _spendableSelected.length;
    final total = _spendableSelected.fold(0, (sum, u) => sum + u.amount);
    final isCustom = _feePreset == 'custom';
    final canSend = count >= 2 && !_sending && _feeRate > 0;
    final summary = count < 2
        ? 'Select at least two spendable coins'
        : '$count coins · ${maskAmount(context, _formatSats(total))} '
              '· estimated fee ≈$_estFeeSats sats';

    if (AppLayout.isPhone(context)) {
      return _buildPhoneConsolidateBar(
        s: s,
        summary: summary,
        isCustom: isCustom,
        canSend: canSend,
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding(context),
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fee', style: AppTypography.eyebrow.copyWith(color: s.inkFaint)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final p in _feePresets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _FeeOption(
                      label: p.$2,
                      detail: '${p.$3} · ${p.$4} sat/vB',
                      selected: _feePreset == p.$1,
                      onTap: () => setState(() => _feePreset = p.$1),
                    ),
                  ),
                ),
              Expanded(
                child: _FeeOption(
                  label: 'Custom',
                  detail: 'sat/vB',
                  selected: isCustom,
                  onTap: () => setState(() => _feePreset = 'custom'),
                ),
              ),
            ],
          ),
          if (isCustom) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Custom fee rate',
              style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _customFeeCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: '3.0',
                  suffixText: 'sat/vB',
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (_consolidateError != null) ...[
            Text(
              _consolidateError!,
              style: AppTypography.caption.copyWith(color: s.danger),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  style: AppTypography.body.copyWith(color: s.inkSecondary),
                ),
              ),
              GhostButton(
                label: 'Cancel',
                onPressed: _sending ? null : _exitConsolidate,
              ),
              const SizedBox(width: AppSpacing.sm),
              PrimaryButton(
                // The button does not broadcast: it builds the transaction
                // and opens the review-then-sign flow.
                label: _sending ? 'Preparing…' : 'Review & consolidate',
                isLoading: _sending,
                onPressed: canSend ? _runConsolidate : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Phone consolidate bar. Stacked: one segmented track of four preset
  /// cells (48 dp), a caption with the active preset's detail, the summary,
  /// then Cancel / Review side by side. The custom rate is typed in a sheet
  /// rather than an inline field: a keyboard would push the bar off screen.
  Widget _buildPhoneConsolidateBar({
    required AppScheme s,
    required String summary,
    required bool isCustom,
    required bool canSend,
  }) {
    final pad = AppSpacing.pagePadding(context);

    Widget cell(String id, String label, VoidCallback onTap) {
      final active = id == _feePreset;
      return Expanded(
        child: Semantics(
          button: true,
          selected: active,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.quick),
              curve: AppMotion.settle,
              constraints: const BoxConstraints(
                minHeight: AppLayout.minTouchTarget - 4,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              decoration: BoxDecoration(
                color: active ? s.selected : Colors.transparent,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: active ? s.edgeStrong : Colors.transparent,
                ),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.label.copyWith(
                  color: active ? s.ink : s.inkSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final detail = isCustom
        ? (_feeRate > 0
              ? 'Custom · $_feeRate sat/vB · tap Custom to change'
              : 'Custom · tap Custom to enter a rate')
        : () {
            final p = _feePresets.firstWhere((p) => p.$1 == _feePreset);
            return '${p.$3} · ${p.$4} sat/vB';
          }();

    return Container(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.md, pad, AppSpacing.md),
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.edge)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: s.well,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(color: s.edge),
            ),
            child: Row(
              children: [
                for (var i = 0; i < _feePresets.length; i++)
                  cell(
                    _feePresets[i].$1,
                    _feePresets[i].$2,
                    () => setState(() => _feePreset = _feePresets[i].$1),
                  ),
                cell('custom', 'Custom', _editCustomFee),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            detail,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (_consolidateError != null) ...[
            Text(
              _consolidateError!,
              style: AppTypography.caption.copyWith(color: s.danger),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            summary,
            style: AppTypography.bodyOf(context).copyWith(color: s.ink),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Cancel',
                  isFullWidth: true,
                  onPressed: _sending ? null : _exitConsolidate,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: PrimaryButton(
                  label: _sending ? 'Preparing…' : 'Review',
                  isFullWidth: true,
                  isLoading: _sending,
                  onPressed: canSend ? _runConsolidate : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Phone: custom fee rate entered in a keyboard-aware sheet. Selecting
  /// "Custom" and editing its value are one gesture. The sheet edits the
  /// screen's own controller (the phone bar hosts no inline field, so
  /// nothing else is bound to it) and puts the old text back on cancel —
  /// no throwaway controller to dispose under a sheet that is still
  /// animating out.
  Future<void> _editCustomFee() async {
    final previous = _customFeeCtrl.text;
    final value = await showAppDialog<String>(
      context,
      builder: (ctx) => AppDialog(
        title: const Text('Custom fee rate'),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Fee rate',
              style: AppTypography.eyebrow.copyWith(
                color: AppScheme.of(ctx).inkSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _customFeeCtrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                hintText: '3.0',
                suffixText: 'sat/vB',
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          SecondaryButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(ctx).pop(null),
          ),
          PrimaryButton(
            label: 'Use rate',
            onPressed: () => Navigator.of(ctx).pop(_customFeeCtrl.text),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (value == null) {
      _customFeeCtrl.text = previous;
      return;
    }
    setState(() {
      _customFeeCtrl.text = value.trim();
      _feePreset = 'custom';
    });
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

/// One fee preset on the desktop consolidate bar: an option card in the
/// chip grammar — outline at rest, the raised surface and a firmer edge
/// when chosen. Never the accent.
class _FeeOption extends StatelessWidget {
  const _FeeOption({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final radius = BorderRadius.circular(AppSpacing.radiusMd);
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: s.hover,
          highlightColor: s.pressed,
          splashFactory: NoSplash.splashFactory,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.quick),
            curve: AppMotion.settle,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: selected ? s.selected : Colors.transparent,
              borderRadius: radius,
              border: Border.all(color: selected ? s.edgeStrong : s.edge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.label.copyWith(
                    color: selected ? s.ink : s.inkSecondary,
                  ),
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: s.inkFaint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet text action on a phone row: the label in [ink], a 48 dp target.
class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        highlightColor: s.pressed,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppLayout.minTouchTarget,
            minWidth: AppLayout.minTouchTarget,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            label,
            style: AppTypography.buttonOf(context).copyWith(color: s.ink),
          ),
        ),
      ),
    );
  }
}

/// The phone's sort: a quiet text button naming the current order
/// (`Amount ↓`) that opens a menu of the four orders.
class _SortMenu extends StatelessWidget {
  const _SortMenu({
    required this.sortBy,
    required this.sortAsc,
    required this.onChanged,
  });

  final String sortBy;
  final bool sortAsc;
  final void Function(String by, bool asc) onChanged;

  static const _options = <(String, bool, String)>[
    ('amount', false, 'Amount, largest first'),
    ('amount', true, 'Amount, smallest first'),
    ('label', true, 'Label, A to Z'),
    ('label', false, 'Label, Z to A'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final current =
        '${sortBy == 'label' ? 'Label' : 'Amount'} ${sortAsc ? '↑' : '↓'}';
    return PopupMenuButton<int>(
      tooltip: 'Sort',
      color: s.panel,
      position: PopupMenuPosition.under,
      onSelected: (i) => onChanged(_options[i].$1, _options[i].$2),
      itemBuilder: (_) => [
        for (var i = 0; i < _options.length; i++)
          PopupMenuItem<int>(
            value: i,
            height: AppLayout.minTouchTarget,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _options[i].$3,
                    style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                  ),
                ),
                if (_options[i].$1 == sortBy && _options[i].$2 == sortAsc)
                  Icon(Icons.check, size: 20, color: s.inkSecondary),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: AppLayout.minTouchTarget),
        alignment: Alignment.center,
        padding: const EdgeInsets.only(left: AppSpacing.md),
        child: Text(current, style: AppTypography.body.copyWith(color: s.ink)),
      ),
    );
  }
}

/// Empty: one line, no illustration. An empty set is not an error.
class _EmptyCoins extends StatelessWidget {
  const _EmptyCoins();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
        child: Text(
          'No coins yet',
          textAlign: TextAlign.center,
          style: AppTypography.bodyOf(context).copyWith(color: s.inkSecondary),
        ),
      ),
    );
  }
}

// ── Load failure ──────────────────────────────────────────────────────────────
// An empty UTXO set is NOT an error and keeps its own message; this card only
// appears when the bridge call itself failed.

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.pagePadding(context),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: PlainCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: AppSpacing.icon,
                      color: s.danger,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        'Could not load UTXOs',
                        style: AppTypography.sectionTitle.copyWith(
                          color: s.ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: s.inkSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                SecondaryButton(
                  label: 'Retry',
                  isFullWidth: AppLayout.isPhone(context),
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop selection bar: what is selected on the left; Label, Clear and
/// Freeze beside the screen's one filled action, Consolidate.
class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.summary,
    required this.allFrozen,
    required this.busy,
    required this.showConsolidate,
    required this.consolidateTip,
    required this.onTag,
    required this.onFreeze,
    required this.onClear,
    required this.onConsolidate,
  });

  /// `2 selected · 0.01234567 BTC`.
  final String summary;

  /// Every selected coin is frozen: the freeze button unfreezes.
  final bool allFrozen;

  /// A freeze is in flight.
  final bool busy;

  /// Bitcoin only: Liquid has no consolidation.
  final bool showConsolidate;
  final String consolidateTip;
  final VoidCallback onTag;
  final VoidCallback onFreeze;
  final VoidCallback onClear;

  /// Null while fewer than two spendable coins are selected.
  final VoidCallback? onConsolidate;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.pagePadding(context),
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.edge)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.body.copyWith(
                color: s.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          GhostButton(label: 'Label', onPressed: onTag),
          const SizedBox(width: AppSpacing.sm),
          GhostButton(label: 'Clear', onPressed: onClear),
          const SizedBox(width: AppSpacing.sm),
          SecondaryButton(
            label: allFrozen ? 'Unfreeze' : 'Freeze',
            isLoading: busy,
            onPressed: busy ? null : onFreeze,
          ),
          if (showConsolidate) ...[
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: consolidateTip,
              child: PrimaryButton(
                label: 'Consolidate',
                onPressed: onConsolidate,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Phone selection bar, floating over the list above the tab bar: the
/// selection on one line with Label and Clear at its end, then Freeze and the
/// one filled action, Consolidate, side by side.
class _PhoneSelectionBar extends StatelessWidget {
  const _PhoneSelectionBar({
    super.key,
    required this.summary,
    required this.allFrozen,
    required this.busy,
    required this.showConsolidate,
    required this.onTag,
    required this.onClear,
    required this.onFreeze,
    required this.onConsolidate,
  });

  /// How much list the bar covers: the bottom padding the list keeps so its
  /// last row can scroll clear of it.
  static const double reserve =
      AppSpacing.xs +
      AppLayout.minTouchTarget +
      AppSpacing.sm +
      AppSpacing.phoneControlHeight +
      AppSpacing.md +
      AppSpacing.lg;

  final String summary;
  final bool allFrozen;
  final bool busy;
  final bool showConsolidate;
  final VoidCallback onTag;
  final VoidCallback onClear;
  final VoidCallback onFreeze;
  final VoidCallback? onConsolidate;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = AppSpacing.pagePadding(context);
    final freeze = SecondaryButton(
      label: allFrozen ? 'Unfreeze' : 'Freeze',
      isFullWidth: true,
      isLoading: busy,
      onPressed: busy ? null : onFreeze,
    );
    return Container(
      padding: EdgeInsets.fromLTRB(pad, AppSpacing.xs, pad, AppSpacing.md),
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.edge)),
        boxShadow: s.floatShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyOf(context).copyWith(
                    color: s.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _TextAction(label: 'Label', onTap: onTag),
              _TextAction(label: 'Clear', onTap: onClear),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(child: freeze),
              if (showConsolidate) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Consolidate',
                    isFullWidth: true,
                    onPressed: onConsolidate,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
