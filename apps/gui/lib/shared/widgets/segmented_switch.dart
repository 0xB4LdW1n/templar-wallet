import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One choice in a [SegmentedSwitch].
class SegOption<T> {
  const SegOption({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.dot,
  });

  final T value;
  final String label;
  final IconData? icon;

  final String? tooltip;

  /// A choice the user can see but not make — the chain this wallet does not
  /// have, say. Drawn dimmed and inert; put the reason in [tooltip]. Keeping
  /// the segment in place (rather than dropping it) leaves the control the
  /// same shape on every screen.
  final bool enabled;

  /// A 6 px dot before the label, in a chain hue. The one place colour may
  /// appear in the control, and only to identify a chain.
  final Color? dot;
}

/// The segmented control (design.md, "Controls").
///
/// A recessed `well` track with a hairline; the chosen segment is the raised
/// surface with the primary ink, the others are quiet text. No option owns a
/// colour: which one is chosen is told by the surface step alone.
///
/// Each segment is a focus stop, so Tab walks the options and Space/Enter
/// picks one. On a phone every segment is a 40 dp row inside a 44 dp track,
/// the track shrinks (labels ellipsised) instead of overflowing, and a
/// disabled segment explains itself with a snack bar since there is no hover
/// to surface the tooltip.
class SegmentedSwitch<T> extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.dense = false,
    this.expand = false,
    this.iconOnly = false,
  });

  final List<SegOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Tighter side padding, for a track inside a dense header row. The height
  /// is the same either way.
  final bool dense;

  /// Fill the available width, every segment the same share. Needs a bounded
  /// width (a Column child, a SizedBox) — inside a horizontal scroller leave
  /// it false and the track keeps its intrinsic width.
  final bool expand;

  /// Draw only the icons; the label moves into the tooltip. For the rare
  /// track that has to share one phone row with other controls. Options
  /// without an icon keep their label.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    // Radii nest: the track's corner minus its 2 px padding is the segment's.
    final radius = phone ? AppSpacing.radiusLg : AppSpacing.radiusMd;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: s.edge),
      ),
      child: FocusTraversalGroup(
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          children: [
            for (final o in options)
              _wrap(
                phone,
                _Segment<T>(
                  option: o,
                  selected: o.value == selected,
                  dense: dense,
                  phone: phone,
                  expand: expand,
                  iconOnly: iconOnly && o.icon != null,
                  onTap: () => onChanged(o.value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _wrap(bool phone, Widget segment) {
    if (expand) return Expanded(child: segment);
    // A loose Flexible in a min-size Row costs nothing while the track fits
    // and caps each segment at an equal share when it does not — and, unlike
    // Expanded, it is legal under unbounded width (the page header's
    // horizontal scroller on a phone).
    if (phone) return Flexible(child: segment);
    return segment;
  }
}

class _Segment<T> extends StatefulWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.dense,
    required this.phone,
    required this.expand,
    required this.iconOnly,
    required this.onTap,
  });

  final SegOption<T> option;
  final bool selected;
  final bool dense;
  final bool phone;
  final bool expand;
  final bool iconOnly;
  final VoidCallback onTap;

  @override
  State<_Segment<T>> createState() => _SegmentState<T>();
}

class _SegmentState<T> extends State<_Segment<T>> {
  bool _hover = false;
  bool _focus = false;

  /// Phone stand-in for the hover tooltip on a dimmed segment.
  void _explainDisabled() {
    final tip = widget.option.tooltip;
    if (tip == null) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tip)));
  }

  void _activate() {
    if (widget.option.enabled) widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final selected = widget.selected;
    final enabled = widget.option.enabled;
    final phone = widget.phone;
    final baseInk = selected || (_hover && enabled) ? s.ink : s.inkSecondary;
    final ink = enabled ? baseInk : baseInk.withValues(alpha: 0.5);

    final labelStyle = (selected ? AppTypography.label : AppTypography.caption)
        .copyWith(color: ink);
    final label = phone || widget.expand
        // Capped segments (phone Flexible / expand) ellipsise the label
        // instead of painting past the track.
        ? Flexible(
            child: Text(
              widget.option.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: labelStyle,
            ),
          )
        : Text(widget.option.label, style: labelStyle);

    final dot = widget.option.dot;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (dot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: enabled ? dot : dot.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        if (widget.option.icon != null) ...[
          Icon(widget.option.icon, size: AppSpacing.iconSmall, color: ink),
          if (!widget.iconOnly) const SizedBox(width: AppSpacing.sm),
        ],
        if (!widget.iconOnly) label,
      ],
    );

    // Nested inside the track's 2 px padding: 12 − 2 on a phone.
    final radius = phone
        ? AppSpacing.radiusPhoneControl - 2
        : AppSpacing.radiusSm;
    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      height: phone ? 40 : AppSpacing.controlHeightSmall,
      padding: EdgeInsets.symmetric(
        horizontal: widget.dense || widget.iconOnly
            ? AppSpacing.sm
            : AppSpacing.md,
      ),
      // The thumb sits in a well: on light that means white on grey, and the
      // card's whisper of a shadow is what gives it an edge there.
      decoration: BoxDecoration(
        color: selected ? s.thumb : Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: selected ? s.panelShadow : null,
      ),
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      // The chosen segment carries the accent's mark at its foot: a short
      // bar, the tab's "you are here", inside the thumb.
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(widthFactor: 1, child: content),
          Positioned(
            bottom: 2,
            child: AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: AppMotion.of(context, AppMotion.quick),
              curve: AppMotion.settle,
              child: Container(
                width: AppSpacing.md,
                height: 2,
                decoration: BoxDecoration(
                  color: s.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final tappable = Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: widget.iconOnly ? widget.option.label : null,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? widget.onTap : (phone ? _explainDisabled : null),
          child: body,
        ),
      ),
    );

    final tip =
        widget.option.tooltip ?? (widget.iconOnly ? widget.option.label : null);
    if (tip == null) return tappable;
    // On a phone the tap on a disabled segment already explains it and an
    // icon-only segment is named for the screen reader; a long-press tooltip
    // would only add a second, undiscoverable path.
    if (phone) return Semantics(label: tip, child: tappable);
    return Tooltip(message: tip, child: tappable);
  }
}
