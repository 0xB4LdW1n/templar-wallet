// Every address a chain of this wallet has handed out, with what each one
// received. Receive shows the newest eight; the rest live here, so the page
// that exists to hand over ONE address never turns into a ledger.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/address_tag.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/chain_switch.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../services/address_label_store.dart';
import 'address_dialogs.dart';
import 'address_rows.dart';
import 'models/address_info.dart';

class ReceiveAddressesScreen extends StatefulWidget {
  const ReceiveAddressesScreen({super.key, required this.asset, this.bridge});

  /// `BTC` or `LBTC` — the chain whose addresses are listed first. The page's
  /// own chain switch can move to the other one.
  final String asset;

  /// Test seam, as on [ReceiveScreen]: null in the app.
  final WalletBridge? bridge;

  @override
  State<ReceiveAddressesScreen> createState() => _ReceiveAddressesScreenState();
}

class _ReceiveAddressesScreenState extends State<ReceiveAddressesScreen> {
  late final WalletBridge _bridge = widget.bridge ?? walletBridge;

  /// The chain on screen: the route's to begin with, then the switch's.
  late String _asset = widget.asset;

  /// Newest first: the current unused address leads, then every previous
  /// one by descending index — the ones most likely still in use on top.
  List<AddressInfo> _all = const [];
  AddressInfo? _current;
  bool _loading = true;
  String? _error;

  /// Bumped by every [_load]; an answer for a chain the user has since
  /// switched away from is dropped.
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    AddressLabelStore.instance.load();
    _load();
  }

  @override
  void didUpdateWidget(ReceiveAddressesScreen old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset && widget.asset != _asset) {
      _switchAsset(widget.asset);
    }
  }

  Future<void> _load() async {
    final asset = _asset;
    final token = ++_loadSeq;
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    setState(() {
      _loading = true;
      _error = null;
    });
    bool stale() => !mounted || token != _loadSeq;
    try {
      // `fresh: false` re-reads the current unused address; nothing is
      // derived by opening this page.
      final current = await _bridge.generateReceiveAddress(walletId, asset);
      final previous = await _bridge.listPreviousAddresses(walletId, asset);
      if (stale()) return;
      final sorted = [...previous]..sort((a, b) => b.index.compareTo(a.index));
      setState(() {
        _current = current;
        _all = [current, ...sorted.where((a) => a.address != current.address)];
        _loading = false;
      });
    } catch (e) {
      if (stale()) return;
      setState(() {
        _loading = false;
        _error = _plainError(e.toString());
      });
    }
  }

  void _switchAsset(String asset) {
    if (asset == _asset) return;
    setState(() {
      _asset = asset;
      _all = const [];
      _current = null;
    });
    _load();
  }

  String get _coin => _asset == 'BTC' ? 'BTC' : 'LBTC';

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final st = context.watch<AppState>();
    final useSats = st.useSats;
    final funded = _all.where((a) => a.receivedSats > 0).toList();
    final totalSats = funded.fold<int>(0, (sum, a) => sum + a.receivedSats);
    final total = receivedFigure(totalSats, useSats: useSats, coin: _coin);
    final summary = _loading || _error != null
        ? null
        : '${_all.length} address${_all.length == 1 ? '' : 'es'} · '
              '${funded.length} used · ${total.value} ${total.unit} received';

    final chainSwitch = st.activeWalletBitcoin && st.activeWalletLiquid
        ? ChainSwitch<String>(
            selected: _asset,
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
      body = Center(
        child: Column(
          children: [
            Icon(Icons.error_outline, size: AppSpacing.icon, color: s.danger),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(
              _error!,
              style: AppTypography.body.copyWith(color: s.inkSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: 'Retry',
              icon: Icons.refresh_outlined,
              onPressed: _load,
            ),
          ],
        ),
      );
    } else if (phone) {
      body = ListCard(
        children: [
          for (final a in _all)
            _PhoneAddressRow(
              info: a,
              isCurrent: a.address == _current?.address,
              useSats: useSats,
              coin: _coin,
            ),
        ],
      );
    } else {
      body = SectionCard(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: AddressTable(
          header: const AddressTableHeader(withStatus: true),
          rows: [
            for (final a in _all)
              AddressTableRow(
                info: a,
                useSats: useSats,
                coin: _coin,
                status: _StatusTag(
                  isCurrent: a.address == _current?.address,
                  used: a.receivedSats > 0,
                ),
                statusLabel: _stateWord(
                  isCurrent: a.address == _current?.address,
                  used: a.receivedSats > 0,
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: PageBackground.flat(
        child: ListView(
          padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
          children: [
            // The phone shell's header already says "‹ All addresses"; the
            // desktop page names itself and offers the way back.
            if (phone) ...[
              if (chainSwitch != null) ...[
                chainSwitch,
                const SizedBox(height: AppSpacing.lg),
              ],
              if (summary != null) ...[
                Text(
                  summary,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
            ] else
              PageHeader(
                title: 'All addresses',
                subtitle: summary,
                actions: [
                  GhostButton(
                    label: 'Back to Receive',
                    icon: Icons.arrow_back_outlined,
                    onPressed: () => context.go(AppRoutes.receive),
                  ),
                  ?chainSwitch,
                ],
              ),
            body,
          ],
        ),
      ),
    );
  }
}

/// Current / used / unused, as a quiet tag. Current is the one Receive is
/// showing now; used means something arrived at it.
class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.isCurrent, required this.used});

  final bool isCurrent;
  final bool used;

  @override
  Widget build(BuildContext context) => QuietTag(
    label: isCurrent
        ? 'Current'
        : used
        ? 'Used'
        : 'Unused',
  );
}

/// The state of an address as one word.
String _stateWord({required bool isCurrent, required bool used}) => isCurrent
    ? 'Current'
    : used
    ? 'Used'
    : 'Unused';

/// One address as a phone list row: the label (or the shortened address)
/// leads, the index and state follow, the right column says what it
/// received. Tapping opens the address — its QR, a copy button, its label.
class _PhoneAddressRow extends StatelessWidget {
  const _PhoneAddressRow({
    required this.info,
    required this.isCurrent,
    required this.useSats,
    required this.coin,
  });

  final AddressInfo info;
  final bool isCurrent;
  final bool useSats;
  final String coin;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final a = info;
    final funded = a.receivedSats > 0;
    final short = shortAddress(a.address, head: 10, tail: 8);
    final state = _stateWord(isCurrent: isCurrent, used: funded);
    final figure = receivedFigure(a.receivedSats, useSats: useSats, coin: coin);
    return ListenableBuilder(
      listenable: AddressLabelStore.instance,
      builder: (context, _) {
        final label = addressLabelOf(a);
        return ListRow(
          icon: isCurrent
              ? Icons.qr_code_2_outlined
              : Icons.call_received_outlined,
          title: label ?? short,
          titleWidget: label == null
              ? null
              : AddressTag(label: label, hue: addressHueOf(s, a.address)),
          subtitle: label == null
              ? '#${a.index} · $state'
              : '#${a.index} · $state · $short',
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
            coin: coin,
            useSats: useSats,
            status: state,
          ),
        );
      },
    );
  }
}

String _plainError(String raw) {
  var msg = raw.trim();
  for (final prefix in const ['Exception: ', 'wallet-ffi: ']) {
    if (msg.startsWith(prefix)) msg = msg.substring(prefix.length).trim();
  }
  return msg;
}
