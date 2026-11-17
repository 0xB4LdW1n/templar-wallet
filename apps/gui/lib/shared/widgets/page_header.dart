import 'package:flutter/material.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// The page's name (design.md, "Controls"): `pageTitle` in the primary ink,
/// the actions on the right centred on the title, one optional line of meta
/// under it, 24 below the whole header (16 on a phone).
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;

  /// One quiet line of meta — a count, a period, the wallet — not a sentence
  /// restating the title.
  final String? subtitle;

  /// Right-aligned on the title row. The chain switch goes here on per-chain
  /// screens, as the last item: one row, no leftover space.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final sub = subtitle;
    final titleText = Text(
      title,
      style: AppTypography.pageTitleOf(context).copyWith(color: s.ink),
    );
    final meta = sub == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              sub,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          );
    final actionRow = actions.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                actions[i],
              ],
            ],
          );

    return Padding(
      padding: EdgeInsets.only(bottom: phone ? AppSpacing.lg : AppSpacing.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow widths: the chain switch and the other actions would leave
          // the title a few dozen pixels, so they move under it instead. A
          // single small action (the privacy eye, one icon button) stays on
          // the title row; only a real toolbar stacks.
          final stacked =
              actionRow != null &&
              constraints.maxWidth < 520 &&
              actions.length > 1;
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText,
                ?meta,
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: actionRow,
                  ),
                ),
              ],
            );
          }
          // The actions share the title's row so they centre on the title,
          // not on the title and its meta together.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: titleText),
                  if (actionRow != null) ...[
                    const SizedBox(width: AppSpacing.lg),
                    actionRow,
                  ],
                ],
              ),
              ?meta,
            ],
          );
        },
      ),
    );
  }
}
