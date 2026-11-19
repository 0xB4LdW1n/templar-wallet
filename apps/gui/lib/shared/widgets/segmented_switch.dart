import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'hybrid_kit.dart' show CurrentMark;

/// One choice in a [SegmentedSwitch].
class SegOption<T> {
  const SegOption({
    required this.value,
    required this.label,
    this.icon,
    this.tooltip,
    this.enabled = true,
    this.logo,
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

  /// A chain's logo before the label (an `AssetLogo`, sized
  /// [SegmentedSwitch.logoSize]). The one place colour may appear in the
  /// control, and only to identify a chain. Kept in [SegmentedSwitch.iconOnly]
  /// mode, where it stands for the label.
  final Widget? logo;
}

/// The segmented control (design.md, "Controls").
///
/// A recessed `well` track with a hairline; the chosen segment is the raised
/// surface with the primary ink inside the accent's 1 px border
/// ([CurrentMark]), the others are quiet text. No option owns a colour
/// beyond a chain's logo.
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

  /// The side of a [SegOption.logo].
  static const double logoSize = 20;

  /// A segment's height on desktop; the track adds its padding and hairline
  /// (40 in all). On a phone the segment is 40 and the track 46.
  static const double segmentHeight = 34;

  /// Space between the track's hairline and its segments.
  static const double _inset = 2;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return Container(
      padding: const EdgeInsets.all(_inset),
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
                  iconOnly: iconOnly && (o.icon != null || o.logo != null),
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

    final labelStyle = AppTypography.body.copyWith(
      color: ink,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
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

    final logo = widget.option.logo;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (logo != null) ...[
          Opacity(opacity: enabled ? 1 : 0.5, child: logo),
          if (!widget.iconOnly) const SizedBox(width: AppSpacing.sm),
        ] else if (widget.option.icon != null) ...[
          Icon(widget.option.icon, size: AppSpacing.iconSmall, color: ink),
          if (!widget.iconOnly) const SizedBox(width: AppSpacing.sm),
        ],
        if (!widget.iconOnly) label,
      ],
    );

    // Radii nest: the track's corner minus its padding.
    const radius = AppSpacing.radiusLg - SegmentedSwitch._inset;
    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      height: phone ? 40 : SegmentedSwitch.segmentHeight,
      padding: EdgeInsets.symmetric(
        horizontal: widget.dense || widget.iconOnly
            ? AppSpacing.md
            : AppSpacing.lg,
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
      child: Center(widthFactor: 1, child: content),
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
          // The chosen segment wears the accent's border, the sidebar
          // row's "you are here".
          child: CurrentMark(active: selected, radius: radius, child: body),
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
