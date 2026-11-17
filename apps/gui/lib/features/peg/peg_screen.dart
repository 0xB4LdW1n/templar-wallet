import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/badges.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/hex_text.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/scan_button.dart';
import '../../shared/widgets/segmented_switch.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../liquid/form_parts.dart';
import 'models/peg_models.dart';

/// Peg screen — move between Bitcoin and Liquid Bitcoin through a peg
/// provider. The current provider is a built-in simulation (clearly labeled):
/// the full flow works end to end but no real funds move.
class PegScreen extends StatefulWidget {
  const PegScreen({super.key});

  @override
  State<PegScreen> createState() => _PegScreenState();
}

class _PegScreenState extends State<PegScreen> {
  final _bridge = walletBridge;

  // ── New-peg form ──
  String _direction = 'in'; // 'in' = BTC → LBTC, 'out' = LBTC → BTC
  final _amountCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  PegQuote? _quote;
  String? _quoteError;
  bool _quoting = false;
  int _quoteSeq = 0; // guards against out-of-order quote responses
  Timer? _quoteDebounce;
  bool _starting = false;
  String? _startError;

  // ── Orders ──
  List<PegOrder> _orders = [];
  bool _ordersLoading = true;
  String? _ordersError;
  final Set<String> _expanded = {};
  final Set<String> _cancelling = {};
  Timer? _pollTimer;
  bool _polling = false;

  AppState? _appState;
  String? _lastWalletId;

  static const _statusFlow = [
    ('awaiting_deposit', 'Awaiting deposit'),
    ('deposit_seen', 'Deposit seen'),
    ('confirming', 'Confirming'),
    ('settling', 'Settling'),
    ('completed', 'Completed'),
  ];

  String get _walletId => context.read<AppState>().activeWalletId ?? 'wallet-1';

