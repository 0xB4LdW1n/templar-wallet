import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../services/price_service.dart';
import '../../shared/amount_units.dart';
import '../../shared/payment_uri.dart';
import '../../shared/widgets/address_tag.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/chain_switch.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../shared/widgets/unit_chip.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../services/address_label_store.dart';
import '../hardware/hw_error.dart';
import 'address_dialogs.dart';
import 'address_rows.dart';
import 'models/address_info.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key, this.bridge});

  /// Test seam: the engine to ask for addresses. The app leaves it null and
  /// gets the process-wide [walletBridge]; a widget test hands in a stand-in
  /// so the screen can be driven without a wallet on disk.
  final WalletBridge? bridge;

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

/// Longest note a payment request carries. A BIP21 label is read off a QR by
/// a payer's camera: every character grows the code, and past a few dozen a
/// phone-sized code is a wall of modules that will not scan. Forty is a
/// sentence — "Invoice 12 · March rent" — and keeps the QR at the size the
/// card was laid out for.
const int kRequestNoteMaxLength = 40;

/// Longest amount a request field takes: `0.00000001` is ten characters,
/// a fiat figure with a thousands group rarely passes twelve.
const int _requestAmountMaxLength = 16;

/// How many previous addresses Receive shows before "Show all": the list is
/// every address the wallet ever handed out, and this page exists to hand
/// over one. The rest, with what each received, live on the All addresses
/// page ([AppRoutes.receiveAddresses]).
const int _previousPreview = 8;

/// The QR's side on desktop. A phone takes [AppLayout.qrSide].
const double _qrSideDesktop = 240;

/// The address card's widest: the QR plus its frame, with room for an
/// address on two lines beside the copy control.
const double _addressCardMaxWidth = 440;

