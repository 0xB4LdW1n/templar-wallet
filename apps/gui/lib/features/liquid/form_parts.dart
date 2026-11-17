// Small pieces the Liquid, LiquiDEX and Peg screens share: a labelled field,
// an outlined icon action and a status dot. They are the design.md grammar
// for things the shared kit has no widget for yet; kept here, next to the
// screens that use them, rather than in lib/shared/widgets/.

import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A form field with its name above it (`eyebrow`, faint) and an optional
/// line of help under it (`caption`, faint). design.md: "A field's label is
/// an eyebrow above it, never floating inside."
class FieldBlock extends StatelessWidget {
  const FieldBlock({
    super.key,
    required this.label,
    required this.child,
    this.help,
    this.trailing,
  });

  final String label;
  final Widget child;

  /// One quiet line under the field.
  final String? help;

  /// Something that belongs to the label row, right-aligned ("Burn all").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final h = help;
    final t = trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTypography.eyebrow.copyWith(color: s.inkSecondary),
              ),
            ),
            ?t,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        child,
        if (h != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(h, style: AppTypography.caption.copyWith(color: s.inkFaint)),
        ],
      ],
    );
  }
}

/// A square icon action with a hairline outline and a tooltip — a header
/// tool (refresh, import, help). 36 on desktop, 48 on a phone, the glyph in
/// the secondary ink at the chrome size.
class OutlinedIconAction extends StatelessWidget {
  const OutlinedIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final side = phone ? AppLayout.minTouchTarget : AppSpacing.controlHeight;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: side,
          child: IconButton(
            onPressed: onPressed,
            padding: EdgeInsets.zero,
            icon: Icon(icon, size: phone ? 20 : AppSpacing.icon),
            style: IconButton.styleFrom(
              minimumSize: Size.square(side),
              fixedSize: Size.square(side),
              side: BorderSide(color: s.edgeStrong),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  phone ? AppSpacing.radiusPhoneControl : AppSpacing.radiusMd,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The 6 px status dot (design.md: status is a dot and a word).
class StatusDot extends StatelessWidget {
  const StatusDot(this.color, {super.key});

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
