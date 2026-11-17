import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The unit beside an amount field. Plain text for a token; on a BTC/LBTC
/// row with a live price it is a small quiet button that flips the field to
/// the other unit ([other]) — the swap glyph says it can, the label says which
/// unit the number in the box is in right now.
///
/// Units are meta, so the chip speaks in the secondary ink: it must never
/// compete with the figure it qualifies.
class UnitChip extends StatefulWidget {
  const UnitChip({super.key, required this.label, this.other, this.onTap});

  final String label;

  /// The unit a tap switches to; null when the chip is only a label.
  final String? other;
  final VoidCallback? onTap;

  @override
  State<UnitChip> createState() => _UnitChipState();
}

class _UnitChipState extends State<UnitChip> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final onTap = widget.onTap;
    if (onTap == null) {
      return Padding(
        padding: const EdgeInsets.only(
          left: AppSpacing.sm,
          right: AppSpacing.md,
        ),
        child: Text(
          widget.label,
          style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
        ),
      );
    }

    final ink = _hover || _down ? s.ink : s.inkSecondary;
    final fill = _down
        ? Color.alphaBlend(s.pressed, s.panel)
        : _hover
        ? Color.alphaBlend(s.hover, s.panel)
        : s.panel;
    final pill = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
        border: Border.all(color: s.edge),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.label,
            style: AppTypography.eyebrow.copyWith(color: ink),
          ),
          const SizedBox(width: AppSpacing.xs),
          Icon(Icons.swap_vert_outlined, size: AppSpacing.iconSmall, color: ink),
        ],
      ),
    );

    final tip = 'Enter the amount in ${widget.other}';
    final body = Semantics(
      button: true,
      label: tip,
      excludeSemantics: true,
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
          // The pill keeps its own size inside a 48 dp slot on a phone — the
          // slot is what a finger hits, not the pill.
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: phone ? AppLayout.minTouchTarget : 0,
              minHeight: phone ? AppLayout.minTouchTarget : 0,
            ),
            child: Center(widthFactor: 1, heightFactor: 1, child: pill),
          ),
        ),
      ),
    );
    // Touch has no tooltip; the semantics label above names the action.
    if (phone) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: body,
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
      child: Tooltip(message: tip, child: body),
    );
  }
}
