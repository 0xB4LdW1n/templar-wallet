// "Use my own address": one window to pick an address of this wallet as a
// recipient — the next unused one, or any that already received — each under
// the label and the colour Receive gave it.
//
// It is the transaction detail's window (history_screen.dart): the dialog
// material at the same width, a short head, rows, and a list that scrolls
// inside it instead of growing the window with the wallet's history. A
// phone gets it as a sheet.

import 'package:flutter/material.dart';

import '../../bridge/wallet_bridge.dart';
import '../../services/address_label_store.dart';
import '../../shared/widgets/address_tag.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../receive/address_dialogs.dart' show addressLabelOf;
import '../receive/address_rows.dart' show receivedFigure, shortAddress;
import '../receive/models/address_info.dart';

/// Opens the picker and returns the address chosen, or null when the user
/// backed out. [asset] is `BTC` or `LBTC`. Nothing is derived by opening
/// it: the unused address is the one Receive is already showing.
Future<String?> showOwnAddressPicker(
  BuildContext context, {
  required WalletBridge bridge,
  required String walletId,
  required String asset,
  required bool useSats,
}) {
  return showAppDialog<String>(
    context,
    builder: (_) => _OwnAddressDialog(
      bridge: bridge,
      walletId: walletId,
      asset: asset,
      useSats: useSats,
    ),
  );
}

class _OwnAddressDialog extends StatefulWidget {
  const _OwnAddressDialog({
    required this.bridge,
    required this.walletId,
    required this.asset,
    required this.useSats,
  });

  final WalletBridge bridge;
  final String walletId;
  final String asset;
  final bool useSats;

  @override
  State<_OwnAddressDialog> createState() => _OwnAddressDialogState();
}

class _OwnAddressDialogState extends State<_OwnAddressDialog> {
  /// The list scrolls inside the window past this many rows.
  static const int _visibleRows = 5;

  AddressInfo? _unused;
  List<AddressInfo> _used = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AddressLabelStore.instance.load();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final unused = await widget.bridge.generateReceiveAddress(
        widget.walletId,
        widget.asset,
      );
      final previous = await widget.bridge.listPreviousAddresses(
        widget.walletId,
        widget.asset,
      );
      if (!mounted) return;
      setState(() {
        _unused = unused;
        // Newest first: the ones most likely still in use on top.
        _used = previous.where((a) => a.address != unused.address).toList()
          ..sort((a, b) => b.index.compareTo(a.index));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('wallet-ffi: ', '');
      });
    }
  }

  String get _coin => widget.asset == 'BTC' ? 'BTC' : 'LBTC';

  /// One address: its tag (or the address itself, when it has no label),
  /// its index, and what it received. Tapping it picks it.
  Widget _row(BuildContext context, AddressInfo a) {
    final s = AppScheme.of(context);
    final label = addressLabelOf(a);
    final short = shortAddress(a.address, head: 12, tail: 8);
    final figure = receivedFigure(
      a.receivedSats,
      useSats: widget.useSats,
      coin: _coin,
    );
    return ListRow(
      icon: Icons.call_received_outlined,
      title: label ?? short,
      titleWidget: label == null
          ? null
          : AddressTag(label: label, hue: addressHueOf(s, a.address)),
      subtitle: label == null ? '#${a.index}' : '#${a.index} · $short',
      trailing: a.receivedSats > 0
          ? ListAmount(value: figure.value, unit: figure.unit, maxWidth: 128)
          : null,
      onTap: () => Navigator.of(context).pop(a.address),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    Widget eyebrow(String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
      ),
    );

    final Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: SizedBox(
            width: AppSpacing.xl,
            height: AppSpacing.xl,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    } else if (_error != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _error!,
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          SecondaryButton(
            label: 'Retry',
            icon: Icons.refresh_outlined,
            onPressed: _load,
          ),
        ],
      );
    } else {
      final unused = _unused!;
      final used = _used;
      body = ListenableBuilder(
        // A label written in Receive (or in another window) lands here.
        listenable: AddressLabelStore.instance,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            eyebrow('Unused'),
            ListCard(children: [_row(context, unused)]),
            const SizedBox(height: AppSpacing.lg),
            eyebrow(used.isEmpty ? 'Used' : 'Used · ${used.length}'),
            if (used.isEmpty)
              Text(
                'No used addresses yet',
                style: AppTypography.body.copyWith(color: s.inkSecondary),
              )
            else if (phone)
              // The sheet already scrolls; a nested list would fight it.
              ListCard(children: [for (final a in used) _row(context, a)])
            else
              _ScrollingCard(
                maxHeight: _visibleRows * AppSpacing.rowHeight,
                children: [for (final a in used) _row(context, a)],
              ),
          ],
        ),
      );
    }

    return AppDialog(
      title: const Text('Use my own address'),
      scrollable: true,
      content: SizedBox(width: phone ? null : 480, child: body),
      actions: [
        SecondaryButton(
          label: 'Close',
          isFullWidth: phone,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// A [ListCard] that keeps to [maxHeight] and scrolls its rows inside its
/// own corners, with a scrollbar when there is more than fits.
class _ScrollingCard extends StatefulWidget {
  const _ScrollingCard({required this.children, required this.maxHeight});

  final List<Widget> children;
  final double maxHeight;

  @override
  State<_ScrollingCard> createState() => _ScrollingCardState();
}

class _ScrollingCardState extends State<_ScrollingCard> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final rows = widget.children;
    return Container(
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Scrollbar(
        controller: _scroll,
        child: ListView.separated(
          controller: _scroll,
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: rows.length,
          separatorBuilder: (_, _) => Divider(
            height: 1,
            thickness: 1,
            color: s.edge,
            indent: kListTextInset,
          ),
          itemBuilder: (_, i) => rows[i],
        ),
      ),
    );
  }
}
