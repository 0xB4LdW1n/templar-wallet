// A card whose body folds away: a 56 tall header row with the title, a count
// or caption on the right and a chevron that turns; the body below it when
// open. For the things a page must keep but need not show first — closed
// loans, the long "how it works" — so the fact the page exists for stays
// above the fold.

import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'cards.dart';

class ExpanderCard extends StatefulWidget {
  const ExpanderCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.initiallyExpanded = false,
    this.padding,
  });

  final String title;

  /// One quiet line under the title, visible folded or not.
  final String? subtitle;

  /// A count or a tag on the right of the title row, before the chevron.
  final Widget? trailing;
  final Widget child;
  final bool initiallyExpanded;

  /// Body inset; defaults to the card padding of the window at hand. A zero
  /// top inset (a flush list) gets a hairline under the header.
  final EdgeInsetsGeometry? padding;

  @override
  State<ExpanderCard> createState() => _ExpanderCardState();
}

class _ExpanderCardState extends State<ExpanderCard> {
  late bool _open = widget.initiallyExpanded;

  static const double _headerHeight = 56;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final pad = cardPadFor(context);
    final sub = widget.subtitle;
    final flush =
        widget.padding != null &&
        widget.padding!.resolve(Directionality.of(context)).top == 0;

    final header = Semantics(
      button: true,
      expanded: _open,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => setState(() => _open = !_open),
          hoverColor: s.hover,
          highlightColor: s.pressed,
          focusColor: s.hover,
          splashFactory: NoSplash.splashFactory,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _headerHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pad,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: AppTypography.sectionTitle.copyWith(
                            color: s.ink,
                          ),
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
                  if (widget.trailing != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    widget.trailing!,
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: AppMotion.of(context, AppMotion.quick),
                    curve: AppMotion.settle,
                    child: Icon(
                      Icons.expand_more_outlined,
                      size: AppSpacing.icon,
                      color: s.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // The body is built only while open: a folded card holds nothing a
    // screen reader or a finder could still reach. It has to push the page
    // down, so its height follows the content (the one size animation the
    // kit allows), and the content itself fades in.
    final body = _open
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (flush) Divider(height: 1, thickness: 1, color: s.edge),
              Padding(
                padding:
                    widget.padding ?? EdgeInsets.fromLTRB(pad, 0, pad, pad),
                child: widget.child,
              ),
            ],
          )
        : const SizedBox(width: double.infinity, height: 0);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardDecoration(s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          AnimatedSize(
            duration: AppMotion.of(context, AppMotion.standard),
            curve: AppMotion.settle,
            alignment: Alignment.topCenter,
            // Opening fades the content in; closing just folds it away.
            child: _open
                ? TweenAnimationBuilder<double>(
                    key: const ValueKey('open'),
                    tween: Tween(begin: 0, end: 1),
                    duration: AppMotion.of(context, AppMotion.standard),
                    curve: AppMotion.settle,
                    builder: (_, t, c) => Opacity(opacity: t, child: c),
                    child: body,
                  )
                : body,
          ),
        ],
      ),
    );
  }
}
