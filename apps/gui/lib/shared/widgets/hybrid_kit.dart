// Surfaces, data blocks, tags and the small motion helpers every screen
// shares (design.md, "Surfaces" and "Controls").
//
// The page is a flat `canvas`. A card is the `panel` step with a hairline; a
// recess for data is the `well`. Tags are quiet text on `panelInset`. Motion
// is a fade and a short rise, once, and nothing loops.

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

// ── Page background ───────────────────────────────────────────────────────────

/// The page: the flat `canvas` step. Wrap a screen's body in this.
///
/// Both constructors draw the same thing; [PageBackground.flat] is kept so
/// existing call sites compile.
class PageBackground extends StatelessWidget {
  const PageBackground({super.key, required this.child});

  const PageBackground.flat({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppScheme.of(context).canvas, child: child);
}

// ── Bottom-sheet surface ──────────────────────────────────────────────────────

/// Rounded-top surface for modal bottom sheets (tx detail, asset/token
/// detail): the `panel` step with a hairline, floating over the page.
/// Pair with `showModalBottomSheet(backgroundColor: Colors.transparent)`.
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child, this.topMargin = 0});

  final Widget child;

  /// Gap above the sheet (leaves the page peeking at the top).
  final double topMargin;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      margin: EdgeInsets.only(top: topMargin),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppSpacing.radiusXl),
        ),
        border: Border.all(color: s.edge),
        boxShadow: s.floatShadow,
      ),
      child: child,
    );
  }
}

// ── Panels ────────────────────────────────────────────────────────────────────

/// The hero: the one block a screen exists for (the balance, the quorum).
/// The card material at the hero radius and a wider inset — larger, not
/// louder.
class HeroPanel extends StatelessWidget {
  const HeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: child,
    );
  }
}

/// A titled card with a trailing control in the title row, in the card
/// material. A domain is told by the title, not by a coloured edge.
class RailPanel extends StatelessWidget {
  const RailPanel({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  /// Body padding. Pass EdgeInsets.zero for flush content (tables, rows):
  /// the panel then rules a hairline under the title.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = AppLayout.isPhone(context)
        ? AppSpacing.cardPaddingSmall
        : AppSpacing.cardPadding;
    final flush =
        padding != null &&
        padding!.resolve(Directionality.of(context)).top == 0;
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: AppTypography.sectionTitle.copyWith(color: s.ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  trailing!,
                ],
              ],
            ),
          ),
          if (flush) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, thickness: 1, color: s.edge),
          ],
          Padding(
            padding:
                padding ?? EdgeInsets.fromLTRB(pad, AppSpacing.lg, pad, pad),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ── Data display ──────────────────────────────────────────────────────────────

/// The recess critical data is printed in (addresses, outpoints,
/// descriptors): the `well` with a hairline. Solid, never translucent.
class DataWell extends StatelessWidget {
  const DataWell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: s.edge),
      ),
      child: child,
    );
  }
}

/// Key/value row for technical data: the key in `label` and the secondary
/// ink in a fixed column, the value in selectable `mono` and the primary
/// ink, wrapping rather than truncating. 40 tall.
///
/// On a phone a long value (an outpoint, an address) stacks under its key
/// so it gets the whole column instead of what is left beside the key.
class KvRow extends StatelessWidget {
  const KvRow({
    super.key,
    required this.label,
    required this.value,
    this.labelWidth = 96,
    this.divider = false,
  });
  final String label;
  final String value;
  final double labelWidth;

  /// A hairline under the row, for a run of rows that is not inside a
  /// [DataWell].
  final bool divider;

  /// Values longer than this stack on a phone; shorter ones (fees, counts,
  /// network names) keep the two-column shape, which scans faster.
  static const int _stackOver = 20;

  static const double _rowHeight = 40;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final keyText = Text(
      label,
      style: AppTypography.label.copyWith(color: s.inkSecondary),
    );
    final valueText = SelectableText(
      value,
      style: AppTypography.mono.copyWith(color: s.ink),
    );
    final Widget body;
    if (AppLayout.isPhone(context) && value.length > _stackOver) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          keyText,
          const SizedBox(height: AppSpacing.xs),
          valueText,
        ],
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: labelWidth, child: keyText),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: valueText),
        ],
      );
    }
    return Container(
      constraints: const BoxConstraints(minHeight: _rowHeight),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: s.edge)),
            )
          : null,
      child: body,
    );
  }
}

/// 6 px status dot.
class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 6,
    height: 6,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
  );
}

/// A quiet tag: `eyebrow` in the secondary ink on `panelInset`.
///
/// [color] names what the tag means. A status or chain hue becomes a 6 px
/// dot before the word; the ink roles and the accent draw no dot (the
/// accent is never decoration). The word itself is never coloured.
/// Ellipsises rather than overflows when the parent is tighter than it.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final neutral =
        color == s.ink ||
        color == s.inkSecondary ||
        color == s.inkFaint ||
        color == s.accent;
    return QuietTag(label: label, dot: neutral ? null : color);
  }
}

