import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/peg_tx_label_store.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_password_gate.dart';
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

/// Peg screen — move between Bitcoin and Liquid Bitcoin through the active
/// network's peg provider (`LiquidNetworkInfo.pegProvider`):
///
/// - **native**: the Elements peg of a joined test server's regtest. A
///   peg-in is paid to a Bitcoin deposit address (from this wallet or from
///   anywhere) and claimed by the user once deep enough; a peg-out is made by
///   funding the order, and the lab's federation pays the Bitcoin.
/// - **sideswap**: on Liquid testnet, a third party's custodial swap — said
///   plainly before anything is started.
/// - none: the screen says why and still lists the wallet's orders.
///
/// Only "Fund from this wallet" and "Claim" sign, each behind a confirmation
/// and the app password gate. Reading orders contacts servers (seconds per
/// open order), so it runs off the UI path, shows its progress, and polls
/// sparingly while the screen is open.
class PegScreen extends StatefulWidget {
  const PegScreen({super.key, this.bridge, this.pollInterval});

  /// Tests pass a stub; the app uses the live bridge.
  final WalletBridge? bridge;

  /// How often open orders are re-read; null: every 30 s.
  final Duration? pollInterval;

  @override
  State<PegScreen> createState() => _PegScreenState();
}

class _PegScreenState extends State<PegScreen> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;

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

  /// Orders with a signing step (fund or claim) in flight.
  final Set<String> _signing = {};

  /// The last refusal of a step, per order, shown inside that order.
  final Map<String, String> _stepErrors = {};
  Timer? _pollTimer;
  bool _polling = false;

  AppState? _appState;
  String? _lastWalletId;

  /// The steps an order walks. A native peg-in has the user's claim between
  /// confirming and settling; the other orders go straight on.
  static const _pegInFlow = [
    ('awaiting_deposit', 'Awaiting deposit'),
    ('deposit_seen', 'Deposit seen'),
    ('confirming', 'Confirming'),
    ('claimable', 'Ready to claim'),
    ('settling', 'Settling'),
    ('completed', 'Completed'),
  ];
  static const _straightFlow = [
    ('awaiting_deposit', 'Awaiting deposit'),
    ('deposit_seen', 'Deposit seen'),
    ('confirming', 'Confirming'),
    ('settling', 'Settling'),
    ('completed', 'Completed'),
  ];

  List<(String, String)> _flowOf(PegOrder o) =>
      o.isPegIn && o.provider == 'native' ? _pegInFlow : _straightFlow;

  String get _walletId => context.read<AppState>().activeWalletId ?? 'wallet-1';

  bool get _isPegIn => _direction == 'in';
  String get _fromTicker => _isPegIn ? 'BTC' : 'LBTC';
  String get _toTicker => _isPegIn ? 'LBTC' : 'BTC';

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _prefillAddress();
    // Reading an open order asks the chain servers (seconds each); every
    // 30 s is enough to follow blocks without holding the engine busy.
    _pollTimer = Timer.periodic(
      widget.pollInterval ?? const Duration(seconds: 30),
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

  String _msg(Object e) => pegErrorText(e);

  /// `native` | `sideswap`, or null when no peg serves this network.
  String? get _provider => context.watch<AppState>().liquidNetwork?.pegProvider;

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
      final walletId = _walletId;
      final orders = await _bridge.pegList(walletId);
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _ordersLoading = false;
      });
      // Activity names peg transactions from this local index.
      unawaited(PegTxLabelStore.instance.record(walletId, orders));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ordersLoading = false;
        _ordersError = _msg(e);
      });
    }
  }

  /// One silent re-read of the list while an order is open. Skipped while
  /// another read or a signing step runs: they share the engine.
  Future<void> _pollActive() async {
    if (_polling || _ordersLoading || _signing.isNotEmpty || !mounted) return;
    final open = _orders.any((o) => !o.isTerminal && !o.isLegacySimulated);
    if (!open) return;
    setState(() => _polling = true);
    try {
      await _loadOrders(silent: true);
    } finally {
      if (mounted) setState(() => _polling = false);
    }
  }

  void _replace(PegOrder updated) {
    final i = _orders.indexWhere((o) => o.orderId == updated.orderId);
    if (i >= 0) _orders[i] = updated;
  }

  Future<void> _start() async {
    final sats = _amountSats;
    final address = _addressCtrl.text.trim();
    if (sats == null || address.isEmpty || _starting) return;
    if (_quote?.provider == 'sideswap') {
      final go = await _confirmDialog(
        title: 'Start a SideSwap swap?',
        icon: Icons.storefront_outlined,
        body: _sideSwapDisclosure,
        action: 'Start swap',
      );
      if (!go || !mounted) return;
    }
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
        _replace(updated);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling.remove(order.orderId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  static const _sideSwapDisclosure =
      'On Liquid testnet this goes through SideSwap, a third party\'s '
      'custodial swap service — not a peg. You send coins to SideSwap and it '
      'pays you on the other chain by itself; until it does, it holds them. '
      'Your receive address, the direction and a fee rate are sent to '
      'SideSwap.';

  Future<bool> _confirmDialog({
    required String title,
    required IconData icon,
    required String body,
    required String action,
  }) async {
    final ok = await showAppDialog<bool>(
      context,
      barrierDismissible: false,
      builder: (ctx) => PromptDialog(
        title: title,
        icon: icon,
        width: 460,
        actions: [
          GhostButton(
            label: 'Cancel',
            onPressed: () => Navigator.pop(ctx, false),
          ),
          PrimaryButton(
            label: action,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
        child: Text(
          body,
          style: AppTypography.body.copyWith(
            color: AppScheme.of(ctx).inkSecondary,
          ),
        ),
      ),
    );
    return ok == true;
  }

  String get _onThisDevice =>
      AppLayout.isMobilePlatform ? 'device' : 'computer';

  /// Fund from this wallet: what will be signed, then the password gate,
  /// then the engine builds, signs and broadcasts.
  Future<void> _fund(PegOrder o) async {
    if (_signing.contains(o.orderId)) return;
    final amount = _fmtBtc(o.depositExpectedSats);
    final body = o.isPegIn
        ? 'This wallet sends $amount BTC to the deposit address\n'
              '${o.depositAddress}\nat 1 sat/vB; the Bitcoin fee is paid on '
              'top. ${o.isSideSwap ? 'SideSwap' : 'You'} then '
              '${o.isSideSwap ? 'pays' : 'claim'} the L-BTC once the deposit '
              'has ${o.confirmationsRequired} confirmations.'
        : o.isSideSwap
        ? 'This wallet sends $amount L-BTC to SideSwap\'s deposit address\n'
              '${o.depositAddress}\nSideSwap then pays the BTC itself.'
        : 'This wallet signs and broadcasts a Liquid peg-out of $amount '
              'L-BTC; the Liquid fee is paid on top. After '
              '${o.confirmationsRequired} Liquid confirmations the test '
              'server\'s federation pays $amount BTC to\n${o.payoutAddress}';
    final go = await _confirmDialog(
      title: o.isPegIn ? 'Pay the peg-in deposit?' : 'Make the peg-out?',
      icon: Icons.outbox_outlined,
      body: body,
      action: 'Continue',
    );
    if (!go || !mounted) return;
    final ok = await showSpendPasswordGate(
      context,
      message:
          'Templar is about to sign the ${o.isPegIn ? 'deposit' : 'peg-out'} '
          'with the key stored on this $_onThisDevice.',
    );
    if (!ok || !mounted) return;
    await _signStep(o, () => _bridge.pegFund(o.orderId), 'Deposit sent');
  }

  /// Claim a native peg-in that is deep enough.
  Future<void> _claim(PegOrder o) async {
    if (_signing.contains(o.orderId)) return;
    final go = await _confirmDialog(
      title: 'Claim the peg-in?',
      icon: Icons.download_done_outlined,
      body:
          'This wallet checks the deposit against its own view of the Bitcoin '
          'chain, then signs and broadcasts the claim: about '
          '${_fmtBtc(o.payoutExpectedSats)} L-BTC to\n${o.payoutAddress}\n'
          '(the claim\'s Liquid fee comes out of the deposit).',
      action: 'Continue',
    );
    if (!go || !mounted) return;
    final ok = await showSpendPasswordGate(
      context,
      message:
          'Templar is about to sign the peg-in claim with the key stored on '
          'this $_onThisDevice.',
    );
    if (!ok || !mounted) return;
    await _signStep(o, () => _bridge.pegClaim(o.orderId), 'Claim sent');
  }

  Future<void> _signStep(
    PegOrder o,
    Future<PegOrder> Function() step,
    String done,
  ) async {
    setState(() {
      _signing.add(o.orderId);
      _stepErrors.remove(o.orderId);
    });
    try {
      final updated = await step();
      if (!mounted) return;
      setState(() {
        _signing.remove(o.orderId);
        _replace(updated);
      });
      unawaited(PegTxLabelStore.instance.record(updated.walletId, _orders));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$done. The order follows the chain from here.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signing.remove(o.orderId);
        _stepErrors[o.orderId] = _msg(e);
      });
    }
  }

  Future<void> _openExplorer(String txid, {required bool liquid}) async {
    final app = context.read<AppState>();
    final base = liquid ? app.liquidExplorerBase : app.btcExplorerBase;
    if (base == null) return;
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
    final provider = _provider;
    final list = ListView(
      padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
      // The pull has to work even when the page is shorter than the screen.
      physics: phone ? const AlwaysScrollableScrollPhysics() : null,
      children: [
        const PageHeader(
          title: 'Peg',
          subtitle: 'Move between Bitcoin and Liquid Bitcoin',
        ),
        // Who moves the coins: a fact about every number below, so it stays
        // at the top.
        _providerBanner(provider),
        const SizedBox(height: AppSpacing.xl),
        // No provider here: nothing can be started, but the wallet's orders
        // (of another network, or the retired simulated ones) still list.
        if (provider != null) ...[
          _pegForm(),
          const SizedBox(height: AppSpacing.xl),
        ],
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

  /// Who moves the coins, said before anything is started.
  Widget _providerBanner(String? provider) {
    final st = context.watch<AppState>();
    switch (provider) {
      case 'native':
        return InfoBanner(
          title: 'Native peg · ${st.testServerName ?? 'test server'}',
          message:
              'The Elements peg between the test server\'s Bitcoin regtest '
              'and Liquid regtest: real regtest coins. You claim a peg-in '
              'once its deposit is deep enough; a peg-out is paid by the test '
              'server\'s federation after its Liquid confirmations.',
        );
      case 'sideswap':
        return const WarningBanner(
          title: 'SideSwap swap — not a peg',
          message: _sideSwapDisclosure,
        );
      default:
        final reason = st.liquidNetwork?.pegUnavailableReason;
        return InfoBanner(
          title: 'No peg on this network',
          message: reason == null
              ? 'Peg-in and peg-out need a test server: join one in '
                    'Settings › Network & Sync.'
              : pegErrorText(reason).replaceFirst('No peg here. ', ''),
        );
    }
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
                // 21 million BTC is "no maximum" in words.
                _quote!.maxSats >= 2100000000000000
                    ? 'Minimum ${_fmtBtc(_quote!.minSats)} $_fromTicker'
                    : 'Limits: ${_fmtBtc(_quote!.minSats)} – '
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
            // A refusal moved nothing: a warning, not the red of a loss.
            WarningBanner(title: 'Not started', message: _startError!),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: _quote?.provider == 'sideswap'
                ? 'Start SideSwap swap'
                : (_isPegIn ? 'Start peg-in' : 'Start peg-out'),
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
          label: 'Provider',
          value: q.provider == 'sideswap'
              ? 'SideSwap (custodial)'
              : 'Native peg',
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
          value:
              '${q.networkFeeSats} sats, '
              '${q.networkFeeIncluded ? 'taken from the amount' : 'paid on top'}',
          labelWidth: 120,
          divider: true,
        ),
        KvRow(
          label: 'Waits for',
          value:
              '${q.confirmationsRequired} '
              '${_isPegIn ? 'Bitcoin' : 'Liquid'} confirmations',
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
          // The background re-read of open orders has no spinner of its own
          // on a phone: the label says it.
          ListSectionLabel(
            label: _polling ? 'Your peg orders · checking…' : 'Your peg orders',
          )
        else
          // The section label with the one control a desktop pointer needs
          // in place of pull-to-refresh, centred on the label's line. While
          // open orders are re-read in the background, a spinner holds its
          // place.
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
                if (_polling)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.sm),
                    child: SizedBox(
                      width: AppSpacing.iconSmall,
                      height: AppSpacing.iconSmall,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
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
      // Open orders are read from the chains first: say why it takes a while.
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          children: [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Reading your orders from the chains…',
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
          ],
        ),
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
    if (o.isLegacySimulated) return ('Simulated', BadgeVariant.neutral);
    final conf = o.confirmationsRequired > 0
        ? ' ${o.confirmations}/${o.confirmationsRequired}'
        : '';
    return switch (o.status) {
      'awaiting_deposit' => (
        o.isPegIn || o.isSideSwap ? 'Awaiting deposit' : 'Awaiting funding',
        BadgeVariant.warning,
      ),
      'deposit_seen' => ('Deposit seen', BadgeVariant.neutral),
      'confirming' => ('Confirming$conf', BadgeVariant.neutral),
      // The user's move: a status with a dot, like an unpaid deposit.
      'claimable' => ('Ready to claim', BadgeVariant.warning),
      'settling' => ('Settling', BadgeVariant.neutral),
      'completed' => ('Completed', BadgeVariant.success),
      'cancelled' => ('Cancelled', BadgeVariant.neutral),
      'expired' => ('Expired', BadgeVariant.neutral),
      'failed' => ('Failed', BadgeVariant.danger),
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
    final signing = _signing.contains(o.orderId);
    final stepError = _stepErrors[o.orderId];
    final phone = AppLayout.isPhone(context);
    final counting = const {
      'deposit_seen',
      'confirming',
      'claimable',
    }.contains(o.status);
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
          if (o.isLegacySimulated)
            const InfoBanner(
              message:
                  'An order of the retired simulated provider: no coins '
                  'moved, and nothing can be paid to it or claimed from it.',
            )
          else
            _stepper(s, o),
          const SizedBox(height: AppSpacing.lg),
          if (o.lastError != null) ...[
            WarningBanner(
              title: 'Could not check this order',
              message: _msg(o.lastError!),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (counting && o.confirmationsRequired > 0) ...[
            KvRow(
              label: 'Confirmed',
              value:
                  '${o.confirmations} of ${o.confirmationsRequired} '
                  '${o.isPegIn ? 'Bitcoin' : 'Liquid'} confirmations',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (o.status == 'expired')
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                o.isPegIn && o.txidDeposit == null
                    ? 'The deposit address expired: never pay it. Start a new '
                          'peg.'
                    : 'The order expired.',
                style: AppTypography.bodySmall.copyWith(color: s.inkSecondary),
              ),
            ),
          if (o.status == 'failed')
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                o.isSideSwap
                    ? 'SideSwap did not pay this order out.'
                    : 'The order failed.',
                style: AppTypography.bodySmall.copyWith(color: s.danger),
              ),
            ),
          if (o.showsDepositAddress) ...[
            Text(
              'Pay ${_fmtBtc(o.depositExpectedSats)} $depositTicker to this '
              'address — from this wallet below, or from any other '
              'wallet.${_validityOf(o)}',
              style: AppTypography.bodySmall.copyWith(color: s.inkSecondary),
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
                      label: o.isSideSwap
                          ? 'SideSwap deposit address'
                          : 'Deposit address',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ] else if (o.canOfferFund && !o.isPegIn) ...[
            Text(
              'Funding signs and broadcasts the peg-out from this wallet\'s '
              'L-BTC; there is no address to pay by hand.',
              style: AppTypography.bodySmall.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (o.canOfferClaim) ...[
            Text(
              'The deposit is deep enough. Claim it to receive the L-BTC.',
              style: AppTypography.bodySmall.copyWith(color: s.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          KvRow(label: 'Order', value: o.orderId),
          KvRow(
            label: 'Payout',
            value:
                '${_fmtBtc(o.payoutExpectedSats)} $payoutTicker → ${o.payoutAddress}',
          ),
          if (o.depositReceivedSats != null &&
              o.depositReceivedSats != o.depositExpectedSats)
            KvRow(
              label: 'Received',
              value: '${_fmtBtc(o.depositReceivedSats!)} $depositTicker',
            ),
          if (o.txidDeposit != null)
            _txRow(
              s,
              o.isPegIn ? 'Deposit tx' : 'Peg-out tx',
              o.txidDeposit!,
              liquid: depositIsLiquid,
            ),
          if (o.txidClaim != null)
            _txRow(s, 'Claim tx', o.txidClaim!, liquid: true),
          if (o.txidPayout != null && o.txidPayout != o.txidClaim)
            _txRow(s, 'Payout tx', o.txidPayout!, liquid: payoutIsLiquid),
          if (stepError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            WarningBanner(title: 'Not done', message: stepError),
          ],
          if (o.canOfferFund || o.canOfferClaim || o.awaitingDeposit) ...[
            const SizedBox(height: AppSpacing.md),
            _orderActions(o, signing: signing, cancelling: cancelling),
          ],
        ],
      ),
    );
  }

  /// "Valid through Liquid block 189." / "SideSwap takes it until …".
  String _validityOf(PegOrder o) {
    if (o.validUntilLiquidHeight != null) {
      return ' The address is valid through Liquid block '
          '${o.validUntilLiquidHeight}.';
    }
    if (o.expiresAt != null) {
      return ' SideSwap takes it until ${_fmtTime(o.expiresAt!)}.';
    }
    return '';
  }

  /// Fund, Claim and Cancel: full width and stacked on a phone, a right-hand
  /// row on desktop.
  Widget _orderActions(
    PegOrder o, {
    required bool signing,
    required bool cancelling,
  }) {
    final phone = AppLayout.isPhone(context);
    final busy = signing || cancelling;
    final buttons = <Widget>[
      if (o.canOfferClaim)
        SecondaryButton(
          label: signing ? 'Claiming…' : 'Claim',
          icon: Icons.download_done_outlined,
          isFullWidth: phone,
          onPressed: busy ? null : () => _claim(o),
        ),
      if (o.canOfferFund)
        SecondaryButton(
          label: signing ? 'Funding…' : 'Fund from this wallet',
          icon: Icons.outbox_outlined,
          isFullWidth: phone,
          onPressed: busy ? null : () => _fund(o),
        ),
      if (o.awaitingDeposit && !o.isLegacySimulated)
        GhostButton(
          label: cancelling ? 'Cancelling…' : 'Cancel order',
          icon: Icons.close,
          isFullWidth: phone,
          onPressed: busy ? null : () => _cancel(o),
        ),
    ];
    if (phone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            buttons[i],
          ],
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: buttons,
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
    final app = context.read<AppState>();
    final hasExplorer =
        (liquid ? app.liquidExplorerBase : app.btcExplorerBase) != null;
    // A regtest has no public explorer: no link rather than a dead one.
    final Widget explorer = hasExplorer
        ? IconButton(
            tooltip: 'View in explorer',
            icon: const Icon(Icons.open_in_new, size: AppSpacing.iconSmall),
            visualDensity: phone
                ? VisualDensity.standard
                : VisualDensity.compact,
            onPressed: () => _openExplorer(txid, liquid: liquid),
          )
        : const SizedBox(width: AppSpacing.sm);
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
    const ended = {
      'cancelled': 'Order cancelled',
      'expired': 'Order expired',
      'failed': 'Order failed',
    };
    final endedLabel = ended[o.status];
    if (endedLabel != null) {
      final at = o.statusHistory
          .where((e) => e.status == o.status)
          .map((e) => e.at)
          .lastOrNull;
      // Only a failure is a loss; a cancel or an expiry before any deposit
      // is not, so it is not drawn in red.
      final tint = o.status == 'failed' ? s.danger : s.inkSecondary;
      return Row(
        children: [
          Icon(
            o.status == 'failed' ? Icons.error_outline : Icons.cancel_outlined,
            size: AppSpacing.iconSmall,
            color: tint,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(endedLabel, style: AppTypography.label.copyWith(color: tint)),
          const Spacer(),
          if (at != null)
            Text(
              _fmtTime(at),
              style: AppTypography.caption.copyWith(color: s.inkFaint),
            ),
        ],
      );
    }

    final flow = _flowOf(o);
    final idx = flow.indexWhere((step) => step.$1 == o.status);
    final current = idx < 0 ? 0 : idx;
    final completed = o.status == 'completed';
    bool done(int i) => i < current || completed;
    bool active(int i) => i == current && !completed;

    if (AppLayout.isPhone(context)) {
      // Five captions across a 300 dp detail wrap and read as noise: the
      // phone gets the progress as thin segments plus the name of the step
      // it is on, and the timestamp a Tooltip would hide from a finger.
      final at = o.statusHistory
          .where((e) => e.status == flow[current].$1)
          .map((e) => e.at)
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < flow.length; i++) ...[
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
                  flow[current].$2,
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
        for (var i = 0; i < flow.length; i++)
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
    final key = _flowOf(o)[i].$1;
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
            _flowOf(o)[i].$2,
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
