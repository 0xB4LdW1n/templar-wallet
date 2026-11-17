import 'package:flutter/material.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

// The card (design.md, "Controls"): one material for every card in the app —
// the `panel` step, a hairline, radius 12, padding 20 (16 on a phone), the
// title in `sectionTitle` with 16 between it and the content. No tinted
// header strip. A hairline under the title only when the body is flush (a
// list or a table that runs to the card's edges), because then the rows need
// a rule to start from.

/// Card inset for the window at hand: the desktop 20, the compact 16 on a
/// phone, where every card spends its width on padding twice.
double cardPadFor(BuildContext context) => AppLayout.isPhone(context)
    ? AppSpacing.cardPaddingSmall
    : AppSpacing.cardPadding;

/// The card's surface: shared by every card in the kit so a FormCard, a
/// SectionCard and a PlainCard are visibly the same object.
BoxDecoration cardDecoration(AppScheme s, {Color? color}) => BoxDecoration(
  color: color ?? s.panel,
  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
  border: Border.all(color: s.edge),
  boxShadow: s.panelShadow,
);

/// True when the caller asked for a body with no top inset — a list or a
/// table that starts at the hairline.
bool _isFlush(BuildContext context, EdgeInsetsGeometry? padding) =>
    padding != null && padding.resolve(Directionality.of(context)).top == 0;

/// Title, optional quiet subtitle, optional trailing control, optional
/// leading mark.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final t = title;
    final sub = subtitle;
    return Row(
      children: [
        if (leading != null) ...[
          leading!,
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: t == null
              ? const SizedBox.shrink()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t,
                      style: AppTypography.sectionTitle.copyWith(color: s.ink),
                    ),
                    if (sub != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          sub,
                          style: AppTypography.caption.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.md),
          trailing!,
        ],
      ],
    );
  }
}

/// The card body under an optional header: one implementation for FormCard
/// and SectionCard.
class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.padding,
    this.color,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = cardPadFor(context);
    final hasHeader = title != null || trailing != null;
    final flush = _isFlush(context, padding);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(s, color: color),
      // Start, not stretch: a button or a min-size row in the body keeps its
      // own width instead of being pulled to the card's.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader)
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
              child: _CardHeader(
                title: title,
                subtitle: subtitle,
                trailing: trailing,
                leading: leading,
              ),
            ),
          if (hasHeader && flush) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, thickness: 1, color: s.edge),
          ],
          Padding(
            padding:
                padding ??
                (hasHeader
                    ? EdgeInsets.fromLTRB(pad, AppSpacing.lg, pad, pad)
                    : EdgeInsets.all(pad)),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A card that holds a form or a block of content under a title.
class FormCard extends StatelessWidget {
  const FormCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.padding,
    this.trailing,
  });

  final Widget child;
  final String? title;

  /// One quiet line under the title.
  final String? subtitle;

  /// Body inset. Pass a zero top inset for a flush list or table: the card
  /// then rules a hairline under the title.
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => _Card(
    title: title,
    subtitle: subtitle,
    trailing: trailing,
    padding: padding,
    child: child,
  );
}

/// Label / value pairs in one card: keys in `label` and the secondary ink,
/// values in the primary ink, right-aligned in one column, 40 per row with a
/// hairline between rows.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.rows, this.title});

  final List<({String label, String value, bool isMono})> rows;
  final String? title;

  static const double _rowHeight = 40;
  static const double _keyColumn = 160;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final pad = cardPadFor(context);
    final t = title;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t != null) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, AppSpacing.md),
              child: Text(
                t,
                style: AppTypography.sectionTitle.copyWith(color: s.ink),
              ),
            ),
            Divider(height: 1, thickness: 1, color: s.edge),
          ],
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: pad,
                endIndent: pad,
                color: s.edge,
              ),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _rowHeight),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: pad,
                  vertical: AppSpacing.sm,
                ),
                child: _row(context, s, phone, rows[i]),
              ),
            ),
          ],
          if (rows.isNotEmpty) const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppScheme s,
    bool phone,
    ({String label, String value, bool isMono}) row,
  ) {
    final key = Text(
      row.label,
      style: AppTypography.label.copyWith(color: s.inkSecondary),
    );
    final valueStyle = row.isMono
        ? AppTypography.mono.copyWith(color: s.ink)
        : AppTypography.body.copyWith(
            color: s.ink,
            fontFeatures: const [FontFeature.tabularFigures()],
          );

    if (phone && row.isMono && row.value.length > 24) {
      // A txid / address / descriptor right-aligned beside a label wraps
      // into a ragged column; stacked it reads as one block.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          key,
          const SizedBox(height: AppSpacing.xs),
          SelectableText(row.value, style: valueStyle),
        ],
      );
    }
    final value = Text(row.value, style: valueStyle, textAlign: TextAlign.end);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (phone)
          Expanded(child: key)
        else
          SizedBox(width: _keyColumn, child: key),
        const SizedBox(width: AppSpacing.sm),
        if (phone) Flexible(flex: 2, child: value) else Expanded(child: value),
      ],
    );
  }
}

/// A titled section of a page: the same card as [FormCard], with an action
/// on the right of the title.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.action,
    this.leading,
    this.padding,
    this.color,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? action;

  /// A mark before the title that says what the section is about — a
  /// key-ring for a multisig. A fact, like any glyph: never decoration.
  final Widget? leading;

  /// Body inset. Pass a zero top inset for a flush list or table.
  final EdgeInsetsGeometry? padding;

  /// Overrides the `panel` fill. Use a surface token, never a tint.
  final Color? color;

  @override
  Widget build(BuildContext context) => _Card(
    title: title,
    subtitle: subtitle,
    trailing: action,
    leading: leading,
    padding: padding,
    color: color,
    child: child,
  );
}
