import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'hybrid_kit.dart';

// Tags (design.md, "Controls"): quiet text on `panelInset`. A status is a
// 6 px dot in its colour and a word in the secondary ink — never a filled
// pill, never a coloured outline.

enum BadgeVariant { success, warning, danger, accent, neutral }

/// A status tag. [BadgeVariant.success], [BadgeVariant.warning] and
/// [BadgeVariant.danger] draw their dot; [BadgeVariant.accent] and
/// [BadgeVariant.neutral] are the plain tag (the accent is never a status
/// colour). Shrink-wrapped, and when a Row hands it less than it needs the
/// label ellipsises instead of striping.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.variant = BadgeVariant.neutral,
    this.icon,
  });

  final String label;
  final BadgeVariant variant;

  /// A glyph before the word, for a neutral tag. A status variant draws its
  /// dot instead.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final Color? hue = switch (variant) {
      BadgeVariant.success => s.success,
      BadgeVariant.warning => s.warning,
      BadgeVariant.danger => s.danger,
      BadgeVariant.accent || BadgeVariant.neutral => null,
    };
    return QuietTag(label: label, dot: hue, icon: hue == null ? icon : null);
  }
}

/// An asset's ticker as a tag: `monoSmall`, upper-cased because a ticker is
/// data.
class AssetBadge extends StatelessWidget {
  /// The tag is the same for every asset; the chain is told by the asset's
  /// glyph.
  const AssetBadge({super.key, required this.ticker});

  final String ticker;

  @override
  Widget build(BuildContext context) =>
      QuietTag(label: ticker.toUpperCase(), mono: true);
}

/// One asset to pick, with its balance: a chip. Selected is the raised
/// surface with a firmer edge and the primary ink — the same grammar as
/// every other selection in the app.
class AssetChip extends StatefulWidget {
  const AssetChip({
    super.key,
    required this.ticker,
    required this.amount,
    this.isSelected = false,
    this.onTap,
  });

  final String ticker;
  final String amount;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  State<AssetChip> createState() => _AssetChipState();
}

class _AssetChipState extends State<AssetChip> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final tap = widget.onTap;
    final selected = widget.isSelected;
    final lit = tap != null && _hover;
    final radius = BorderRadius.circular(AppSpacing.radiusSm);

    final chip = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: selected ? s.selected : (lit ? s.hover : Colors.transparent),
        borderRadius: radius,
        border: Border.all(color: selected || lit ? s.edgeStrong : s.edge),
      ),
      foregroundDecoration: _focus && tap != null
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.ticker,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.label.copyWith(
              color: selected ? s.ink : s.inkSecondary,
            ),
          ),
          Text(
            widget.amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.numericSmall.copyWith(
              color: selected ? s.ink : s.inkSecondary,
            ),
          ),
        ],
      ),
    );

    return Semantics(
      button: tap != null,
      selected: selected,
      child: FocusableActionDetector(
        enabled: tap != null,
        mouseCursor: tap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: (v) => setState(() => _hover = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              tap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          child: chip,
        ),
      ),
    );
  }
}
