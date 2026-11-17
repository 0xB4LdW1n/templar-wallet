import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One entry of a [ChoiceList].
class ChoiceListOption<T> {
  const ChoiceListOption({
    required this.value,
    required this.label,
    required this.icon,
    this.note,
    this.enabled = true,
    this.disabledReason,
  });

  final T value;
  final String label;
  final IconData icon;

  /// A two-word qualifier after the label — "signs here" — for what choosing
  /// this changes about the wallet. Not a description: the row is a choice,
  /// and a choice is read at a glance.
  final String? note;

  /// A choice the user can see but not make. It stays in place, dimmed, with
  /// [disabledReason] under it, so the list is the same shape every time.
  final bool enabled;
  final String? disabledReason;
}

/// A grouped list of options with one selected: the wizard's "pick one of
/// these" once there are more than two or three of them and a row of chips
/// would wrap (design.md, "Option card").
///
/// One card, one row per option, hairlines between them inset to the text,
/// an [OptionRadio] on the right — the same radio a `SelectableOptionCard`
/// carries, so a chosen row and a chosen card read the same. The chosen row
/// is told by its radio alone; the row itself is never tinted.
class ChoiceList<T> extends StatelessWidget {
  const ChoiceList({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<ChoiceListOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: s.edge,
                indent: kChoiceTextInset,
              ),
            ChoiceListRow<T>(
              option: options[i],
              selected: options[i].value == selected,
              onTap: options[i].enabled
                  ? () => onChanged(options[i].value)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

/// Where a row's text starts — the hairlines between rows start there too,
/// so the icon column reads as one column and not as five gaps.
const double kChoiceTextInset = AppSpacing.lg + AppSpacing.icon + AppSpacing.md;

/// One row of a [ChoiceList].
class ChoiceListRow<T> extends StatefulWidget {
  const ChoiceListRow({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ChoiceListOption<T> option;
  final bool selected;

  /// Null for a disabled option: it keeps its row, loses its cursor.
  final VoidCallback? onTap;

  @override
  State<ChoiceListRow<T>> createState() => _ChoiceListRowState<T>();
}

class _ChoiceListRowState<T> extends State<ChoiceListRow<T>> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final o = widget.option;
    final enabled = widget.onTap != null;
    final selected = widget.selected;

    final fill = !enabled
        ? Colors.transparent
        : _down
        ? s.pressed
        : _hover
        ? s.hover
        : Colors.transparent;
    final reason = o.disabledReason;

    final row = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: fill,
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      constraints: const BoxConstraints(minHeight: AppSpacing.rowHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(o.icon, size: AppSpacing.icon, color: s.inkSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text.rich(
                  TextSpan(
                    text: o.label,
                    style: (phone
                            ? AppTypography.bodyOf(context)
                            : AppTypography.body)
                        .copyWith(color: s.ink, fontWeight: FontWeight.w500),
                    children: [
                      if (o.note != null)
                        TextSpan(
                          text: '  ·  ${o.note}',
                          style: AppTypography.caption.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!enabled && reason != null)
                  Text(
                    reason,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          OptionRadio(selected: selected),
        ],
      ),
    );

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      enabled: enabled,
      selected: selected,
      child: MergeSemantics(
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor: enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onShowHoverHighlight: (v) => setState(() {
            _hover = v;
            if (!v) _down = false;
          }),
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
            onTap: widget.onTap,
            onTapDown: enabled ? (_) => setState(() => _down = true) : null,
            onTapUp: enabled ? (_) => setState(() => _down = false) : null,
            onTapCancel: enabled ? () => setState(() => _down = false) : null,
            // A disabled option is legible but plainly not on offer.
            child: Opacity(opacity: enabled ? 1 : 0.5, child: row),
          ),
        ),
      ),
    );
  }
}

/// The radio of an option row or card: an 18 px ring; chosen, the ring takes
/// the primary ink and holds an 8 px dot in the accent — one of the three
/// places the accent appears beyond the primary button.
class OptionRadio extends StatelessWidget {
  const OptionRadio({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final duration = AppMotion.of(context, AppMotion.quick);
    return AnimatedContainer(
      duration: duration,
      curve: AppMotion.settle,
      width: AppSpacing.icon,
      height: AppSpacing.icon,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? s.ink : s.edgeStrong,
          width: 1.5,
        ),
      ),
      child: AnimatedOpacity(
        opacity: selected ? 1 : 0,
        duration: duration,
        curve: AppMotion.settle,
        child: Container(
          width: AppSpacing.sm,
          height: AppSpacing.sm,
          decoration: BoxDecoration(color: s.accent, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
