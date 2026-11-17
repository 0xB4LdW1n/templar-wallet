import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The resolved colour scheme: one neutral ramp ("iron"), three inks, one
/// accent. Resolved once per build via [AppScheme.of].
///
/// Screens read `final s = AppScheme.of(context);` instead of branching on
/// `Theme.of(context).brightness` at every call site. Accent-derived values
/// route through the runtime-mutable [AppColors.accent], so per-wallet
/// re-tinting keeps working (never use these in const contexts).
///
/// The rules that go with these tokens are in design.md.
class AppScheme {
  const AppScheme._(this.isDark);

  /// For the context-free [ThemeData] builder only; widgets use [of].
  const AppScheme.forBrightness(Brightness b) : isDark = b == Brightness.dark;

  final bool isDark;

  static AppScheme of(BuildContext context) =>
      AppScheme._(Theme.of(context).brightness == Brightness.dark);

  // ── Surfaces: four steps, never a fifth ────────────────────────────────────

  /// The deepest step: the sidebar and the phone's tab bar. Chrome recedes.
  Color get chrome => isDark ? AppColors.chromeDark : AppColors.chromeLight;

  /// The page.
  Color get canvas =>
      isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

  /// The card.
  Color get panel => isDark ? AppColors.surfaceDark : AppColors.surfaceLight;

  /// Raised: a field, a glyph tile, a secondary button, the selected row or
  /// segment. The one tone above [panel].
  Color get panelInset =>
      isDark ? AppColors.surfaceDark2 : AppColors.raisedLight;

  /// A recess inside a card: the track of a segmented control, the box an
  /// address or descriptor is printed in. The page tone, so it reads as cut
  /// into the card rather than stacked on it.
  Color get well => canvas;

  /// The fill of the selected thing when it sits ON A CARD — a chosen chip,
  /// a selected row in a table. Selection is a surface step, not the accent.
  Color get selected => panelInset;

  /// The fill of the selected thing when it sits on the page, the chrome or
  /// a well — a nav row, the thumb of a segmented control, the current tab.
  /// On dark that is the same raised step; on light those grounds are
  /// already grey, so the step up from them is white.
  Color get thumb => isDark ? panelInset : panel;

  /// Row under the pointer.
  Color get hover => ink.withValues(alpha: isDark ? 0.045 : 0.04);

  /// Row under a press.
  Color get pressed => ink.withValues(alpha: isDark ? 0.08 : 0.07);

  /// Behind a dialog or sheet.
  Color get scrim => Colors.black.withValues(alpha: isDark ? 0.62 : 0.36);

  // ── Strokes ────────────────────────────────────────────────────────────────

  /// The hairline: every card edge, every row rule.
  Color get edge => ink.withValues(alpha: isDark ? 0.08 : 0.12);

  /// A control's outline, a selected card's edge.
  Color get edgeStrong => ink.withValues(alpha: isDark ? 0.18 : 0.24);

  /// The keyboard-focus ring and a focused field. Neutral on purpose: the
  /// accent is red, and a red ring around a field reads as an error.
  Color get focus => ink.withValues(alpha: isDark ? 0.55 : 0.6);

  // ── Ink: three roles ───────────────────────────────────────────────────────
  Color get ink => isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
  Color get inkSecondary =>
      isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;

  /// Meta and captions only — it sits near 4.5:1, not above it.
  Color get inkFaint => isDark ? AppColors.textMutedDark : AppColors.textMuted;

  // ── Status / chain ─────────────────────────────────────────────────────────
  // The light values are darkened so they pass as text on white: status is
  // often a caption.
  Color get success =>
      isDark ? AppColors.successMuted : const Color(0xFF15803D);
  Color get warning =>
      isDark ? AppColors.warningMuted : const Color(0xFFA8590B);
  Color get danger =>
      isDark ? const Color(0xFFF06A6A) : const Color(0xFFD32020);
  Color get testnet => warning;

  /// A fee bump (design.md, "Colour as data"): the double bolt of "Speed
  /// up", and — as a fill — the state of a transaction whose fee was
  /// raised. Yellow: the fee's amber, brightened into a signal.
  Color get boost => const Color(0xFFF5C518);

  /// [boost] as a glyph on a neutral surface: itself on dark, deepened on
  /// light so the bolt still reads.
  Color get boostGlyph => isDark ? boost : const Color(0xFFA16207);

  /// Ink on a [boost] fill.
  Color get onBoost => const Color(0xFF16171A);

  /// The tick of a bump that was made, on a [boost] fill: a green deep
  /// enough to stand on the yellow in both themes.
  Color get boostDone => const Color(0xFF15803D);

