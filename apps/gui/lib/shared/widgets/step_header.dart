import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'choice_list.dart';
import 'hybrid_kit.dart';

/// One step's header text, used to reserve the header's height up front.
/// See [StepHeader.variants].
class StepHeaderVariant {
  const StepHeaderVariant(this.title, [this.subtitle]);
  final String title;
  final String? subtitle;
}

/// The head of a wizard step (design.md, "Steps").
///
/// Top to bottom: the counter ("Step 2 of 6") with the way back before it and
/// Cancel opposite; a row of thin segments, one per step, done and current
/// in the primary ink; then the step's question as the title and an optional
/// line under it. No numbered circles: the count is stated once, in words.
///
/// The segments sit with the counter, above the title, so the height the
/// header reserves for its longest step ([variants]) opens between the text
/// and the body — where a gap reads as a paragraph break — and not between
/// the text and its own progress bar.
class StepHeader extends StatelessWidget {
  const StepHeader({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onCancel,
    this.variants,
    this.display = false,
  });

  final int currentStep;
  final int totalSteps;
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onCancel;

  /// Every title/subtitle pair this flow can show. Given them, the header
  /// reserves the height of its tallest step, so a two-line subtitle on step 3
  /// does not push the body — and everything under it — down the screen when
  /// the user arrives from a one-line step 2. Null: the header is exactly as
  /// tall as the text it holds.
  final List<StepHeaderVariant>? variants;

  /// The title in `displayTitle`, for a full-screen wizard outside the shell
  /// (no page title competes with it there). In-shell flows keep `pageTitle`.
  final bool display;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final titleStyle =
        (display
                ? AppTypography.displayTitleOf(context)
                : AppTypography.pageTitleOf(context))
            .copyWith(color: s.ink);
    final subtitleStyle =
        (phone ? AppTypography.bodyOf(context) : AppTypography.body).copyWith(
          color: s.inkSecondary,
        );
    // Read here, never inside the LayoutBuilder below: its builder runs during
    // layout, and an inherited dependency registered from there is re-checked
    // in the same phase — when the keyboard closes and MediaQuery changes
    // mid-layout, that marks this element dirty while it is being laid out and
    // the whole step fails to size (the body scroll view is left unlaid-out).
    final measure = _TextMeasure(
      scaler: MediaQuery.textScalerOf(context),
      ambient: DefaultTextStyle.of(context).style,
      direction: Directionality.of(context),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // The arrow keeps one place from the second step on. On the first
            // there is nothing to go back to, and the counter starts on the
            // title's own left edge instead of floating a slot away from it.
            if (onBack != null) ...[
              _BackSlot(onBack: onBack, phone: phone),
              const SizedBox(width: AppSpacing.xs),
            ],
            Expanded(
              child: Text(
                'Step $currentStep of $totalSteps',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
              ),
            ),
            if (onCancel != null)
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: s.inkSecondary,
                  minimumSize: phone
                      ? const Size(
                          AppLayout.minTouchTarget,
                          AppLayout.minTouchTarget,
                        )
                      : const Size(0, AppSpacing.controlHeightSmall),
                ),
                child: const Text('Cancel'),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _StepProgress(current: currentStep, total: totalSteps),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final block = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: titleStyle),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(subtitle!, style: subtitleStyle),
                  ),
              ],
            );
            final reserved = _reservedHeight(
              measure,
              constraints.maxWidth,
              titleStyle,
              subtitleStyle,
            );
            if (reserved == null) return block;
            return ConstrainedBox(
              constraints: BoxConstraints(minHeight: reserved),
              child: block,
            );
          },
        ),
      ],
    );
  }

  /// The height of the tallest [variants] entry at this width, or null when
  /// the flow did not declare its steps.
  double? _reservedHeight(
    _TextMeasure measure,
    double width,
    TextStyle titleStyle,
    TextStyle subtitleStyle,
  ) {
    final vs = variants;
    if (vs == null || vs.isEmpty || !width.isFinite || width <= 0) return null;
    var tallest = 0.0;
    for (final v in vs) {
      var h = measure.height(v.title, titleStyle, width);
      final sub = v.subtitle;
      if (sub != null && sub.isNotEmpty) {
        h += AppSpacing.sm + measure.height(sub, subtitleStyle, width);
      }
      tallest = math.max(tallest, h);
    }
    return tallest;
  }
}

