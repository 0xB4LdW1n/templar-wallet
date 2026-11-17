import 'package:flutter/widgets.dart';

import 'app_layout.dart';

export 'app_layout.dart';

/// Everything sits on a 4 px grid. Space shows grouping: less inside a group
/// than between two of them.
abstract final class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;
  static const double huge = 64.0;

  // Card / container padding
  static const double cardPadding = 20.0;
  static const double cardPaddingSmall = 16.0;

  // Radius by size. Nested radii add up: inner = outer − padding, floor 4.
  /// Tags, keycaps.
  static const double radiusXs = 4.0;

  /// Chips, small controls, a segment inside a segmented track.
  static const double radiusSm = 6.0;

  /// Buttons, fields, rows.
  static const double radiusMd = 8.0;

  /// Cards.
  static const double radiusLg = 12.0;

  /// The hero, dialogs, sheets.
  static const double radiusXl = 16.0;

  // Desktop control metrics.
  /// A button, a field, a segmented control.
  static const double controlHeight = 36.0;

  /// The screen's lead pair of buttons (`large: true`).
  static const double controlHeightLarge = 48.0;

  /// A button in a dense toolbar or a table row.
  static const double controlHeightSmall = 28.0;

  /// A navigation row.
  static const double navRowHeight = 40.0;

  /// The icon of a navigation row.
  static const double navIcon = 20.0;

  /// A row in a grouped list.
  static const double rowHeight = 56.0;

  /// The icon everywhere in chrome: one size, the ink of its text role.
  static const double icon = 18.0;
  static const double iconSmall = 16.0;

  // Phone control metrics. Nothing on a desktop path reads these.
  /// A filled phone button.
  static const double phoneControlHeight = 54.0;

  /// A phone text field. Above [AppLayout.minTouchTarget] by design.
  static const double phoneFieldHeight = 56.0;

  /// The corner of a phone button and field.
  static const double radiusPhoneControl = 12.0;

  /// The phone's tab bar, above the gesture inset.
  static const double phoneTabBarHeight = 60.0;

  // Sidebar
  static const double sidebarWidth = 264.0;
  static const double sidebarWidthCollapsed = 60.0;

  /// Widest a page's content column grows before it stops and centres.
  static const double contentMaxWidth = 1200.0;

  /// A form or a wizard step: one readable column.
  static const double formMaxWidth = 640.0;

  /// Page padding for the window at hand: [lg] on a phone (under 600 dp),
  /// [xl] on a small tablet (under 905 dp), the desktop [xxl] above that.
  /// Phone predicate — see [AppLayout.isPhone]; re-exported here so a screen
  /// that already imports the spacing tokens needs nothing else.
  static bool isPhone(BuildContext context) => AppLayout.isPhone(context);

  static double pagePadding(BuildContext context) {
    // Desktop windows are floored at 1024 px by every runner, so the answer
    // is a constant there — and skipping MediaQuery avoids rebuilding every
    // screen on each window-resize frame.
    if (!AppLayout.isMobilePlatform) return xxl;
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return lg;
    if (width < 905) return xl;
    return xxl;
  }
}
