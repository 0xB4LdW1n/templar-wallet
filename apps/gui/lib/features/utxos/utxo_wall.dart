// Coins under the address they sit on: a card per address.
//
// A coin does not float in the wallet: it sits on an address, and two coins
// on one address are tied together on-chain for anyone to see. So coins are
// kept under their address (design.md, "The moments") — the address is the
// parent, its coins are what is in it.
//
// Each address is a card of its own, the cards one under the other: a head
// that names the address — its colour, its label, the address itself, how
// many coins it holds and what they add up to — then its coins, as notes on
// the wall ([AddressTray]) or as rows in a list ([AddressCoinGroup]). An
// address that was paid twice is one card with two notes, which is the fact
// a list of outpoints never shows.
//
// An address is grey until the user gives it a colour; the colour and the
// label are the ones Receive gives it, so a card here and a row there are
// visibly the same address.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/address_label_store.dart';
import '../../shared/widgets/address_tag.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/utxo_views.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'models/utxo.dart';

/// The coins that sit on one address, as indices into the screen's list.
class AddressGroup {
  const AddressGroup({
    required this.address,
    required this.indices,
    required this.total,
  });

  /// Null when the engine named no address for these coins.
  final String? address;

  /// Settled coins first, largest first, then what is still arriving.
  final List<int> indices;

  /// Sum of the coins' amounts, for ordering the cards.
  final int total;
}

/// [utxos] grouped by the address they sit on: the fullest address first,
/// and inside one the settled coins by size, then the ones on their way.
List<AddressGroup> groupCoinsByAddress(List<Utxo> utxos) {
  final byAddress = <String?, List<int>>{};
  for (var i = 0; i < utxos.length; i++) {
    final a = utxos[i].address;
    byAddress.putIfAbsent(a == null || a.isEmpty ? null : a, () => []).add(i);
  }
  final groups = [
    for (final e in byAddress.entries)
      AddressGroup(
        address: e.key,
        indices: e.value
          ..sort((a, b) {
            final ua = utxos[a];
            final ub = utxos[b];
            if (ua.isPending != ub.isPending) return ua.isPending ? 1 : -1;
            return ub.amount.compareTo(ua.amount);
          }),
        total: e.value.fold<int>(0, (sum, i) => sum + utxos[i].amount),
      ),
  ];
  // A stable order for equal totals: the engine's own.
  final order = {for (var i = 0; i < groups.length; i++) groups[i]: i};
  groups.sort((a, b) {
    final byTotal = b.total.compareTo(a.total);
    return byTotal != 0 ? byTotal : order[a]!.compareTo(order[b]!);
  });
  return groups;
}

/// What [coins] add up to, as `0.00750000 BTC` — null when they are not one
/// asset counted in BTC units, where a sum would add apples to pears.
String? coinSumText(List<Utxo> coins) {
  if (coins.isEmpty) return null;
  final keys = coins.map(utxoAssetKey).toSet();
  if (keys.length != 1 || !coins.first.isBtcLike) return null;
  final sats = coins.fold<int>(0, (sum, u) => sum + u.amount);
  final unit = coins.first.ticker ?? 'BTC';
  return '${(sats / 1e8).toStringAsFixed(8)} $unit';
}

/// `1 coin`, `3 coins`.
String coinCountText(int count) => count == 1 ? '1 coin' : '$count coins';

/// Space between two notes in a card, along a line and between two lines.
const double kTrayPad = AppSpacing.sm;

/// The address cards, one under the other ([AddressTray],
/// [AddressCoinGroup], [ConsolidationTray]).
class AddressCards extends StatelessWidget {
  const AddressCards({super.key, required this.children});

  final List<Widget> children;

  /// The space between two cards.
  static const double gap = AppSpacing.md;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: gap),
        children[i],
      ],
    ],
  );
}

/// The card of one address: [head] over a hairline over [body]. The card
/// itself is the kit's — panel, hairline, radius 12 — and wears no colour:
/// the address's colour is in its head.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.head, required this.body});

  final Widget head;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          Divider(height: 1, thickness: 1, color: s.edge),
          body,
        ],
      ),
    );
  }
}

/// The coins of one address as notes, in a card of its own: the wall's
/// form, on the coin screen and in Send's picker.
class AddressTray extends StatelessWidget {
  const AddressTray({
    super.key,
    required this.address,
    required this.notes,
    required this.count,
    this.total,
    this.onEditLabel,
  });

  /// Null when the engine named no address for these coins.
  final String? address;
  final List<Widget> notes;

  /// How many coins sit on the address.
  final int count;

  /// What they add up to, ready to print (masked by the caller); null when
  /// there is no one sum.
  final String? total;

  /// Opens the label prompt for the address.
  final VoidCallback? onEditLabel;

