import 'package:flutter/material.dart';

/// Raw palette. Screens read [AppScheme] (resolved per brightness); the
/// constants here are what it resolves to, plus the brand and chain hues.
///
/// One neutral ramp per brightness — "iron": graphite with a breath of cool
/// in it — and one accent. See design.md.
abstract final class AppColors {
  // ── Accent ────────────────────────────────────────────────────────────────
  // Templar crimson, the red of the cross in the brand mark. Runtime-mutable
  // so the wallet's own accent flows through the whole UI; every shade is
  // derived from the base, so one [applyAccent] call re-tints all of them.
  static const Color accentDefault = Color(0xFFC1121F);
  static Color _accent = accentDefault;

  static Color get accent => _accent;

  /// Ink that reads on a fill of the current accent: white on the brand
  /// crimson, near-black on a pale accent a wallet may have been given.
  static Color get onAccent => _accent.computeLuminance() > 0.42
      ? const Color(0xFF16171A)
      : Colors.white;

  /// Re-tint the whole app. Pass null to fall back to the brand default.
  static void applyAccent(Color? c) {
    _accent = (c ?? accentDefault).withAlpha(0xFF);
  }

  // ── Status ────────────────────────────────────────────────────────────────
  // Toned to sit inside the ramp. They carry meaning and nothing else.
  static const Color successMuted = Color(0xFF4CC38A);

  static const Color warning = Color(0xFFD97706);
  static const Color warningMuted = Color(0xFFE2B04A);

  // Danger is red and so is the accent, so the two are kept apart on
  // lightness: the accent is deep (L~41%), destructive is bright (L~60%).
  // Never darken this toward the accent. Destructive controls also carry an
  // icon or an explicit verb, never colour alone.
  static const Color danger = Color(0xFFEF4444);

  // ── Chain hues ────────────────────────────────────────────────────────────
  // Identification only: the glyph of an asset, the dot beside a network
  // name. Never a title colour, a border or a card fill.
  static const Color liquid = Color(0xFF0E8E8E);
  static const Color liquidLight = Color(0xFFDDF1F0);
  static const Color liquidMuted = Color(0xFF4DB6AC);
  static const Color liquidDark = Color(0xFF0A6E6E);

  static const Color bitcoin = Color(0xFFF7931A);
  static const Color bitcoinLight = Color(0xFFFFF1DE);
  static const Color bitcoinMuted = Color(0xFFFFB74D);
  static const Color bitcoinDark = Color(0xFFB76E00);

  // ── Iron ramp — light ─────────────────────────────────────────────────────
  static const Color backgroundLight = Color(0xFFF5F5F6);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color raisedLight = Color(0xFFEDEEF0);
  static const Color chromeLight = Color(0xFFEFEFF1);
  static const Color textPrimary = Color(0xFF16171A);
  static const Color textSecondary = Color(0xFF50535A);
  static const Color textMuted = Color(0xFF6C6F77);

  // ── Iron ramp — dark ──────────────────────────────────────────────────────
  // Four steps: chrome (deepest, the sidebar), page, card, raised. Depth is
  // these steps and a hairline; nothing glows and nothing casts light.
  static const Color chromeDark = Color(0xFF0E0F11);
  static const Color backgroundDark = Color(0xFF131416);
  static const Color surfaceDark = Color(0xFF18191C);
  static const Color surfaceDark2 = Color(0xFF222327);
  static const Color textPrimaryDark = Color(0xFFECEDEE);
  static const Color textSecondaryDark = Color(0xFFA0A2A8);
  static const Color textMutedDark = Color(0xFF84868D);
}
