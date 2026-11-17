// The grouped list (design.md, "Rows, not a card each") — one card,
// hairline-separated rows, each with its glyph on a raised tile.
//
// The Dashboard's assets and activity and the Settings root are all the same
// object: a labelled group of rows. Sharing the widgets keeps a row meaning
// the same thing wherever it appears, and keeps the screens from drifting a
// pixel apart.

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Card inset and icon column — the dividers start where the text does.
const double kListPad = AppSpacing.lg;
const double kListTile = 32;
const double kListGap = AppSpacing.md;
const double kListTextInset = kListPad + kListTile + kListGap;

/// The quiet label over a group, with the group's one way in on the right
/// ("Assets … Liquid →"). Navigation lives here so the rows below can stay
/// data. Sentence case: the label is read, not shouted.
///
/// It owns the 8 under it; the gap above it belongs to the block before it.
class ListSectionLabel extends StatelessWidget {
  const ListSectionLabel({
    super.key,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final action = actionLabel;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: s.inkSecondary,
                // The one way into a section is a control, so on touch it
                // clears the floor even though the words are small.
                minimumSize: Size(
                  0,
                  phone
                      ? AppLayout.minTouchTarget
                      : AppSpacing.controlHeightSmall,
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                textStyle: AppTypography.label,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(action),
                  const SizedBox(width: AppSpacing.xs),
                  Icon(
                    Icons.arrow_forward_outlined,
                    size: AppSpacing.iconSmall,
                    color: s.accentGlyph,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The card a run of [ListRow]s sits on. It clips its rows, so a row's hover
/// layer follows the card's corners.
class ListCard extends StatelessWidget {
  const ListCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: s.edge,
                indent: kListTextInset,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Draws a glyph that is not in the icon font — the Templar cross — at an
/// icon's [size] and in its [color], so it sits in a tile like any other.
typedef GlyphBuilder = Widget Function(double size, Color color);

/// The glyph tile at the head of a row: one raised square, one glyph in the
/// secondary ink. A [tint] is honoured only where the colour is a fact — a
/// chain hue or a status; any other colour falls back to the secondary ink,
/// because an icon never gets a colour of its own (design.md, "Icons").
class ListIconTile extends StatelessWidget {
  const ListIconTile({
    super.key,
    this.icon,
    this.glyph,
    this.tint,
    this.size = kListTile,
  }) : assert(icon != null || glyph != null);

  final IconData? icon;

  /// Draws the glyph when it is not an [IconData]; wins over [icon].
  final GlyphBuilder? glyph;
  final Color? tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final side = size >= 48
        ? 24.0
        : size >= kListTile
        ? AppSpacing.icon
        : AppSpacing.iconSmall;
    final ink = listGlyphInk(s, tint);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(
          size > 40 ? AppSpacing.radiusLg : AppSpacing.radiusMd,
        ),
      ),
      child: glyph?.call(side, ink) ?? Icon(icon, size: side, color: ink),
    );
  }
}

/// The ink a row glyph is drawn in: [tint] when it is a chain hue or a
/// status, the secondary ink otherwise.
Color listGlyphInk(AppScheme s, Color? tint) {
  if (tint == null) return s.inkSecondary;
  final factual = <Color>[s.bitcoin, s.liquid, s.success, s.warning, s.danger];
  return factual.contains(tint) ? tint : s.inkSecondary;
}

/// One row: glyph, title, one line saying what it is, and whatever states or
/// operates it on the right.
class ListRow extends StatefulWidget {
  const ListRow({
    super.key,
    this.icon,
    this.glyph,
    this.tint,
    required this.title,
    this.titleWidget,
    this.subtitle,
    this.subtitleColor,
    this.trailing,
    this.onTap,
    this.chevron = false,
  }) : assert(icon != null || glyph != null);

  final IconData? icon;

  /// Draws the glyph when it is not an [IconData]; see [ListIconTile.glyph].
  final GlyphBuilder? glyph;

  /// The glyph's colour when it is a fact (a chain, a status); see
  /// [ListIconTile.tint].
  final Color? tint;
  final String title;

  /// Drawn in place of the title's text — the tag of a labelled address.
  /// [title] still names the row to assistive tech.
  final Widget? titleWidget;
  final String? subtitle;

  /// Overrides the subtitle ink — for a state that is not merely descriptive
  /// (an unavailable chain, an unconfirmed transaction).
  final Color? subtitleColor;

  /// The right-hand side: an amount column, a switch, a value. A [chevron]
  /// is drawn after it.
  final Widget? trailing;

  final VoidCallback? onTap;
  final bool chevron;

  @override
  State<ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<ListRow> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final sub = widget.subtitle;
    final onTap = widget.onTap;
    final enabled = onTap != null;

    final title = Text(
      widget.title,
      style: AppTypography.bodyOf(context).copyWith(color: s.ink),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final content = Row(
      children: [
        ListIconTile(icon: widget.icon, glyph: widget.glyph, tint: widget.tint),
        const SizedBox(width: kListGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.titleWidget case final custom?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: custom,
                )
              else
                title,
              if (sub != null)
                Text(
                  sub,
                  style: AppTypography.caption.copyWith(
                    color: widget.subtitleColor ?? s.inkSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          widget.trailing!,
        ],
        if (widget.chevron) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_outlined,
            size: AppSpacing.icon,
            color: s.inkFaint,
          ),
        ],
      ],
    );

    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: !enabled
          ? Colors.transparent
          : _down
          ? s.pressed
          : _hover
          ? s.hover
          : Colors.transparent,
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: BoxConstraints(
        minHeight: phone && sub != null
            ? AppSpacing.rowHeight + AppSpacing.sm
            : AppSpacing.rowHeight,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.sm,
      ),
      child: content,
    );

    if (!enabled) {
      return Semantics(
        label: sub == null ? widget.title : '${widget.title}. $sub',
        child: body,
      );
    }
    // Merged, not excluded: excluding the children silenced the trailing
    // widget, so a screen reader announced the row's name and not its amount.
    return Semantics(
      button: true,
      child: MergeSemantics(
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
                onTap();
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The right-hand figure of a data row: the number, and its unit or other
/// denomination under it, right-aligned so a column of amounts lines up.
class ListAmount extends StatelessWidget {
  const ListAmount({
    super.key,
    required this.value,
    this.unit,
    this.valueColor,
    this.unitColor,
    this.maxWidth = 150,
  });

  final String value;
  final String? unit;

  /// The figure's ink: [AppScheme.ink] by default; an incoming amount may
  /// pass [AppScheme.success]. Outgoing stays in the primary ink.
  final Color? valueColor;
  final Color? unitColor;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final u = unit;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.numeric.copyWith(color: valueColor ?? s.ink),
          ),
          if (u != null)
            Text(
              u,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.numericSmall.copyWith(
                color: unitColor ?? s.inkFaint,
              ),
            ),
        ],
      ),
    );
  }
}

/// The switch used in a row: the themed Material switch, on in the primary
/// ink (app_theme.dart), never the accent.
class ListSwitch extends StatelessWidget {
  const ListSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      toggled: value,
      child: Switch(
        value: value,
        onChanged: onChanged,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}