  @override
  Widget build(BuildContext context) => _AddressCard(
    address: address,
    count: count,
    total: total,
    onEditLabel: onEditLabel,
    body: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Wrap(spacing: kTrayPad, runSpacing: kTrayPad, children: notes),
    ),
  );
}

/// The coins of one address as rows, in a card of its own: the list's
/// form, on a phone and in Send's picker.
class AddressCoinGroup extends StatelessWidget {
  const AddressCoinGroup({
    super.key,
    required this.address,
    required this.rows,
    required this.count,
    this.total,
    this.onEditLabel,
    this.rowInset = 0,
  });

  /// Null when the engine named no address for these coins.
  final String? address;

  /// The coins on the address, as list rows.
  final List<Widget> rows;

  /// How many coins sit on the address.
  final int count;

  /// What they add up to, ready to print; null when there is no one sum.
  final String? total;
  final VoidCallback? onEditLabel;

  /// Where the hairline between two rows starts.
  final double rowInset;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return _AddressCard(
      address: address,
      count: count,
      total: total,
      onEditLabel: onEditLabel,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: s.edge, indent: rowInset),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// A card of one address with [body] under its head.
///
/// The head names the address: a swatch of its colour (grey until the user
/// picks one), its label as a tag of that colour, the address in mono, and
/// on the far side how many coins it holds and what they add up to. On a
/// desktop its two controls — label, copy — come with the pointer or the
/// focus, at the end of the head; the tag is its own editor at any time. On
/// a phone the head is two lines and the whole head opens the label prompt.
class _AddressCard extends StatefulWidget {
  const _AddressCard({
    required this.address,
    required this.count,
    required this.total,
    required this.onEditLabel,
    required this.body,
  });

  final String? address;
  final int count;
  final String? total;
  final VoidCallback? onEditLabel;
  final Widget body;

  @override
  State<_AddressCard> createState() => _AddressCardState();
}

class _AddressCardState extends State<_AddressCard> {
  bool _hover = false;
  bool _focusWithin = false;
  bool _copied = false;
  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final address = widget.address;
    if (address == null) return;
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final a = widget.address;
    final label = a == null ? null : AddressLabelStore.instance.labelFor(a);
    final count = coinCountText(widget.count);
    final total = widget.total;

    final card = _CardShell(
      head: phone
          ? _phoneHead(s, address: a, label: label, count: count)
          : _desktopHead(s, address: a, label: label, count: count),
      body: widget.body,
    );
    return Semantics(
      container: true,
      label: [
        if (label != null) 'Address $label' else 'Address',
        ?a,
        count,
        ?total,
      ].join(', '),
      // On a desktop the head's controls come with the pointer anywhere on
      // the card, or the focus anywhere in it.
      child: phone
          ? card
          : Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (v) => setState(() => _focusWithin = v),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hover = true),
                onExit: (_) => setState(() => _hover = false),
                child: card,
              ),
            ),
    );
  }

  Widget _desktopHead(
    AppScheme s, {
    required String? address,
    required String? label,
    required String count,
  }) {
    final edit = widget.onEditLabel;
    final total = widget.total;
    final shown = _hover || _focusWithin;
    final controls = address == null
        ? null
        : IgnorePointer(
            ignoring: !shown,
            child: AnimatedOpacity(
              opacity: shown ? 1 : 0,
              duration: AppMotion.of(context, AppMotion.instant),
              curve: AppMotion.settle,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (edit != null)
                    _HeadButton(
                      icon: Icons.label_outlined,
                      tooltip: label == null
                          ? 'Label this address'
                          : 'Edit address label',
                      onPressed: edit,
                    ),
                  _HeadButton(
                    icon: _copied ? Icons.check_outlined : Icons.copy_outlined,
                    tooltip: _copied ? 'Copied' : 'Copy address',
                    onPressed: _copy,
                    color: _copied ? s.success : null,
                  ),
                ],
              ),
            ),
          );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.md,
        ),
        child: Row(
          children: [
            _Swatch(address: address),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _AddressName(
                address: address,
                label: label,
                onEditLabel: edit,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            _Figures(count: count, total: total),
            if (controls != null) ...[
              const SizedBox(width: AppSpacing.sm),
              controls,
            ],
          ],
        ),
      ),
    );
  }

  Widget _phoneHead(
    AppScheme s, {
    required String? address,
    required String? label,
    required String count,
  }) {
    final edit = widget.onEditLabel;
    final total = widget.total;
    // Under the name: the address when a label stands for it, then the
    // count and the sum.
    final under = [
      if (address != null && label != null) shortCoinAddress(address),
      count,
      ?total,
    ].join(' · ');
    final head = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 60),
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: edit == null ? AppSpacing.md : 0,
          top: AppSpacing.sm,
          bottom: AppSpacing.sm,
        ),
        child: Row(
          children: [
            _Swatch(address: address),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _AddressName(address: address, label: label, oneName: true),
                  const SizedBox(height: 2),
                  Text(
                    under,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            if (edit != null)
              SizedBox.square(
                dimension: AppLayout.minTouchTarget,
                child: Icon(
                  Icons.label_outlined,
                  size: 20,
                  color: s.inkSecondary,
                ),
              ),
          ],
        ),
      ),
    );
    if (edit == null) return head;
    return Semantics(
      button: true,
      label: label == null ? 'Label this address' : 'Edit address label',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: edit,
          hoverColor: s.hover,
          highlightColor: s.pressed,
          splashFactory: NoSplash.splashFactory,
          child: head,
        ),
      ),
    );
  }
}

