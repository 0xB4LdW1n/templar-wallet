// The pieces Receive and All addresses share: how an address is shortened,
// how what it received is written, and the desktop table row both pages
// list addresses with — so `#2 #3 #10` sit in the same column on both.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/address_label_store.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/address_tag.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'address_dialogs.dart';
import 'models/address_info.dart';

/// How long a copy control shows its check (design.md, "Code box").
const Duration kCopiedFor = Duration(milliseconds: 1500);

/// Middle-ellipsised address; short strings pass through. Both ends stay,
/// because they are what a person compares.
String shortAddress(String address, {int head = 12, int tail = 8}) {
  if (address.length <= head + tail + 1) return address;
  return '${address.substring(0, head)}…'
      '${address.substring(address.length - tail)}';
}

/// What an address received, split into the figure and its unit so the unit
/// can sit beside it one step quieter. In the user's unit: grouped sats
/// (`1,234,567` `sats`) or the coin with eight decimals.
({String value, String unit}) receivedFigure(
  int sats, {
  required bool useSats,
  required String coin,
}) {
  final text = PriceService.formatUnit(sats, sat: useSats, coin: coin);
  final space = text.lastIndexOf(' ');
  if (space < 0) return (value: text, unit: useSats ? 'sats' : coin);
  return (value: text.substring(0, space), unit: text.substring(space + 1));
}

/// Phone copy receipt: a light haptic and a floating snack bar. The thumb
/// covers whatever control just turned into a check, and Android 12 and
/// below show no toast of their own for a clipboard write.
void confirmCopyOnPhone(BuildContext context) {
  if (!AppLayout.isPhone(context)) return;
  HapticFeedback.lightImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      const SnackBar(
        content: Text('Address copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
}

/// Column widths of the desktop address table. Fixed, so a column of rows
/// reads as a table and not as a run of sentences.
abstract final class AddressColumns {
  static const double index = 48;
  static const double label = 136;
  static const double status = 72;
  static const double received = 136;

  /// One icon control at the end of a row.
  static const double action = 32;

  /// The three of them: label, QR, copy.
  static const double actions = 3 * action;
  static const double gap = AppSpacing.md;

  /// Under this row width there is no room for a label column: the row
  /// becomes two lines, the label over the address, so both stay readable.
  static const double labelFoldsUnder = 520;

  /// Height of a one-line row, and of the two-line one.
  static const double rowHeight = 48;
  static const double rowHeightFolded = 56;
}

/// The quiet head of the desktop address table: `eyebrow` in the faint ink,
/// one per column, aligned with the cells under it.
class AddressTableHeader extends StatelessWidget {
  const AddressTableHeader({super.key, this.withStatus = false});

  final bool withStatus;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final style = AppTypography.eyebrow.copyWith(color: s.inkFaint);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.cardPadding,
        vertical: AppSpacing.sm,
      ),
      child: LayoutBuilder(
        builder: (context, c) => Row(
          children: [
            SizedBox(
              width: AddressColumns.index,
              child: Text('Index', style: style),
            ),
            const SizedBox(width: AddressColumns.gap),
            Expanded(child: Text('Address', style: style)),
            if (c.maxWidth >= AddressColumns.labelFoldsUnder) ...[
              const SizedBox(width: AddressColumns.gap),
              SizedBox(
                width: AddressColumns.label,
                child: Text('Label', style: style),
              ),
            ],
            if (withStatus) ...[
              const SizedBox(width: AddressColumns.gap),
              SizedBox(
                width: AddressColumns.status,
                child: Text('Status', style: style),
              ),
            ],
            const SizedBox(width: AddressColumns.gap),
            SizedBox(
              width: AddressColumns.received,
              child: Text('Received', style: style, textAlign: TextAlign.end),
            ),
            const SizedBox(width: AppSpacing.xs + AddressColumns.actions),
          ],
        ),
      ),
    );
  }
}

/// One address as a desktop table row, 48 tall: index, address (shortened
/// in the middle to the room it has), its label as a tag in the address's
/// colour, an optional status tag, what it received, and its three controls
/// — label it, show its QR, copy it. The whole row copies too; the tag
/// edits the label and its colour.
class AddressTableRow extends StatefulWidget {
  const AddressTableRow({
    super.key,
    required this.info,
    required this.useSats,
    required this.coin,
    this.status,
    this.statusLabel,
  });

  final AddressInfo info;
  final bool useSats;

  /// The chain's whole-coin unit: `BTC` or `LBTC`.
  final String coin;

  /// A quiet tag in its own column (All addresses: current / used / unused).
  final Widget? status;

  /// The same state as a word, for the address's detail.
  final String? statusLabel;

  @override
  State<AddressTableRow> createState() => _AddressTableRowState();
}

class _AddressTableRowState extends State<AddressTableRow> {
  bool _copied = false;
  bool _hover = false;