  bool get _isPegIn => _direction == 'in';
  String get _fromTicker => _isPegIn ? 'BTC' : 'LBTC';
  String get _toTicker => _isPegIn ? 'LBTC' : 'BTC';

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _prefillAddress();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollActive(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appState = context.read<AppState>();
      _lastWalletId = _appState!.activeWalletId;
      _appState!.addListener(_onAppStateChanged);
    });
  }

  @override
  void dispose() {
    _appState?.removeListener(_onAppStateChanged);
    _pollTimer?.cancel();
    _quoteDebounce?.cancel();
    _amountCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _onAppStateChanged() {
    final newWalletId = _appState?.activeWalletId;
    if (newWalletId == _lastWalletId || !mounted) return;
    _lastWalletId = newWalletId;
    setState(() {
      _orders = [];
      _ordersLoading = true;
      _expanded.clear();
      _quote = null;
      _quoteError = null;
      _startError = null;
      _amountCtrl.clear();
      _addressCtrl.clear();
    });
    _loadOrders();
    _prefillAddress();
  }

  String _msg(Object e) =>
      e.toString().replaceFirst('Exception: wallet-ffi: ', '');

  String _fmtBtc(int sats) => (sats / 1e8).toStringAsFixed(8);

  String _fmtTime(int unixSecs) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSecs * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}';
  }

  // ── Quote ─────────────────────────────────────────────────────────────────

  int? get _amountSats {
    final v = double.tryParse(_amountCtrl.text.trim());
    // isFinite: tryParse accepts "NaN"/"Infinity", and .round() throws on them.
    if (v == null || !v.isFinite || v <= 0) return null;
    return (v * 1e8).round();
  }

  void _onAmountChanged() {
    _quoteDebounce?.cancel();
    setState(() {}); // refresh button/quote-panel enablement immediately
    _quoteDebounce = Timer(const Duration(milliseconds: 400), _fetchQuote);
  }

  Future<void> _fetchQuote() async {
    final sats = _amountSats;
    final seq = ++_quoteSeq;
    if (sats == null) {
      setState(() {
        _quote = null;
        _quoteError = null;
        _quoting = false;
      });
      return;
    }
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final q = await _bridge.pegQuote(_direction, sats);
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = q;
        _quoting = false;
      });
    } catch (e) {
      if (!mounted || seq != _quoteSeq) return;
      setState(() {
        _quote = null;
        _quoting = false;
        _quoteError = _msg(e);
      });
    }
  }

  void _setDirection(String dir) {
    if (dir == _direction) return;
    setState(() {
      _direction = dir;
      _quote = null;
      _quoteError = null;
      _startError = null;
      _addressCtrl.clear(); // payout chain changed — old address is invalid
    });
    _quoteDebounce?.cancel();
    _fetchQuote();
    _prefillAddress();
  }

  // ── Payout address ────────────────────────────────────────────────────────

  Future<void> _prefillAddress() async {
    final dir = _direction;
    final wallet = _walletId;
    try {
      // Peg-in pays out on Liquid, peg-out on Bitcoin.
      final info = await _bridge.generateReceiveAddress(
        wallet,
        dir == 'in' ? 'LBTC' : 'BTC',
      );
      // Discard stale results: the user may have flipped direction or
      // switched wallet while the request was in flight.
      if (!mounted || dir != _direction || wallet != _walletId) return;
      setState(() => _addressCtrl.text = info.address);
    } catch (_) {
      // Leave the field for manual entry — the wallet side may be missing.
      if (mounted) setState(() {});
    }
  }

  // ── Orders ────────────────────────────────────────────────────────────────

  /// [silent] keeps the rows on screen while the reload runs — the phone's
  /// pull-to-refresh already draws its own spinner, and swapping the list for
  /// a second one under it flashes the card empty on every pull.
  Future<void> _loadOrders({bool silent = false}) async {
    setState(() {
      if (!silent) _ordersLoading = true;
      _ordersError = null;
    });
    try {
      final orders = await _bridge.pegList(_walletId);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _ordersLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ordersLoading = false;
        _ordersError = _msg(e);
      });
    }
  }

  Future<void> _pollActive() async {
    if (_polling || !mounted) return;
    final active = _orders.where((o) => !o.isTerminal).toList();
    if (active.isEmpty) return;
    _polling = true;
    try {
      final updates = await Future.wait(
        active.map((o) => _bridge.pegStatus(o.orderId)),
      );
      if (!mounted) return;
      setState(() {
        for (final u in updates) {
          final i = _orders.indexWhere((o) => o.orderId == u.orderId);
          if (i >= 0) _orders[i] = u;
        }
      });
    } catch (_) {
      // Transient polling failure — the next tick retries.
    } finally {
      _polling = false;
    }
  }

  Future<void> _start() async {
    final sats = _amountSats;
    final address = _addressCtrl.text.trim();
    if (sats == null || address.isEmpty || _starting) return;
    setState(() {
      _starting = true;
      _startError = null;
    });
    try {
      final order = await _bridge.pegStart(
        _walletId,
        _direction,
        sats,
        address,
      );
      if (!mounted) return;
      setState(() {
        _starting = false;
        _orders.insert(0, order);
        _expanded
          ..clear()
          ..add(order.orderId);
        _amountCtrl.clear();
        _quote = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = _msg(e);
      });
    }
  }

  Future<void> _cancel(PegOrder order) async {
    if (_cancelling.contains(order.orderId)) return;
    setState(() => _cancelling.add(order.orderId));
    try {
      final updated = await _bridge.pegCancel(order.orderId);
      if (!mounted) return;
      setState(() {
        _cancelling.remove(order.orderId);
        final i = _orders.indexWhere((o) => o.orderId == updated.orderId);
        if (i >= 0) _orders[i] = updated;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling.remove(order.orderId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _openExplorer(String txid, {required bool liquid}) async {
    final app = context.read<AppState>();
    final base = liquid ? app.liquidExplorerUrl : app.btcExplorerUrl;
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final uri = Uri.parse('$trimmed/tx/$txid');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final list = ListView(
      padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
      // The pull has to work even when the page is shorter than the screen.
      physics: phone ? const AlwaysScrollableScrollPhysics() : null,
      children: [
        const PageHeader(
          title: 'Peg',
          subtitle: 'Move between Bitcoin and Liquid Bitcoin',
        ),
        // A fact about every number below, so it stays at the top.
        const WarningBanner(
          message:
              'Simulated provider — no real funds move. '
              'A real peg provider arrives in a later update.',
        ),
        const SizedBox(height: AppSpacing.xl),
        _pegForm(),
        const SizedBox(height: AppSpacing.xl),
        _ordersPanel(),
      ],
    );
    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.formMaxWidth,
            ),
            // Pull-to-refresh on a phone; a desktop pointer cannot pull, so
            // it keeps the refresh button over the orders.
            child: phone
                ? RefreshIndicator(
                    onRefresh: () => _loadOrders(silent: true),
                    child: list,
                  )
                : list,
          ),
        ),
      ),
    );
  }

  // ── New-peg form ──────────────────────────────────────────────────────────

  Widget _pegForm() {
    final s = AppScheme.of(context);
    // The quote must match the current amount — editing the field after a
    // quote arrived disables Start until the debounced re-quote lands.
    final sats = _amountSats;
    final canStart =
        !_starting &&
        sats != null &&
        _quote != null &&
        _quote!.amountSats == sats &&
        _addressCtrl.text.trim().isNotEmpty;
    final fiat = sats == null ? null : PriceService.instance.fiatDisplay(sats);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedSwitch<String>(
            options: [
              SegOption(
                value: 'in',
                label: 'Peg in',
                enabled: !_starting,
                tooltip: 'Starting a peg — wait for it to finish',
              ),
              SegOption(
                value: 'out',
                label: 'Peg out',
                enabled: !_starting,
                tooltip: 'Starting a peg — wait for it to finish',
              ),
            ],
            selected: _direction,
            onChanged: _setDirection,
            expand: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          FieldBlock(
            label: 'You send',
            // The other denomination echoes under the field while typing.
            help: fiat,
            child: TextField(
              controller: _amountCtrl,
              enabled: !_starting,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AppTypography.numeric,
              decoration: InputDecoration(
                hintText: '0.00000000',
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md),
                  child: Text(
                    _fromTicker,
                    style: AppTypography.numericSmall.copyWith(
                      color: s.inkFaint,
                    ),
                  ),
                ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
              ),
              onChanged: (_) => _onAmountChanged(),
            ),
          ),
          if (_quote != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Provider limits: ${_fmtBtc(_quote!.minSats)} – '
                '${_fmtBtc(_quote!.maxSats)} $_fromTicker',
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          _quotePanel(s),
          const SizedBox(height: AppSpacing.xl),
          FieldBlock(
            label: 'Payout address',
            help: _isPegIn
                ? 'Where the LBTC is delivered — this wallet\'s Liquid '
                      'address by default'
                : 'Where the BTC is delivered — this wallet\'s Bitcoin '
                      'address by default',
            child: TextField(
              controller: _addressCtrl,
              enabled: !_starting,
              style: AppTypography.mono,
              // A full address needs two lines beside the suffix icons.
              maxLines: AppLayout.isPhone(context) ? 2 : 1,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: '$_toTicker address',
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Paste',
                      icon: const Icon(
                        Icons.content_paste_outlined,
                        size: AppSpacing.icon,
                      ),
                      onPressed: _starting ? null : _pasteAddress,
                    ),
                    ScanIconButton(
                      controller: _addressCtrl,
                      title: 'Scan payout address',
                      onScanned: (_) => setState(() {}),
                    ),
                    IconButton(
                      tooltip: 'Use this wallet\'s address',
                      icon: const Icon(
                        Icons.account_balance_wallet_outlined,
                        size: AppSpacing.icon,
                      ),
                      onPressed: _starting ? null : _prefillAddress,
                    ),
                  ],
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_startError != null) ...[
            const SizedBox(height: AppSpacing.lg),
            DangerBanner(message: _startError!),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: _isPegIn ? 'Start peg-in' : 'Start peg-out',
            isFullWidth: true,
            isLoading: _starting,
            onPressed: canStart ? _start : null,
          ),
        ],
      ),
    );
  }

  Future<void> _pasteAddress() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    setState(() => _addressCtrl.text = text);
  }

  Widget _quotePanel(AppScheme s) {
    if (_quoting) {
      return Row(
        children: [
          const SizedBox(
            width: AppSpacing.iconSmall,
            height: AppSpacing.iconSmall,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            'Fetching quote…',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
      );
    }
    if (_quoteError != null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: AppSpacing.iconSmall,
            color: s.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _quoteError!,
              style: AppTypography.caption.copyWith(color: s.danger),
            ),
          ),
        ],
      );
    }
    if (_quote == null) {
      return Text(
        'Enter an amount to get a live quote',
        style: AppTypography.caption.copyWith(color: s.inkFaint),
      );
    }
    final q = _quote!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KvRow(
          label: 'You receive',
          value: '${_fmtBtc(q.receiveSats)} $_toTicker',
          labelWidth: 120,
          divider: true,
        ),
        KvRow(
          label: 'Rate',
          value: q.rate == 1.0 ? '1:1' : q.rate.toStringAsFixed(8),
          labelWidth: 120,
          divider: true,
        ),
        KvRow(
          label: 'Service fee',
          value: '${q.serviceFeeSats} sats',
          labelWidth: 120,
          divider: true,
        ),
        KvRow(
          label: 'Network fee',
          value: '${q.networkFeeSats} sats',
          labelWidth: 120,
          divider: true,
        ),
        KvRow(label: 'Time', value: '~${q.etaMinutes} min', labelWidth: 120),
      ],
    );
  }

  // ── Orders ────────────────────────────────────────────────────────────────

  Widget _ordersPanel() {
    final s = AppScheme.of(context);
    final hasOrders =
        !_ordersLoading && _ordersError == null && _orders.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (AppLayout.isPhone(context))
          const ListSectionLabel(label: 'Your peg orders')
        else
          // The section label with the one control a desktop pointer needs
          // in place of pull-to-refresh, centred on the label's line.
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Your peg orders',
                    style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh, size: AppSpacing.iconSmall),
                  visualDensity: VisualDensity.compact,
                  onPressed: _ordersLoading ? null : _loadOrders,
                ),
              ],
            ),
          ),
        ListCard(
          children: hasOrders
              ? [for (final o in _orders) _orderTile(s, o)]
              : [_ordersPlaceholder(s)],
        ),
      ],
    );
  }

  /// Loading, failed or empty.
  Widget _ordersPlaceholder(AppScheme s) {
    if (_ordersLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_ordersError != null) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            Text(
              'Could not load peg orders',
              style: AppTypography.body.copyWith(color: s.ink),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _ordersError!,
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            GhostButton(
              label: 'Retry',
              icon: Icons.refresh,
              onPressed: _loadOrders,
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Text(
          'No peg orders yet',
          style: AppTypography.caption.copyWith(color: s.inkFaint),
        ),
      ),
    );
  }

  /// One order as a list row: the glyph tile carries the direction in the
  /// hue of the chain it pays out on, then the two legs, then state and time.
  /// Tapping opens the detail under it.
  Widget _orderTile(AppScheme s, PegOrder o) {
    final expanded = _expanded.contains(o.orderId);
    final fromTicker = o.isPegIn ? 'BTC' : 'LBTC';
    final toTicker = o.isPegIn ? 'LBTC' : 'BTC';
    return Column(
      children: [
        Semantics(
          button: true,
          // Same contract as ListRow: the row's name, then what it is doing.
          label:
              '${o.isPegIn ? 'Peg-in' : 'Peg-out'}, '
              '${_fmtBtc(o.depositExpectedSats)} $fromTicker to '
              '${_fmtBtc(o.payoutExpectedSats)} $toTicker',
          hint: '${_statusParts(o).$1}, ${_fmtTime(o.createdAt)}',
          excludeSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () => setState(() {
                expanded
                    ? _expanded.remove(o.orderId)
                    : _expanded.add(o.orderId);
              }),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: AppSpacing.rowHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: kListPad,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    ListIconTile(
                      icon: Icons.swap_vert,
                      tint: o.isPegIn ? s.liquid : s.bitcoin,
                    ),
                    const SizedBox(width: kListGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_fmtBtc(o.depositExpectedSats)} $fromTicker → '
                            '${_fmtBtc(o.payoutExpectedSats)} $toTicker',
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.numeric.copyWith(color: s.ink),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Flexible(child: _statusBadge(o)),
                              const SizedBox(width: AppSpacing.sm),
                              Flexible(
                                child: Text(
                                  _fmtTime(o.createdAt),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.caption.copyWith(
                                    color: s.inkFaint,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      expanded
                          ? Icons.expand_less_outlined
                          : Icons.expand_more_outlined,
                      size: AppSpacing.icon,
                      color: s.inkFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (expanded) _orderDetail(s, o),
      ],
    );
  }

  StatusBadge _statusBadge(PegOrder o) {
    final (label, variant) = _statusParts(o);
    return StatusBadge(label: label, variant: variant);
  }

  /// The badge's words on their own, so the row can also say them to a
  /// screen reader (its badge is inside an excluded subtree).
  (String, BadgeVariant) _statusParts(PegOrder o) {
    return switch (o.status) {
      'awaiting_deposit' => ('Awaiting deposit', BadgeVariant.warning),
      'deposit_seen' => ('Deposit seen', BadgeVariant.neutral),
      'confirming' => ('Confirming', BadgeVariant.neutral),
      'settling' => ('Settling', BadgeVariant.neutral),
      'completed' => ('Completed', BadgeVariant.success),
      'cancelled' => ('Cancelled', BadgeVariant.neutral),
      _ => (o.status, BadgeVariant.neutral),
    };
  }

  Widget _orderDetail(AppScheme s, PegOrder o) {
    final depositTicker = o.isPegIn ? 'BTC' : 'LBTC';
    final payoutTicker = o.isPegIn ? 'LBTC' : 'BTC';
    // Peg-in deposits on Bitcoin and pays out on Liquid; peg-out the reverse.
    final depositIsLiquid = !o.isPegIn;
    final payoutIsLiquid = o.isPegIn;
    final cancelling = _cancelling.contains(o.orderId);
    final phone = AppLayout.isPhone(context);
    // A recess inside the list card: the page tone, lined up with the row's
    // glyph tile. The card already clips and draws the hairline between
    // orders.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kListPad),
      color: s.well,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepper(s, o),
          const SizedBox(height: AppSpacing.lg),
          if (o.awaitingDeposit) ...[
            InfoBanner(
              message:
                  'Send ${_fmtBtc(o.depositExpectedSats)} $depositTicker '
                  'to the deposit address below to continue. This provider is '
                  'simulated — the deposit is auto-detected, no real funds '
                  'move.',
            ),
            const SizedBox(height: AppSpacing.lg),
            Flex(
              // QR beside the address on desktop; QR above it on a phone,
              // where the side-by-side pair leaves the address ~150 dp.
              direction: phone ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: phone
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: QrImageView(
                    data: o.depositAddress,
                    version: QrVersions.auto,
                    size: phone ? AppLayout.qrSide(context, max: 200) : 112,
                  ),
                ),
                const SizedBox(width: AppSpacing.lg, height: AppSpacing.md),
                Flexible(
                  fit: phone ? FlexFit.loose : FlexFit.tight,
                  child: SizedBox(
                    width: double.infinity,
                    child: CodeBox(
                      value: o.depositAddress,
                      label: 'Deposit address (simulated)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          KvRow(label: 'Order', value: o.orderId),
          KvRow(
            label: 'Payout',
            value:
                '${_fmtBtc(o.payoutExpectedSats)} $payoutTicker → ${o.payoutAddress}',
          ),
          if (o.txidDeposit != null)
            _txRow(s, 'Deposit tx', o.txidDeposit!, liquid: depositIsLiquid),
          if (o.txidPayout != null)
            _txRow(s, 'Payout tx', o.txidPayout!, liquid: payoutIsLiquid),
          if (o.awaitingDeposit) ...[
            const SizedBox(height: AppSpacing.sm),
            // Full width on a phone, where a right-hugging tertiary control
            // is a thumb-hostile target.
            if (phone)
              GhostButton(
                label: cancelling ? 'Cancelling…' : 'Cancel order',
                icon: Icons.close,
                isFullWidth: true,
                onPressed: cancelling ? null : () => _cancel(o),
              )
            else
              Align(
                alignment: Alignment.centerRight,
                child: GhostButton(
                  label: cancelling ? 'Cancelling…' : 'Cancel order',
                  icon: Icons.close,
                  onPressed: cancelling ? null : () => _cancel(o),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _txRow(
    AppScheme s,
    String label,
    String txid, {
    required bool liquid,
  }) {
    final phone = AppLayout.isPhone(context);
    final explorer = IconButton(
      tooltip: 'View in explorer',
      icon: const Icon(Icons.open_in_new, size: AppSpacing.iconSmall),
      visualDensity: phone ? VisualDensity.standard : VisualDensity.compact,
      onPressed: () => _openExplorer(txid, liquid: liquid),
    );
    final key = Text(
      label,
      style: AppTypography.label.copyWith(color: s.inkSecondary),
    );
    if (phone) {
      // Stacked, the way KvRow stacks a long value.
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            key,
            Row(
              children: [
                Expanded(child: HexText(txid, truncate: true)),
                explorer,
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(width: 96, child: key),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: HexText(txid, truncate: true)),
          explorer,
        ],
      ),
    );
  }

  // ── Status steps ──────────────────────────────────────────────────────────
  //
  // Neutral steps: done and current in the ink, the rest in the hairline.
  // The only colour is the 6 px dot of a step that has happened.

  Widget _stepper(AppScheme s, PegOrder o) {
    if (o.status == 'cancelled') {
      final at = o.statusHistory
          .where((e) => e.status == 'cancelled')
          .map((e) => e.at)
          .firstOrNull;
      return Row(
        children: [
          Icon(
            Icons.cancel_outlined,
            size: AppSpacing.iconSmall,
            color: s.danger,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Order cancelled',
            style: AppTypography.label.copyWith(color: s.danger),
          ),
          const Spacer(),
          if (at != null)
            Text(
              _fmtTime(at),
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
        ],
      );
    }

    final idx = _statusFlow.indexWhere((step) => step.$1 == o.status);
    final current = idx < 0 ? 0 : idx;
    final completed = o.status == 'completed';
    bool done(int i) => i < current || completed;
    bool active(int i) => i == current && !completed;

    if (AppLayout.isPhone(context)) {
      // Five captions across a 300 dp detail wrap and read as noise: the
      // phone gets the progress as thin segments plus the name of the step
      // it is on, and the timestamp a Tooltip would hide from a finger.
      final at = o.statusHistory
          .where((e) => e.status == _statusFlow[current].$1)
          .map((e) => e.at)
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < _statusFlow.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: done(i) || active(i) ? s.ink : s.edge,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  _statusFlow[current].$2,
                  style: AppTypography.label.copyWith(color: s.ink),
                ),
              ),
              if (at != null)
                Text(
                  _fmtTime(at),
                  style: AppTypography.caption.copyWith(color: s.inkFaint),
                ),
            ],
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _statusFlow.length; i++)
          Expanded(
            child: _step(s, o, i, done: done(i), active: active(i)),
          ),
      ],
    );
  }

  Widget _step(
    AppScheme s,
    PegOrder o,
    int i, {
    required bool done,
    required bool active,
  }) {
    final key = _statusFlow[i].$1;
    final at = o.statusHistory
        .where((e) => e.status == key)
        .map((e) => e.at)
        .firstOrNull;
    final reached = done || active;
    final step = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusDot(done ? s.success : (active ? s.ink : s.edgeStrong)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Container(
                height: 1,
                color: reached ? s.edgeStrong : s.edge,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.sm),
          child: Text(
            _statusFlow[i].$2,
            maxLines: 2,
            style: (active ? AppTypography.label : AppTypography.caption)
                .copyWith(color: reached ? s.ink : s.inkFaint),
          ),
        ),
      ],
    );
    if (at == null) return step;
    return Tooltip(message: _fmtTime(at), child: step);
  }
}
