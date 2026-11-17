// The Activity rows for what is not a plain payment: a loan, a swap, a peg.
// Same anatomy and height as the payment row (history_screen.dart) — glyph
// tile, title, one line of facts and the status, figures on the right — so
// the list reads as one ledger. What differs is the glyph on the tile — the
// kind's own, as the sidebar draws its page — and the badge on its corner:
// the asset that comes in. The tile itself is the payment row's: iron, the
// glyph in the secondary ink. A kind is told by its glyph and its title,
// never by a colour.

import 'package:flutter/material.dart';

import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/live_edge.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'models/activity_entry.dart';

/// A row's height: 60 on desktop, 64 on a phone (a touch row clears 48 with
/// room for two lines). The payment row uses the same pair.
const double kActivityRowHeight = 60;
const double kActivityRowHeightPhone = 64;

/// The glyph of a kind, as the sidebar draws its page.
IconData activityKindIcon(ActivityKind kind) => switch (kind) {
  ActivityKind.payment => Icons.swap_horiz_outlined,
  ActivityKind.loan => Icons.handshake_outlined,
  ActivityKind.swap => Icons.swap_horiz_outlined,
  ActivityKind.peg => Icons.swap_vert_outlined,
};

/// The dot of a status: only a wait or a loss earns one.
Color? activityToneColor(AppScheme s, ActivityTone tone) => switch (tone) {
  ActivityTone.neutral => null,
  ActivityTone.wait => s.pending,
  ActivityTone.loss => s.danger,
};

/// The figure under the lead one: where a swap or a peg lands, or what a
/// loan is secured by.
String activitySecondaryText(ActivityEntry e, String formatted) => switch (e) {
  LoanEntry() => '$formatted collateral',
  _ => '→ $formatted',
};

/// The kind's tile: the same raised square a payment's arrow sits on, with
/// the kind's glyph in the secondary ink and (when the entry names one) the
/// incoming asset on its corner.
class ActivityKindGlyph extends StatelessWidget {
  const ActivityKindGlyph({
    super.key,
    required this.kind,
    this.badgeTicker,
    this.size = kListTile,
  });

  final ActivityKind kind;
  final String? badgeTicker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final tile = ListIconTile(icon: activityKindIcon(kind), size: size);
    final badge = badgeTicker;
    if (badge == null || badge.isEmpty) return tile;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            right: -AppSpacing.xs,
            bottom: -AppSpacing.xs,
            // A ring of the card's own tone keeps the badge off the tile.
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(color: s.panel, shape: BoxShape.circle),
              child: AssetLogo(ticker: badge, size: AppSpacing.lg),
            ),
          ),
        ],
      ),
    );
  }
}

/// 6 px status dot, inline with the word it qualifies.
InlineSpan activityDotSpan(Color color) => WidgetSpan(
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

/// The facts line: `Borrowed · 2 of 6 paid · due 4 Dec · Active`. On a phone
/// the status leads, so a narrow column cuts a fact, never the state.
class ActivityFactsLine extends StatelessWidget {
  const ActivityFactsLine({super.key, required this.entry});
  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final faint = AppTypography.caption.copyWith(color: s.inkFaint);
    final status = entry.status;
    final dot = status == null ? null : activityToneColor(s, status.tone);
    final statusSpans = <InlineSpan>[
      if (dot != null) activityDotSpan(dot),
      if (status != null) TextSpan(text: status.label, style: faint),
    ];
    final facts = entry.facts.join(' · ');
    final sep = TextSpan(text: ' · ', style: faint);
    final spans = phone
        ? [
            ...statusSpans,
            if (statusSpans.isNotEmpty && facts.isNotEmpty) sep,
            TextSpan(text: facts, style: faint),
          ]
        : [
            TextSpan(text: facts, style: faint),
            if (statusSpans.isNotEmpty && facts.isNotEmpty) sep,
            ...statusSpans,
          ];
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// One loan, swap or peg in the timeline.
class ActivityEntryRow extends StatefulWidget {
  const ActivityEntryRow({
    super.key,
    required this.entry,
    required this.useSats,
    required this.onTap,
  });

  final ActivityEntry entry;
  final bool useSats;
  final VoidCallback onTap;

  @override
  State<ActivityEntryRow> createState() => _ActivityEntryRowState();
}

class _ActivityEntryRowState extends State<ActivityEntryRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final e = widget.entry;
    final primary = e.primary;
    // A phone's amount column (144 dp) cannot hold "0.01200000 LBTC
    // collateral"; the loan's collateral stays in its detail rather than
    // being cut mid-word.
    final secondary = phone && e is LoanEntry ? null : e.secondary;

    final amount = primary == null && secondary == null
        ? null
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: phone ? 144 : 240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (primary != null)
                  Amount(
                    primary.format(useSats: widget.useSats),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppTypography.numeric.copyWith(
                      color: e.isPending ? s.inkSecondary : s.ink,
                    ),
                  ),
                if (secondary != null)
                  Amount(
                    activitySecondaryText(
                      e,
                      secondary.format(useSats: widget.useSats),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppTypography.numericSmall.copyWith(
                      color: s.inkFaint,
                    ),
                  ),
              ],
            ),
          );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      constraints: BoxConstraints(
        minHeight: phone ? kActivityRowHeightPhone : kActivityRowHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      color: _down ? s.pressed : (_hover ? s.hover : Colors.transparent),
      foregroundDecoration: _focus
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      child: Row(
        children: [
          ActivityKindGlyph(kind: e.kind, badgeTicker: e.badgeTicker),
          const SizedBox(width: kListGap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                ),
                ActivityFactsLine(entry: e),
              ],
            ),
          ),
          if (amount != null) ...[const SizedBox(width: AppSpacing.md), amount],
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_outlined,
            size: AppSpacing.icon,
            color: s.inkFaint,
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
          child: PendingEdge(pending: e.isPending, child: body),
        ),
      ),
    );
  }
}

/// The mark of a row that is still in motion (design.md, "Motion"): an
/// orange outline just inside the row, breathing for as long as the
/// transaction or the operation is pending. The row's status word and its
/// dot say the same thing; the edge is how the eye finds it in a long list.
class PendingEdge extends StatelessWidget {
  const PendingEdge({super.key, required this.pending, required this.child});

  final bool pending;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!pending) return child;
    return LiveEdge(
      mode: LiveEdgeMode.breathing,
      color: AppScheme.of(context).pending,
      // A row sits in a card of radius 12: four in, the corner is 8.
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      inset: AppSpacing.xs,
      child: child,
    );
  }
}