/// Text metrics captured outside the layout phase — see [StepHeader.build].
class _TextMeasure {
  const _TextMeasure({
    required this.scaler,
    required this.ambient,
    required this.direction,
  });

  final TextScaler scaler;

  /// The ambient [DefaultTextStyle], merged in exactly as a [Text] merges it:
  /// measuring the bare style misses the theme's line height and under-
  /// reserves by a few pixels a line.
  final TextStyle ambient;
  final TextDirection direction;

  double height(String text, TextStyle style, double width) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: ambient.merge(style)),
      textDirection: direction,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }
}

/// The back arrow, at one size on every step that has one.
class _BackSlot extends StatelessWidget {
  const _BackSlot({required this.onBack, required this.phone});

  final VoidCallback? onBack;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final side = phone
        ? AppLayout.minTouchTarget
        : AppSpacing.controlHeightSmall;
    return IconButton(
      onPressed: onBack,
      tooltip: 'Back',
      icon: const Icon(Icons.arrow_back_outlined),
      iconSize: phone ? 22 : AppSpacing.icon,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(width: side, height: side),
      // No invisible tap-target padding around it: the arrow's box starts on
      // the column's left edge, in line with the title under it.
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// One thin bar per step: the primary ink for the steps behind you, the
/// accent for the one you are on ("you are here", design.md), the control
/// outline ahead. Nothing here reads inherited state inside a layout-phase
/// builder — see the note in [StepHeader.build].
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final duration = AppMotion.of(context, AppMotion.quick);
    return Row(
      children: List.generate(total, (i) {
        final reached = i < current;
        final here = i == current - 1;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < total - 1 ? AppSpacing.xs : 0),
            child: AnimatedContainer(
              duration: duration,
              curve: AppMotion.settle,
              height: 3,
              decoration: BoxDecoration(
                color: here
                    ? s.accent
                    : reached
                    ? s.ink
                    : s.edgeStrong,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// A standalone option with a radio (design.md, "Option card"): a card that
/// is chosen by its radio and a firmer edge, never by a filled slab or an
/// accent border. Under the pointer the card takes the hover layer; keyboard
/// focus is a ring.
class SelectableOptionCard extends StatefulWidget {
  const SelectableOptionCard({
    super.key,
    required this.title,
    required this.description,
    required this.isSelected,
    this.onTap,
    this.badge,
    this.icon,
  });

  final String title;
  final String description;
  final bool isSelected;

  /// Null: the option is shown but not on offer (drawn at half ink).
  final VoidCallback? onTap;

  /// A short fact beside the title ("Coming soon"), drawn as a quiet tag.
  final String? badge;
  final IconData? icon;

  @override
  State<SelectableOptionCard> createState() => _SelectableOptionCardState();
}

class _SelectableOptionCardState extends State<SelectableOptionCard> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final isSelected = widget.isSelected;
    final onTap = widget.onTap;
    final enabled = onTap != null;
    final badge = widget.badge;
    final icon = widget.icon;
    final lit = enabled && (_hover || _down);

    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    final fill = !lit
        ? s.panel
        : Color.alphaBlend(_down ? s.pressed : s.hover, s.panel);

    final card = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      padding: const EdgeInsets.all(AppSpacing.cardPaddingSmall),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(color: isSelected || lit ? s.edgeStrong : s.edge),
        boxShadow: s.panelShadow,
      ),
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: AppSpacing.icon, color: s.inkSecondary),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The title is Flexible so a long one wraps under the badge
                // instead of pushing past the card edge.
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        style:
                            (phone
                                    ? AppTypography.bodyOf(context)
                                    : AppTypography.body)
                                .copyWith(
                                  color: s.ink,
                                  fontWeight: FontWeight.w500,
                                ),
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      QuietTag(label: badge),
                    ],
                  ],
                ),
                if (widget.description.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.description,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          OptionRadio(selected: isSelected),
        ],
      ),
    );

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: isSelected,
      enabled: enabled,
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
              onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onTapDown: enabled ? (_) => setState(() => _down = true) : null,
          onTapUp: enabled ? (_) => setState(() => _down = false) : null,
          onTapCancel: enabled ? () => setState(() => _down = false) : null,
          child: Opacity(opacity: enabled ? 1 : 0.5, child: card),
        ),
      ),
    );
  }
}