/// The tag every badge in the kit draws: `panelInset`, radius 4, 2×6
/// padding, an optional 6 px dot or 16 px glyph, the word in the secondary
/// ink. [mono] sets the word in `monoSmall`, for tickers and data.
class QuietTag extends StatelessWidget {
  const QuietTag({
    super.key,
    required this.label,
    this.dot,
    this.icon,
    this.mono = false,
  });

  final String label;
  final Color? dot;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final d = dot;
    final i = icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (d != null) ...[
            _Dot(d),
            const SizedBox(width: AppSpacing.xs),
          ] else if (i != null) ...[
            Icon(i, size: AppSpacing.iconSmall, color: s.inkSecondary),
            const SizedBox(width: AppSpacing.xs),
          ],
          // A loose Flexible in a min-size Row is a no-op while the label
          // fits and is legal under unbounded width, so the tag can sit in a
          // header scroller as well as a tight Row.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: (mono ? AppTypography.monoSmall : AppTypography.eyebrow)
                  .copyWith(color: s.inkSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The network the wallet is on: a 6 px dot in the testnet hue and the word.
/// Stated once, on the Dashboard.
class TestnetBadge extends StatelessWidget {
  const TestnetBadge({super.key, this.label = 'TESTNET'});

  /// The network's name: `TESTNET`, or `REGTEST` beside a test server.
  final String label;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Semantics(
      label:
          '${label[0]}${label.substring(1).toLowerCase()} network — no mainnet funds',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dot(s.testnet),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${label[0]}${label.substring(1).toLowerCase()}',
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
          ),
        ],
      ),
    );
  }
}

// ── The mark of "you are here" ────────────────────────────────────────────────

/// The current destination's mark (design.md, "The accent"): a short bar in
/// the accent — and so in the wallet's own colour — on the leading edge of
/// the row the user is on, or above the tab they are on.
///
/// The row is already told apart by its surface step and its ink; the bar
/// is the one touch of the wax on the chrome. It fades with the selection
/// and never moves.
class CurrentMark extends StatelessWidget {
  const CurrentMark({
    super.key,
    required this.active,
    this.axis = Axis.vertical,
  });

  final bool active;

  /// Vertical on the edge of a row, horizontal over a tab.
  final Axis axis;

  static const double thickness = 3;
  static const double length = AppSpacing.lg;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final vertical = axis == Axis.vertical;
    return AnimatedOpacity(
      opacity: active ? 1 : 0,
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      child: Container(
        width: vertical ? thickness : length,
        height: vertical ? length : thickness,
        decoration: BoxDecoration(
          color: s.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ── Motion helpers ────────────────────────────────────────────────────────────

/// Gap between two staggered entrances.
const Duration _stagger = Duration(milliseconds: 60);

/// Fade in with an optional rise, once, after `delay` staggers.
class _Enter extends StatelessWidget {
  const _Enter({required this.child, required this.delay, required this.rise});
  final Widget child;
  final int delay;
  final double rise;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduced(context)) return child;
    final wait = _stagger * delay.clamp(0, 8);
    final total = AppMotion.emphasized + wait;
    final start = wait.inMicroseconds / total.inMicroseconds;
    // On a phone the entrance is composited from a cached raster of the
    // child: a QR CustomPaint inside would otherwise be repainted through a
    // saveLayer on every frame of the fade.
    final content = AppLayout.isMobilePlatform
        ? RepaintBoundary(child: child)
        : child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: AppMotion.settle),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: rise == 0
            ? c
            : Transform.translate(offset: Offset(0, rise * (1 - t)), child: c),
      ),
      child: content,
    );
  }
}

/// Entrance for a block of a page: a fade and an 8 px rise, once. [delay]
/// staggers siblings. Skipped under reduced motion.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;

  @override
  Widget build(BuildContext context) =>
      _Enter(delay: delay, rise: 8, child: child);
}

/// A table or list row that answers the pointer with the `hover` step.
///
/// [trailing] is an action that belongs to the row (copy, open) and on
/// desktop fades in on hover; a phone has no hover, so there it is simply
/// always shown.
class HoverRow extends StatefulWidget {
  const HoverRow({super.key, required this.child, this.onTap, this.trailing});
  final Widget child;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  bool _h = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final radius = BorderRadius.circular(AppSpacing.radiusMd);
    Widget content = widget.child;
    final trailing = widget.trailing;
    if (trailing != null) {
      final alwaysShown = AppLayout.isPhone(context);
      content = Row(
        children: [
          Expanded(child: content),
          AnimatedOpacity(
            duration: AppMotion.of(context, AppMotion.instant),
            opacity: alwaysShown || _h ? 1 : 0,
            child: trailing,
          ),
        ],
      );
    }
    final row = MouseRegion(
      onEnter: (_) => setState(() => _h = true),
      onExit: (_) => setState(() => _h = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: AnimatedContainer(
        duration: AppMotion.of(context, AppMotion.instant),
        curve: AppMotion.settle,
        decoration: BoxDecoration(
          color: _h && widget.onTap != null ? s.hover : Colors.transparent,
          borderRadius: radius,
        ),
        child: content,
      ),
    );
    if (widget.onTap == null) return row;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: radius,
      // The row paints its own hover step; the press is the pressed step.
      hoverColor: Colors.transparent,
      highlightColor: s.pressed,
      splashFactory: NoSplash.splashFactory,
      child: row,
    );
  }
}
