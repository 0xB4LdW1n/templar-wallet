// The fee bump's own controls and glyph.
//
// Speeding a transaction up is the one action in Activity with a colour of
// its own (design.md, "Colour as data"): yellow, the fee's amber brightened
// into a signal. Before it, the button is the ordinary secondary one with a
// yellow double bolt; once the fee was raised it is the same slot filled
// yellow with a green tick — a state, not an invitation — and it opens the
// transaction's detail, where the bump is spelled out.

import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Two lightning bolts side by side: "faster". Drawn at an icon's [size].
class DoubleBolt extends StatelessWidget {
  const DoubleBolt({super.key, this.size = AppSpacing.iconSmall, this.color});

  final double size;

  /// The bolt's ink; the scheme's bump yellow when null.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? AppScheme.of(context).boostGlyph;
    // A bolt takes the middle two fifths of its icon box: two of them, set
    // a third of a box apart, read as one double mark.
    return SizedBox(
      width: size * 1.08,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -size * 0.16,
            top: 0,
            child: Icon(Icons.bolt, size: size, color: ink),
          ),
          Positioned(
            left: size * 0.22,
            top: 0,
            child: Icon(Icons.bolt, size: size, color: ink),
          ),
        ],
      ),
    );
  }
}

/// "Speed up": the secondary button with the yellow double bolt.
class SpeedUpButton extends StatelessWidget {
  const SpeedUpButton({
    super.key,
    required this.onPressed,
    this.label = 'Speed up',
    this.isLoading = false,
    this.isFullWidth = false,
    this.dense = true,
  });

  /// Null when the transaction cannot be sped up (the reason goes in the
  /// caller's tooltip).
  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;
  final bool isFullWidth;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    return SecondaryButton(
      label: label,
      leading: DoubleBolt(
        size: phone && !dense ? 20 : AppSpacing.iconSmall,
        color: onPressed == null ? s.inkFaint : s.boostGlyph,
      ),
      dense: dense,
      isLoading: isLoading,
      isFullWidth: isFullWidth,
      onPressed: onPressed,
    );
  }
}

/// The fee was raised: the "Speed up" slot filled yellow, with a green
/// tick. Tapping it opens the transaction's detail.
class SpedUpButton extends StatefulWidget {
  const SpedUpButton({
    super.key,
    required this.onPressed,
    this.label = 'Sped up',
    this.isFullWidth = false,
  });

  final VoidCallback onPressed;
  final String label;
  final bool isFullWidth;

  @override
  State<SpedUpButton> createState() => _SpedUpButtonState();
}

class _SpedUpButtonState extends State<SpedUpButton> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final radius = phone ? AppSpacing.radiusPhoneControl : AppSpacing.radiusMd;
    final fill = Color.alphaBlend(
      s.onBoost.withValues(alpha: _down ? 0.14 : (_hover ? 0.07 : 0)),
      s.boost,
    );
    final body = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      width: widget.isFullWidth ? double.infinity : null,
      height: phone ? AppLayout.minTouchTarget - 4 : AppSpacing.controlHeight,
      padding: EdgeInsets.symmetric(
        horizontal: phone ? AppSpacing.md : AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Row(
        mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _GreenTick(),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.button.copyWith(color: s.onBoost),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: '${widget.label}. Show details',
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
              widget.onPressed();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: AnimatedScale(
            scale: AppMotion.reduced(context) || !_down ? 1.0 : 0.98,
            duration: AppMotion.of(context, AppMotion.instant),
            curve: AppMotion.settle,
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The tick of a bump that was made: a green disc, a white check. On the
/// yellow fill a bare green glyph would not read; a disc does.
class _GreenTick extends StatelessWidget {
  const _GreenTick();

  @override
  Widget build(BuildContext context) => Container(
    width: AppSpacing.iconSmall,
    height: AppSpacing.iconSmall,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppScheme.of(context).boostDone,
      shape: BoxShape.circle,
    ),
    child: const Icon(Icons.check, size: AppSpacing.md, color: Colors.white),
  );
}