class _ReceiveScreenState extends State<ReceiveScreen> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;

  /// Last good answer per wallet and chain, mobile only. Arriving on this
  /// screen from the Dashboard should not greet the user with a spinner; the
  /// cached address is shown at once while the refresh runs behind it. Plain
  /// visits ask for the last unused address, so the cache and the refresh
  /// agree unless funds arrived in between.
  static final Map<String, ({AddressInfo current, List<AddressInfo> previous})>
  _cache = {};

  String _selectedAsset = 'BTC';
  AddressInfo? _current;
  List<AddressInfo> _previous = [];
  bool _loading = true;
  bool _copied = false;
  String? _error;

  /// The optional payment request drawn into the QR: an amount, a note, or
  /// both. Closed and empty by default — this screen exists to hand over an
  /// address, and how much to send is the second question, never the first.
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _labelCtrl = TextEditingController();
  bool _requestOpen = false;

  /// The amount field holds the selected fiat currency rather than coin.
  /// Only the field is in fiat: the link always carries the coin figure,
  /// which is what BIP21 defines and the only figure a payer's wallet reads.
  bool _fiatInput = false;

  /// Bumped by every [_load]; a response carrying an older number lost the
  /// race to a chain switch or a newer "New address" and is dropped.
  int _loadSeq = 0;

  // Hardware wallet verification state
  bool _verifying = false;
  bool _verified = false;
  String? _hwError;

  /// Device-verifiable wallets: USB hardware wallets (typed label) and
  /// HWI-imported watch-only wallets. Single source of truth lives on
  /// AppState; the legacy 'watch_only' label is kept for wallets imported
  /// before the type labels were unified.
  bool get _isHardwareWallet {
    final appState = context.read<AppState>();
    return appState.isActiveWalletHardware ||
        appState.activeWalletType == 'watch_only';
  }

  /// "Verify on Ledger" needs a USB HID transport, which the phone build does
  /// not ship: on Android every hardware route answers HW_UNSUPPORTED, so the
  /// button could only ever end in an error there.
  bool get _canVerifyOnDevice =>
      _isHardwareWallet &&
      _selectedAsset == 'BTC' &&
      !AppLayout.isMobilePlatform;

  @override
  void initState() {
    super.initState();
    AddressLabelStore.instance.load();
    // A Liquid-only wallet has no Bitcoin side to ask: opening on the BTC tab
    // would greet the user with "Bitcoin wallet not open" instead of the
    // address they came for.
    final st = context.read<AppState>();
    if (!st.activeWalletBitcoin && st.activeWalletLiquid) {
      _selectedAsset = 'LBTC';
    }
    // An amount can be asked for in fiat, so the price has to be there by the
    // time the request section is opened — and has to keep the ≈ line honest
    // while the screen is up.
    PriceService.instance
      ..addListener(_onPriceChanged)
      ..fetch();
    _load();
  }

  @override
  void dispose() {
    PriceService.instance.removeListener(_onPriceChanged);
    _amountCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _onPriceChanged() {
    if (mounted) setState(() {});
  }

  /// Loads the receive address. [fresh] advances the derivation index — only
  /// the "New address" button asks for it; simply opening the screen reuses
  /// the current unused address instead of burning a new one.
  ///
  /// The chain is captured once, up front: both bridge calls ask for the same
  /// asset, and a result that lands after the user switched chains (or asked
  /// for another fresh address) is discarded instead of being shown under
  /// the other chain's heading.
  Future<void> _load({bool fresh = false}) async {
    final asset = _selectedAsset;
    final token = ++_loadSeq;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    final cacheKey = '$walletId/$asset';
    // Platform, not width: MediaQuery is off limits from initState.
    final cached = !fresh && AppLayout.isMobilePlatform
        ? _cache[cacheKey]
        : null;
    setState(() {
      _loading = cached == null;
      if (cached != null) {
        _current = cached.current;
        _previous = cached.previous;
      }
      _error = null;
      _verified = false;
      _hwError = null;
    });
    bool stale() => !mounted || token != _loadSeq || asset != _selectedAsset;
    try {
      final cur = await _bridge.generateReceiveAddress(
        walletId,
        asset,
        fresh: fresh,
      );
      if (stale()) return;
      final prev = await _bridge.listPreviousAddresses(walletId, asset);
      if (stale()) return;
      _cache[cacheKey] = (current: cur, previous: prev);
      setState(() {
        _current = cur;
        _previous = prev;
        _loading = false;
      });
    } catch (e) {
      if (stale()) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// The copy button names what it puts on the clipboard: an address until
  /// something is asked for, the whole request afterwards.
  String get _copyLabel {
    if (_copied) return 'Copied';
    return _paymentUri != null ? 'Copy payment link' : 'Copy address';
  }

  /// What this chain calls its coin, for the unit chip and the ≈ line.
  String get _ticker => _selectedAsset == 'BTC' ? 'BTC' : 'LBTC';

  /// The requested amount in satoshis — null when the field is empty or does
  /// not parse. A half-typed figure must not quietly become a QR: until it
  /// is a number, nothing has been asked for.
  int? get _requestSats {
    final text = _amountCtrl.text.trim();
    if (text.isEmpty) return null;
    final sats = _fiatInput
        ? AmountUnits.satsFromFiat(text, PriceService.instance.btcPrice)
        : AmountUnits.satsFromCoin(text);
    return (sats == null || sats <= 0) ? null : sats;
  }

  String get _requestNote => _labelCtrl.text.trim();

  /// The BIP21 link, or null when nothing was asked for: with no amount and
  /// no note a payment link says nothing the address does not already say,
  /// and a bare address is what every wallet and every camera reads best.
  String? get _paymentUri {
    final address = _current?.address;
    if (address == null) return null;
    final sats = _requestSats;
    if (sats == null && _requestNote.isEmpty) return null;
    return PaymentUri.build(
      address: address,
      asset: _selectedAsset,
      amountSats: sats,
      label: _requestNote,
    );
  }

  /// What the QR carries and what Copy and Share hand over — the payment
  /// link once one has been asked for, the bare address otherwise.
  String get _shareData => _paymentUri ?? _current!.address;

  /// Whether the ⇅ can flip the field right now: only with a live price, as
  /// a fiat figure cannot be resolved to coin without one.
  bool get _canToggleFiat => PriceService.instance.hasPrice;

  /// Flip the amount field between coin and fiat, re-expressing whatever is
  /// typed so the figure on screen keeps meaning the same money.
  void _toggleFiat() {
    final price = PriceService.instance.btcPrice;
    if (price <= 0) return;
    final toFiat = !_fiatInput;
    final converted = AmountUnits.convert(
      _amountCtrl.text,
      toFiat: toFiat,
      btcPrice: price,
    );
    setState(() {
      _fiatInput = toFiat;
      if (converted != null) _amountCtrl.text = converted;
    });
  }

  /// The other reading of the amount, under the field while it is typed —
  /// "≈ €98.40" under a coin figure, "≈ 0.00123456 BTC" under a fiat one.
  /// Fiat goes through [PriceService], which owns its symbol and grouping.
  String? get _equivalentText {
    final sats = _requestSats;
    if (sats == null) return null;
    final price = PriceService.instance;
    if (!price.hasPrice) return null;
    if (_fiatInput) return '≈ ${AmountUnits.coinText(sats)} $_ticker';
    final fiat = price.fiatDisplay(sats);
    return fiat == null ? null : '≈ $fiat';
  }

  /// One line naming what is being asked for, shown under the section's
  /// title so a closed request is still a stated fact and not a surprise
  /// hiding inside the QR.
  String? get _requestSummary {
    final sats = _requestSats;
    final note = _requestNote;
    if (sats == null) return note.isEmpty ? null : note;
    final coin = '${PaymentUri.amountText(sats)} $_ticker';
    final fiatText = PriceService.instance.fiatDisplay(sats);
    final fiat = fiatText == null ? '' : ' ≈ $fiatText';
    return note.isEmpty ? '$coin$fiat' : '$coin$fiat · $note';
  }

  Future<void> _copyAddress() async {
    if (_current == null) return;
    await Clipboard.setData(ClipboardData(text: _shareData));
    if (!mounted) return;
    confirmCopyOnPhone(context);
    setState(() => _copied = true);
    await Future.delayed(kCopiedFor);
    if (mounted) setState(() => _copied = false);
  }

  /// Phone only: the system share sheet, so the address can go straight into
  /// a messenger instead of through the clipboard.
  Future<void> _shareAddress() async {
    if (_current == null) return;
    // iPad's share popover needs an anchor; Android ignores it.
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: _shareData,
        subject: _paymentUri != null
            ? 'Payment request'
            : (_selectedAsset == 'BTC'
                  ? 'Bitcoin testnet address'
                  : 'Liquid testnet address'),
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _newAddress() async {
    await _load(fresh: true);
  }

  void _switchAsset(String asset) {
    if (asset == _selectedAsset) return;
    setState(() {
      _selectedAsset = asset;
      _loading = true;
      // Addresses of the other chain must not linger under the new heading.
      _current = null;
      _previous = [];
      _error = null;
      _verified = false;
      _hwError = null;
    });
    _load();
  }

  Future<void> _verifyOnDevice() async {
    if (_verifying) return;
    final walletId = context.read<AppState>().activeWalletId ?? '';
    setState(() {
      _verifying = true;
      _hwError = null;
      _verified = false;
    });
    try {
      await _bridge.verifyHwAddress(walletId);
      if (mounted) {
        setState(() {
          _verifying = false;
          _verified = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verifying = false;
          // Shared classifier: the same failure must read the same here as in
          // the send flow and the setup screen, with the backend's
          // platform-specific guidance already folded in.
          _hwError = friendlyHwError(e);
        });
      }
    }
  }

  /// "Request an amount" — the disclosure that turns an address into an
  /// invoice: an amount, a note, or both, folded into a BIP21 link that the
  /// QR, Copy and Share all carry.
  ///
  /// Closed, it is one row; open, two fields. Either way it states what is
  /// being asked for in its own subtitle, because a request the QR carries
  /// and the screen does not name is a number nobody agreed to.
  Widget _requestSection(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final summary = _requestSummary;
    final header = _RequestHeader(
      open: _requestOpen,
      summary: summary,
      onTap: () => setState(() => _requestOpen = !_requestOpen),
    );
    if (!_requestOpen) return header;

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        const SizedBox(height: AppSpacing.md),
        label('Amount'),
        TextField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: (phone ? AppTypography.bodyLarge : AppTypography.numeric)
              .copyWith(
                color: s.ink,
                fontFeatures: AppTypography.numeric.fontFeatures,
              ),
          maxLength: _requestAmountMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          decoration: InputDecoration(
            hintText: _fiatInput ? '0.00' : '0.00000000',
            // No "0/16" under an amount: the cap is a guard, not a feature.
            counterText: '',
            // The same ⇅ chip the Send amount carries: one control, one
            // gesture, whichever end of a payment you are on.
            //
            // The Row is not decoration: the suffix slot hands its child the
            // field's whole width, and the chip's own 48 dp touch box would
            // stretch across it and push the hint out. mainAxisSize.min
            // shrinks it back to the chip, at the end of the field, which is
            // how Send's amount row carries it too.
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                UnitChip(
                  label: _fiatInput ? PriceService.instance.currency : _ticker,
                  other: _canToggleFiat
                      ? (_fiatInput ? _ticker : PriceService.instance.currency)
                      : null,
                  onTap: _canToggleFiat ? _toggleFiat : null,
                ),
              ],
            ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (_equivalentText case final approx?) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            approx,
            style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        label('Note'),
        TextField(
          controller: _labelCtrl,
          textCapitalization: TextCapitalization.sentences,
          // Hard cap, and one line: a note is a few words for the payer,
          // not a message, and the QR above has a fixed frame to fit in.
          maxLength: kRequestNoteMaxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          maxLines: 1,
          decoration: InputDecoration(
            hintText: 'What it is for (optional)',
            // The counter only once it matters: the last ten characters.
            counterText: _labelCtrl.text.length >= kRequestNoteMaxLength - 10
                ? '${_labelCtrl.text.length}/$kRequestNoteMaxLength'
                : '',
          ),
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  String get _caption => _selectedAsset == 'BTC'
      ? 'Native SegWit · a fresh address for every payment'
      : 'Confidential · the same blinded address can be reused';

  /// Both chains present: the switch earns its place. A one-chain wallet has
  /// nothing to choose, and the address card already says which chain it is.
  bool _hasBothChains(AppState st) =>
      st.activeWalletBitcoin && st.activeWalletLiquid;

  @override
  Widget build(BuildContext context) {
    final phone = AppLayout.isPhone(context);
    final st = context.watch<AppState>();
    final chainSwitch = _hasBothChains(st)
        ? ChainSwitch<String>(
            selected: _selectedAsset,
            onChanged: _switchAsset,
            bitcoin: 'BTC',
            liquid: 'LBTC',
            expand: phone,
          )
        : null;

    final Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.only(top: AppSpacing.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = _LoadError(
        message: phone ? _plainError(_error!) : _error!,
        onRetry: _load,
      );
    } else if (phone) {
      body = _phoneBody(context);
    } else {
      body = _desktopBody(context);
    }

    return Scaffold(
      body: PageBackground.flat(
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
          children: [
            // The phone shell's header already names the page; there the
            // chain switch leads the column at full width.
            if (phone) ...[
              if (chainSwitch != null) ...[
                chainSwitch,
                const SizedBox(height: AppSpacing.lg),
              ],
            ] else
              PageHeader(title: 'Receive', actions: [?chainSwitch]),
            body,
          ],
        ),
      ),
    );
  }

  /// Bitcoin hands out a fresh address per payment, so there is a history
  /// worth listing. Liquid's confidential address is one and reused: a
  /// "previous addresses" list there would only ever repeat the card above.
  bool get _hasPreviousList => _selectedAsset == 'BTC';

  /// The newest previous addresses first — the bridge lists by ascending
  /// derivation index, and the ones most likely still in use are the latest.
  List<AddressInfo> get _previousNewestFirst => _previous.reversed.toList();

  void _openAllAddresses() =>
      context.go('${AppRoutes.receiveAddresses}?asset=$_selectedAsset');

  /// Two columns: the action on the left at a readable width, the history
  /// on the right taking what is left.
  Widget _desktopBody(BuildContext context) {
    if (!_hasPreviousList) {
      return Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _addressCardMaxWidth),
          child: Reveal(child: _addressCard(context)),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        // The card keeps its width while there is room and gives way to an
        // even split in a narrow window, so the list never gets a sliver.
        final cardWidth =
            (c.maxWidth - AppSpacing.xl) / 2 < _addressCardMaxWidth
            ? (c.maxWidth - AppSpacing.xl) / 2
            : _addressCardMaxWidth;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: cardWidth,
              child: Reveal(child: _addressCard(context)),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Reveal(delay: 1, child: _desktopPreviousCard(context)),
            ),
          ],
        );
      },
    );
  }

  /// The desktop address card: code, address, what kind it is, the request,
  /// then the screen's one filled control.
  Widget _addressCard(BuildContext context) {
    final s = AppScheme.of(context);
    return FormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: _QrTile(data: _shareData, side: _qrSideDesktop),
          ),
          const SizedBox(height: AppSpacing.lg),
          // The well always holds the address: it is what a human reads back
          // to check, and the link's query is machine business. What the QR
          // adds on top is named by the request section under it.
          _AddressWell(info: _current!),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _caption,
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
          const SizedBox(height: AppSpacing.lg),
          _requestSection(context),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: _copyLabel,
            icon: _copied ? Icons.check_outlined : Icons.copy_outlined,
            isFullWidth: true,
            onPressed: _copyAddress,
          ),
          // Liquid CT addresses stay stable — no regenerate there.
          if (_selectedAsset == 'BTC') ...[
            const SizedBox(height: AppSpacing.sm),
            SecondaryButton(
              label: 'New address',
              icon: Icons.refresh_outlined,
              isFullWidth: true,
              onPressed: _newAddress,
            ),
          ],
          if (_canVerifyOnDevice) ...[
            const SizedBox(height: AppSpacing.sm),
            _HwVerify(
              verifying: _verifying,
              verified: _verified,
              error: _hwError,
              onVerify: _verifyOnDevice,
            ),
          ],
        ],
      ),
    );
  }

  /// The desktop list of previous addresses: the newest eight as table rows,
  /// and one quiet action to the page that lists every one.
  Widget _desktopPreviousCard(BuildContext context) {
    final s = AppScheme.of(context);
    final useSats = context.select<AppState, bool>((st) => st.useSats);
    final previous = _previousNewestFirst;
    final shown = previous.take(_previousPreview).toList();
    return SectionCard(
      title: 'Previous addresses',
      action: previous.isEmpty
          ? null
          : GhostButton(label: 'Show all', onPressed: _openAllAddresses),
      padding: previous.isEmpty
          ? null
          : const EdgeInsets.only(bottom: AppSpacing.xs),
      child: previous.isEmpty
          ? Text(
              'No previous addresses',
              style: AppTypography.body.copyWith(color: s.inkSecondary),
            )
          : AddressTable(
              rows: [
                for (final a in shown)
                  AddressTableRow(info: a, useSats: useSats, coin: _ticker),
              ],
            ),
    );
  }

  /// One column for a 379 dp content column: the QR card and its actions,
  /// the request, then the previous addresses as one list group.
  Widget _phoneBody(BuildContext context) {
    final s = AppScheme.of(context);
    final previous = _previousNewestFirst;
    final preview = previous.take(_previousPreview).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Reveal(
          child: FormCard(
            padding: const EdgeInsets.all(AppSpacing.cardPaddingSmall),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: _QrTile(
                    data: _shareData,
                    side: AppLayout.qrSide(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _AddressWell(info: _current!),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _caption,
                  style: AppTypography.caption.copyWith(color: s.inkFaint),
                ),
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: _copyLabel,
                  icon: _copied ? Icons.check_outlined : Icons.copy_outlined,
                  isFullWidth: true,
                  onPressed: _copyAddress,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    // Liquid CT addresses stay stable — no regenerate there.
                    if (_selectedAsset == 'BTC') ...[
                      Expanded(
                        child: SecondaryButton(
                          label: 'New address',
                          icon: Icons.refresh_outlined,
                          isFullWidth: true,
                          onPressed: _newAddress,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      child: SecondaryButton(
                        label: 'Share',
                        icon: Icons.share_outlined,
                        isFullWidth: true,
                        onPressed: _shareAddress,
                      ),
                    ),
                  ],
                ),
                if (_canVerifyOnDevice) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _HwVerify(
                    verifying: _verifying,
                    verified: _verified,
                    error: _hwError,
                    onVerify: _verifyOnDevice,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Reveal(
          delay: 1,
          child: FormCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.cardPaddingSmall,
              vertical: AppSpacing.xs,
            ),
            child: _requestSection(context),
          ),
        ),
        // Liquid's one address is the card above; nothing to list under it.
        if (_hasPreviousList) ...[
          const SizedBox(height: AppSpacing.xl),
          Reveal(
            delay: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ListSectionLabel(label: 'Previous addresses'),
                ListCard(
                  children: [
                    if (previous.isEmpty)
                      const ListRow(
                        icon: Icons.inbox_outlined,
                        title: 'No previous addresses',
                      )
                    else ...[
                      for (final a in preview) _previousRow(context, a),
                      ListRow(
                        icon: Icons.list_outlined,
                        title: 'All addresses',
                        chevron: true,
                        onTap: _openAllAddresses,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// One previous address as a phone list row. The whole row opens the
  /// address — its QR, a copy button, its label — so nothing small has to
  /// be hit.
  Widget _previousRow(BuildContext context, AddressInfo a) {
    final s = AppScheme.of(context);
    final useSats = context.select<AppState, bool>((st) => st.useSats);
    final funded = a.receivedSats > 0;
    final short = shortAddress(a.address, head: 10, tail: 8);
    final figure = receivedFigure(
      a.receivedSats,
      useSats: useSats,
      coin: _ticker,
    );
    return ListenableBuilder(
      listenable: AddressLabelStore.instance,
      builder: (context, _) {
        final label = addressLabelOf(a);
        return ListRow(
          // The glyph Activity gives an incoming transaction: an address is
          // where money arrives.
          icon: Icons.call_received_outlined,
          // A labelled address leads with its tag, in its own colour; an
          // unlabelled one has nothing to lead with but itself.
          title: label ?? short,
          titleWidget: label == null
              ? null
              : AddressTag(label: label, hue: addressHueOf(s, a.address)),
          subtitle: label == null ? '#${a.index}' : '#${a.index} · $short',
          trailing: funded
              ? ListAmount(
                  value: figure.value,
                  unit: figure.unit,
                  maxWidth: 128,
                )
              : Icon(
                  Icons.chevron_right_outlined,
                  size: AppSpacing.icon,
                  color: s.inkFaint,
                ),
          onTap: () => showAddressDetail(
            context,
            info: a,
            coin: _ticker,
            useSats: useSats,
          ),
        );
      },
    );
  }
}

/// The closed face of the request: one row, a title and what is asked for,
/// and a chevron that turns. The glyph stays in the secondary ink whether or
/// not something is asked for — the subtitle carries that fact.
class _RequestHeader extends StatefulWidget {
  const _RequestHeader({
    required this.open,
    required this.summary,
    required this.onTap,
  });

  final bool open;
  final String? summary;
  final VoidCallback onTap;

  @override
  State<_RequestHeader> createState() => _RequestHeaderState();
}

class _RequestHeaderState extends State<_RequestHeader> {
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final summary = widget.summary;
    return Semantics(
      button: true,
      expanded: widget.open,
      label: 'Request an amount',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
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
          child: Container(
            constraints: BoxConstraints(
              minHeight: phone ? AppLayout.minTouchTarget : 0,
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            foregroundDecoration: _focus
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(color: s.focus, width: 2),
                  )
                : null,
            child: Row(
              children: [
                Icon(
                  Icons.request_quote_outlined,
                  size: AppSpacing.icon,
                  color: s.inkSecondary,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request an amount',
                        style: AppTypography.bodyOf(
                          context,
                        ).copyWith(color: s.ink),
                      ),
                      Text(
                        summary ?? 'Optional — adds it to the QR and the link',
                        style: AppTypography.caption.copyWith(
                          color: summary == null ? s.inkFaint : s.inkSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: widget.open ? 0.5 : 0,
                  duration: AppMotion.of(context, AppMotion.quick),
                  curve: AppMotion.settle,
                  child: Icon(
                    Icons.expand_more_outlined,
                    size: AppSpacing.icon,
                    color: s.inkFaint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A failed load: what went wrong in the engine's words, and a retry.
class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: AppSpacing.icon, color: s.danger),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              message,
              style: AppTypography.body.copyWith(color: s.inkSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: 'Retry',
              icon: Icons.refresh_outlined,
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Drops the transport wrappers ("Exception: wallet-ffi: …") so the phone's
/// error view leads with the backend's own sentence.
String _plainError(String raw) {
  var msg = raw.trim();
  for (final prefix in const ['Exception: ', 'wallet-ffi: ']) {
    if (msg.startsWith(prefix)) msg = msg.substring(prefix.length).trim();
  }
  return msg;
}

/// The QR on a white square in both themes: a code needs its quiet zone,
/// and a camera reads dark modules on white. No glow, no shadow — the
/// square is the frame.
class _QrTile extends StatelessWidget {
  const _QrTile({required this.data, required this.side});

  final String data;
  final double side;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      // The payload is this QR's identity: a new one is a different code,
      // not a repaint of the old. It is also the only way a test can read
      // back what a payer's camera would — the package keeps `data` private.
      //
      // The frame is pinned to [side] on both axes: a longer payload means
      // more modules inside the same square, never a bigger square.
      child: SizedBox.square(
        dimension: side,
        child: QrImageView(
          key: ValueKey<String>(data),
          data: data,
          version: QrVersions.auto,
          size: side,
          padding: EdgeInsets.zero,
          semanticsLabel: 'Receive address QR code',
        ),
      ),
    );
  }
}

/// "Verify on Ledger": a secondary action, its outcome stated under it — a
/// short status in the success ink, or the device's error in a banner.
class _HwVerify extends StatelessWidget {
  const _HwVerify({
    required this.verifying,
    required this.verified,
    required this.error,
    required this.onVerify,
  });

  final bool verifying;
  final bool verified;
  final String? error;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    if (verified) {
      return SizedBox(
        height: AppSpacing.controlHeight,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: AppSpacing.iconSmall,
              color: s.success,
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Address confirmed on device',
              style: AppTypography.label.copyWith(color: s.ink),
            ),
          ],
        ),
      );
    }
    final button = SecondaryButton(
      label: verifying ? 'Confirm on Ledger…' : 'Verify on Ledger',
      icon: Icons.usb_outlined,
      isLoading: verifying,
      isFullWidth: true,
      onPressed: onVerify,
    );
    final e = error;
    if (e == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DangerBanner(message: e),
        const SizedBox(height: AppSpacing.sm),
        button,
      ],
    );
  }
}

/// The address in the `well`: its label as a tag above it — or the dashed
/// "add label" tag when it has none — then `mono` in the primary ink,
/// selectable, wrapping to as many lines as it needs (two for a bech32
/// address), with the copy control at the edge. The copy turns into a check
/// for a moment.
class _AddressWell extends StatefulWidget {
  const _AddressWell({required this.info});
  final AddressInfo info;

  @override
  State<_AddressWell> createState() => _AddressWellState();
}

class _AddressWellState extends State<_AddressWell> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.info.address));
    if (!mounted) return;
    confirmCopyOnPhone(context);
    setState(() => _copied = true);
    await Future.delayed(kCopiedFor);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone ? AppLayout.minTouchTarget : AppSpacing.xxl;
    Widget action(IconData icon, String tooltip, VoidCallback onPressed) =>
        SizedBox.square(
          dimension: side,
          child: IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            iconSize: phone ? 20 : AppSpacing.iconSmall,
            color: s.inkSecondary,
            icon: Icon(icon),
          ),
        );
    void editLabel() => showAddressLabelPrompt(
      context,
      address: widget.info.address,
      index: widget.info.index,
    );
    return ListenableBuilder(
      listenable: AddressLabelStore.instance,
      builder: (context, _) {
        final label = addressLabelOf(widget.info);
        return DataWell(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The label is a tag in the address's own colour, and
                    // its own editor; an address without one says so with
                    // a dashed tag, so "this can be labelled" is on screen
                    // and not behind an icon.
                    if (label == null)
                      AddAddressTag(onTap: editLabel, label: 'Add label')
                    else
                      AddressTag(
                        label: label,
                        hue: addressHueOf(s, widget.info.address),
                        onTap: editLabel,
                        tooltip: 'Edit label',
                      ),
                    SizedBox(height: phone ? 0 : AppSpacing.sm),
                    SelectableText(
                      widget.info.address,
                      style: AppTypography.mono.copyWith(color: s.ink),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              action(
                _copied ? Icons.check_outlined : Icons.copy_outlined,
                _copied ? 'Copied' : 'Copy address',
                _copy,
              ),
            ],
          ),
        );
      },
    );
  }
}