  /// A wait: the dot of a pending status and the breathing edge of its row
  /// in Activity. Orange, apart from [warning]'s amber — a pending payment
  /// is not a problem, it is in motion.
  Color get pending =>
      isDark ? const Color(0xFFF28C38) : const Color(0xFFC2590A);
  Color get bitcoin => isDark ? AppColors.bitcoin : const Color(0xFFC46F00);
  Color get liquid => isDark ? const Color(0xFF35B8B0) : AppColors.liquid;

  // ── Data hues ──────────────────────────────────────────────────────────────
  // Colour that states a fact (design.md, "Colour as data"): the role of a
  // box in a transaction's flow, the size tier of a coin, an asset's slice
  // of a chart, the colour a wallet was given. Never chrome, never a title.
  // The light values are darkened so each passes as text on white.
  Color get hueSlate =>
      isDark ? const Color(0xFF8B93A7) : const Color(0xFF5F6878);
  Color get hueTeal =>
      isDark ? const Color(0xFF35B8AC) : const Color(0xFF0B7F75);
  Color get hueBlue =>
      isDark ? const Color(0xFF5D9BE8) : const Color(0xFF2B68BC);
  Color get hueViolet =>
      isDark ? const Color(0xFFA78BFA) : const Color(0xFF7446DB);
  Color get hueGold =>
      isDark ? const Color(0xFFE8B54A) : const Color(0xFF8F6200);
  Color get hueRose =>
      isDark ? const Color(0xFFE879A6) : const Color(0xFFBC3470);

  /// The slices of a chart, in a fixed order, so an asset keeps its colour
  /// from one screen to the next. Chain coins use [bitcoin] / [liquid].
  List<Color> get series => [
    hueBlue,
    hueViolet,
    hueGold,
    hueRose,
    hueTeal,
    hueSlate,
  ];

  /// A surface washed with [hue]: the fill of a thing whose colour is data.
  /// A few percent over [on] (the card by default), never a saturated slab.
  Color wash(Color hue, {Color? on}) => Color.alphaBlend(
    hue.withValues(alpha: isDark ? 0.10 : 0.07),
    on ?? panel,
  );

  /// The hairline of a washed surface.
  Color washEdge(Color hue) => hue.withValues(alpha: isDark ? 0.42 : 0.5);

  // The roles in a transaction's flow.
  /// Change: the part that comes back to this wallet.
  Color get flowChange => hueBlue;

  /// The network fee: the part that is spent and gone.
  Color get flowFee => warning;

  // ── Accent (runtime-mutable — never const) ─────────────────────────────────
  // A fill, a line in the chart, the seal. Not a text colour on a dark
  // surface: lightened enough to read there it would be the danger red.

  Color get accent => AppColors.accent;

  /// Ink on an accent fill.
  Color get onAccent => AppColors.onAccent;

  /// The accent as a glyph: the icon of a secondary or ghost button, the
  /// icon of the current destination, a spinner. The accent itself where it
  /// already stands 3:1 clear of the raised surface; otherwise lifted (on
  /// dark) or deepened (on light) just far enough to — still the wallet's
  /// own colour, and still short of the danger red, which is kept brighter
  /// on purpose. Glyphs only: text is never set in it.
  Color get accentGlyph {
    final base = AppColors.accent;
    // Asked for by every button and nav row on every build: worked out
    // once per accent and brightness.
    final key = Object.hash(base.toARGB32(), isDark);
    if (key == _glyphKey) return _glyph;
    _glyphKey = key;
    return _glyph = _glyphOf(base);
  }

  static int? _glyphKey;
  static Color _glyph = AppColors.accentDefault;

  Color _glyphOf(Color base) {
    final ground = panelInset;
    if (_contrast(base, ground) >= 3) return base;
    final hsl = HSLColor.fromColor(base);
    var l = hsl.lightness;
    for (var i = 0; i < 40; i++) {
      l = (l + (isDark ? 0.02 : -0.02)).clamp(0.0, 1.0);
      final c = hsl.withLightness(l).toColor();
      if (_contrast(c, ground) >= 3) return c;
    }
    return hsl.withLightness(l).toColor();
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// The chart's area under its line — the one tint of the accent in the app.
  Color get accentSoft =>
      AppColors.accent.withValues(alpha: isDark ? 0.16 : 0.12);

  // ── Elevation ──────────────────────────────────────────────────────────────

  /// Cards cast nothing on dark (surface steps and hairlines do the work)
  /// and a whisper on light.
  List<BoxShadow> get panelShadow => isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ];

  /// Things that float over the page: dialogs, sheets, menus, tooltips.
  List<BoxShadow> get floatShadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
      blurRadius: isDark ? 40 : 24,
      offset: Offset(0, isDark ? 16 : 8),
    ),
  ];
}
