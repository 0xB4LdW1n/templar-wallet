import 'package:flutter/material.dart';

/// Motion tokens — single source of truth for durations and easing.
///
/// Naming follows intent, not milliseconds, so a global retune (or the
/// reduced-motion gate) never requires touching call sites.
///
/// Always read durations through [AppMotion.of] (or [resolve]) so the OS
/// reduced-motion setting collapses animation app-wide.
abstract final class AppMotion {
  // ── Durations ───────────────────────────────────────────────────────────────
  /// Hover / pressed feedback, colour shifts. Never delays the user.
  static const Duration instant = Duration(milliseconds: 120);

  /// Selection changes, toggles, small reveals.
  static const Duration quick = Duration(milliseconds: 160);

  /// Menus, popovers, expansion.
  static const Duration standard = Duration(milliseconds: 220);

  /// Things that enter: a sheet, a dialog, the chart drawing itself.
  static const Duration emphasized = Duration(milliseconds: 360);

  /// The one long move: the chart's first draw.
  static const Duration grand = Duration(milliseconds: 500);

  // ── Easing ──────────────────────────────────────────────────────────────────
  /// The one curve: fast start, soft settle, no overshoot. Nothing in the
  /// app bounces.
  static const Curve settle = Cubic(0.22, 1, 0.36, 1);

  /// Entering elements. Same curve.
  static const Curve enter = settle;

  /// Exiting elements get out of the way fast.
  static const Curve exit = Curves.easeInCubic;

  // ── Reduced-motion gate ─────────────────────────────────────────────────────
  /// True when the OS asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Resolve a token duration against the reduced-motion setting.
  /// Reduced motion collapses movement to (near-)zero; state changes stay
  /// instant and legible instead of animated.
  static Duration of(BuildContext context, Duration token) =>
      reduced(context) ? Duration.zero : token;

  /// Same gate for raw values (e.g. AnimationController durations).
  static Duration resolve({
    required bool reducedMotion,
    required Duration token,
  }) => reducedMotion ? Duration.zero : token;
}

/// Route transition: the incoming page fades in quickly over the outgoing
/// one — no lateral slide, no parallax. Installed for every platform through
/// [ThemeData.pageTransitionsTheme], so macOS, Windows and Linux move the
/// same way instead of each inheriting its Material default (a slide from
/// the right on macOS).
class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // A MaterialPageRoute runs 300 ms; doing the whole fade in its first
    // half keeps the change quick while the route itself still settles.
    // On the way back out the same window applies, so a pop is as fast.
    final opacity = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOut),
      reverseCurve: const Interval(0.45, 1.0, curve: Curves.easeIn),
    );
    return FadeTransition(opacity: opacity, child: child);
  }
}
