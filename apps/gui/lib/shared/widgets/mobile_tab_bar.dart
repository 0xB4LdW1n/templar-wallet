import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'hybrid_kit.dart' show CurrentMark;

/// One destination in the phone's tab bar.
class MobileTabItem {
  const MobileTabItem({
    required this.id,
    required this.label,
    required this.route,
    required this.icon,
  });

  final String id;
  final String label;
  final String route;
  final IconData icon;
}

/// The phone's navigation: every destination visible and labelled, one tap
/// away (design.md, "Navigation").
///
/// It sits on [AppScheme.chrome], the deepest surface, because chrome
/// recedes. The current tab is [AppScheme.thumb] behind its icon and the
/// primary ink — selection is a surface step here as everywhere else — with
/// the [CurrentMark] round that pill, the sidebar row's border.
class MobileTabBar extends StatelessWidget {
  const MobileTabBar({
    super.key,
    required this.items,
    required this.currentRoute,
    required this.onSelect,
    this.onReselect,
  });

  final List<MobileTabItem> items;
  final String currentRoute;
  final ValueChanged<String> onSelect;

  /// The current tab tapped again: the shell scrolls its page to the top.
  final VoidCallback? onReselect;

  /// The bar's height over a bottom system inset of [bottomInset].
  static double heightFor(double bottomInset) =>
      AppSpacing.phoneTabBarHeight + bottomInset;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final inset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      height: heightFor(inset),
      padding: EdgeInsets.only(bottom: inset),
      decoration: BoxDecoration(
        color: s.chrome,
        border: Border(top: BorderSide(color: s.edge)),
      ),
      // Past this scale six labels no longer fit a 360 dp phone on one line.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              Expanded(
                child: _Tab(
                  item: item,
                  selected: item.route == currentRoute,
                  onTap: () {
                    if (item.route == currentRoute) {
                      onReselect?.call();
                    } else {
                      HapticFeedback.selectionClick();
                      onSelect(item.route);
                    }
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.item, required this.selected, required this.onTap});

  final MobileTabItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final ink = selected ? s.ink : s.inkFaint;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(onTap: onTap, child: _body(context, s, ink)),
    );
  }

  Widget _body(BuildContext context, AppScheme s, Color ink) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // "You are here": the current tab's pill wears the accent's border
        // and its glyph the accent.
        CurrentMark(
          active: selected,
          radius: AppSpacing.radiusMd,
          child: AnimatedContainer(
            duration: AppMotion.of(context, AppMotion.quick),
            curve: AppMotion.settle,
            width: 48,
            height: 28,
            decoration: BoxDecoration(
              color: selected ? s.thumb : s.thumb.withValues(alpha: 0),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              item.icon,
              size: 22,
              color: selected ? s.accentGlyph : ink,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          item.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.eyebrow.copyWith(
            color: ink,
            fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