  /// IBM Plex Mono advances 0.6 em: 7.8 px at the 13 px `mono` size. Used to
  /// fit the address to its column without measuring every frame.
  static const double _monoAdvance = 7.8;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.info.address));
    if (!mounted) return;
    confirmCopyOnPhone(context);
    setState(() => _copied = true);
    await Future.delayed(kCopiedFor);
    if (mounted) setState(() => _copied = false);
  }

  void _editLabel() => showAddressLabelPrompt(
    context,
    address: widget.info.address,
    index: widget.info.index,
  );

  void _showQr() => showAddressDetail(
    context,
    info: widget.info,
    coin: widget.coin,
    useSats: widget.useSats,
    status: widget.statusLabel,
  );

  Widget _action({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) => SizedBox.square(
    dimension: AddressColumns.action,
    child: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      iconSize: AppSpacing.iconSmall,
      color: AppScheme.of(context).inkSecondary,
      icon: Icon(icon),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AddressLabelStore.instance,
    builder: (context, _) => _row(context),
  );

  Widget _row(BuildContext context) {
    final s = AppScheme.of(context);
    final a = widget.info;
    final funded = a.receivedSats > 0;
    final figure = receivedFigure(
      a.receivedSats,
      useSats: widget.useSats,
      coin: widget.coin,
    );
    final label = addressLabelOf(a);
    // The label is a tag in the address's own colour, and its own editor.
    final Widget? tag = label == null
        ? null
        : AddressTag(
            label: label,
            hue: addressHueOf(s, a.address),
            onTap: _editLabel,
            tooltip: 'Edit label',
          );

    Widget cells(bool withLabel) => Row(
      children: [
        SizedBox(
          width: AddressColumns.index,
          child: Text(
            '#${a.index}',
            style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
          ),
        ),
        const SizedBox(width: AddressColumns.gap),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final fit = (c.maxWidth / _monoAdvance).floor();
              final text = a.address.length <= fit
                  ? a.address
                  : shortAddress(
                      a.address,
                      head: ((fit - 1) / 2).ceil().clamp(4, 40),
                      tail: ((fit - 1) / 2).floor().clamp(4, 40),
                    );
              final address = Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style:
                    (withLabel || tag == null
                            ? AppTypography.mono
                            : AppTypography.monoSmall)
                        .copyWith(
                          color: withLabel || tag == null
                              ? s.ink
                              : s.inkSecondary,
                        ),
              );
              // Folded: the tag leads and the address goes under it.
              if (withLabel || tag == null) return address;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [tag, const SizedBox(height: 2), address],
              );
            },
          ),
        ),
        if (withLabel) ...[
          const SizedBox(width: AddressColumns.gap),
          SizedBox(
            width: AddressColumns.label,
            // The tag is its own editor; an address without one offers the
            // dashed "add" tag under the pointer.
            child: Align(
              alignment: Alignment.centerLeft,
              child:
                  tag ??
                  (_hover
                      ? AddAddressTag(onTap: _editLabel)
                      : const SizedBox.shrink()),
            ),
          ),
        ],
        if (widget.status != null) ...[
          const SizedBox(width: AddressColumns.gap),
          SizedBox(
            width: AddressColumns.status,
            child: Align(alignment: Alignment.centerLeft, child: widget.status),
          ),
        ],
        const SizedBox(width: AddressColumns.gap),
        SizedBox(
          width: AddressColumns.received,
          child: funded
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        figure.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: AppTypography.numericSmall.copyWith(
                          color: s.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      figure.unit,
                      style: AppTypography.numericSmall.copyWith(
                        color: s.inkFaint,
                      ),
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(width: AppSpacing.xs),
        _action(
          icon: Icons.label_outlined,
          tooltip: label == null ? 'Add label' : 'Edit label',
          onPressed: _editLabel,
        ),
        _action(
          icon: Icons.qr_code_2_outlined,
          tooltip: 'Show QR',
          onPressed: _showQr,
        ),
        _action(
          icon: _copied ? Icons.check_outlined : Icons.copy_outlined,
          tooltip: _copied ? 'Copied' : 'Copy address',
          onPressed: _copy,
        ),
      ],
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _copy,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.instant),
          curve: AppMotion.settle,
          color: _hover ? s.hover : Colors.transparent,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
          ),
          child: LayoutBuilder(
            builder: (context, c) {
              final wide = c.maxWidth >= AddressColumns.labelFoldsUnder;
              return SizedBox(
                height: wide
                    ? AddressColumns.rowHeight
                    : AddressColumns.rowHeightFolded,
                child: cells(wide),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Rows with a hairline between each, flush to the card's edges.
class AddressTable extends StatelessWidget {
  const AddressTable({super.key, required this.rows, this.header});

  final List<Widget> rows;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null) ...[
          header!,
          Divider(height: 1, thickness: 1, color: s.edge),
        ],
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: s.edge),
          rows[i],
        ],
      ],
    );
  }
}
