import 'package:flutter/material.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import 'cards.dart';

/// The plain card (design.md, "Controls"): `panel`, a hairline, radius 12,
/// padding 20. The same material as [FormCard] and [SectionCard], for
/// content that brings its own layout.
class PlainCard extends StatefulWidget {
  const PlainCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  /// Corner override for the rare card nested inside another (inner radius
  /// = outer − padding). Defaults to `radiusLg`.
  final double? borderRadius;

  /// When set, the whole card is the target: a hover step, a 2 px focus
  /// ring, Enter/Space activate.
  final VoidCallback? onTap;

  @override
  State<PlainCard> createState() => _PlainCardState();
}

class _PlainCardState extends State<PlainCard> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final r = widget.borderRadius ?? AppSpacing.radiusLg;
    final tap = widget.onTap;
    final lit = tap != null && _hover;

    final card = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      padding: widget.padding ?? EdgeInsets.all(cardPadFor(context)),
      decoration: cardDecoration(
        s,
        color: lit ? Color.alphaBlend(s.hover, s.panel) : s.panel,
      ).copyWith(borderRadius: BorderRadius.circular(r)),
      foregroundDecoration: _focus && tap != null
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: widget.child,
    );

    if (tap == null) return card;
    return FocusableActionDetector(
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            tap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tap,
        child: card,
      ),
    );
  }
}

/// A loading placeholder: a `panelInset` block whose opacity breathes while
/// the data it stands for is on its way. It moves because the wait is live;
/// under reduced motion it holds still.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppSpacing.radiusMd,
  });
  final double width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  // One breath in, one out: two of the longest motion token.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: AppMotion.grand * 2,
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _ctrl
        ..stop()
        ..value = 1;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return FadeTransition(
      opacity: _ctrl.drive(
        Tween<double>(
          begin: 0.45,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeInOut)),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: s.panelInset,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}