/// The address's colour, as a small square leading its head: grey until the
/// user picks one, iron for coins with no address.
class _Swatch extends StatelessWidget {
  const _Swatch({required this.address});

  final String? address;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final a = address;
    return AddressSwatch(
      hue: a == null ? s.edgeStrong : addressHueOf(s, a),
      size: 12,
    );
  }
}

/// How many coins and what they add up to: the count in the secondary ink,
/// the sum in the primary, both in tabular figures.
class _Figures extends StatelessWidget {
  const _Figures({required this.count, required this.total});

  final String count;
  final String? total;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final total = this.total;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          maxLines: 1,
          softWrap: false,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
        if (total != null) ...[
          const SizedBox(width: AppSpacing.md),
          Text(
            total,
            maxLines: 1,
            softWrap: false,
            style: AppTypography.numericSmall.copyWith(
              color: s.ink,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }
}

/// An address, shortened, in mono; the whole of it is its tooltip. [named]
/// when a label stands before it: the address is then the quieter of the
/// two.
class _AddressText extends StatelessWidget {
  const _AddressText(this.address, {required this.named});

  final String address;
  final bool named;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Tooltip(
      message: address,
      child: Text(
        shortCoinAddress(address),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: named
            ? AppTypography.monoSmall.copyWith(color: s.inkSecondary)
            : AppTypography.mono.copyWith(color: s.ink),
      ),
    );
  }
}

/// An address on one line: its label as a tag in the address's colour,
/// then the address; an address with no label is the address alone, in
/// ink. [oneName] prints only the first of the two (a phone's head puts the
/// address on the line under it).
class _AddressName extends StatelessWidget {
  const _AddressName({
    required this.address,
    required this.label,
    this.onEditLabel,
    this.oneName = false,
  });

  final String? address;
  final String? label;

  /// Makes the tag its own editor. Left null where the whole head already
  /// opens the label prompt.
  final VoidCallback? onEditLabel;
  final bool oneName;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final a = address;
    if (a == null) {
      return Text(
        'No address reported',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.body.copyWith(color: s.inkSecondary),
      );
    }
    final l = label;
    if (l == null) return _AddressText(a, named: false);
    final edit = onEditLabel;
    final tag = AddressTag(
      label: l,
      hue: addressHueOf(s, a),
      onTap: edit,
      tooltip: edit == null ? null : 'Edit address label',
    );
    if (oneName) return Align(alignment: Alignment.centerLeft, child: tag);
    return Row(
      children: [
        Flexible(child: tag),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: _AddressText(a, named: true)),
      ],
    );
  }
}

/// A consolidation in flight, in a card of its own at the head of the
/// cards: the coins it merges are gone and the one it makes has no block
/// yet, so the card names the transaction's coin instead of an address, and
/// its swatch is iron.
class ConsolidationTray extends StatelessWidget {
  const ConsolidationTray({
    super.key,
    required this.count,
    required this.displayAmount,
    required this.txid,
  });

  final int count;
  final String displayAmount;
  final String txid;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final head = ConstrainedBox(
      constraints: BoxConstraints(minHeight: phone ? 60 : 52),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: phone ? AppSpacing.md : AppSpacing.lg,
        ),
        child: Row(
          children: [
            const _Swatch(address: null),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'New coin, not confirmed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(color: s.inkSecondary),
              ),
            ),
          ],
        ),
      ),
    );
    return _CardShell(
      head: head,
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Align(
          alignment: Alignment.centerLeft,
          // The longest note: it stands for several coins, and its one line
          // of caption has to fit beside its seal.
          child: ConsolidatingNote(
            count: count,
            displayAmount: displayAmount,
            txid: txid,
            size: Size(BanknoteTier.whale.size.width, kNoteHeight),
          ),
        ),
      ),
    );
  }
}

/// A quiet icon square in an address's head: 28 px, the secondary ink.
class _HeadButton extends StatelessWidget {
  const _HeadButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  /// Overrides the secondary ink of the glyph (a copy that landed).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            hoverColor: s.hover,
            highlightColor: s.pressed,
            splashFactory: NoSplash.splashFactory,
            focusColor: s.hover,
            child: SizedBox.square(
              dimension: AppSpacing.controlHeightSmall,
              child: Icon(
                icon,
                size: AppSpacing.iconSmall,
                color: color ?? s.inkSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
