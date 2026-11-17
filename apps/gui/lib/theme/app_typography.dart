import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_layout.dart';

// One family for the interface, one partner for the things a user compares
// character by character.
//
//   IBM Plex Sans — every label, figure and headline
//   IBM Plex Mono — addresses, txids, fingerprints, descriptors, small meta
//
// Two weights, 400 and 500. Hierarchy is size and ink (AppScheme.ink /
// inkSecondary / inkFaint), not weight: nothing here is bold, nothing is
// uppercase, nothing under 40 px is tracked. Styles carry no colour — the
// caller picks the ink role.

abstract final class AppTypography {
  static const List<FontFeature> _tabular = [FontFeature.tabularFigures()];

  static TextStyle _sans(
    double size,
    double height, {
    FontWeight weight = FontWeight.w400,
    double tracking = 0,
    bool tabular = false,
  }) => GoogleFonts.ibmPlexSans(
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: tracking,
    fontFeatures: tabular ? _tabular : null,
  );

  static TextStyle _mono(
    double size,
    double height, {
    FontWeight weight = FontWeight.w400,
  }) => GoogleFonts.ibmPlexMono(
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    letterSpacing: 0,
  );

  // ── Figures ────────────────────────────────────────────────────────────────
  // Money. Always tabular, so a column of amounts lines up and a figure that
  // changes does not shift its neighbours.

  /// The balance: the one large thing on the Dashboard.
  static TextStyle get balanceHero => _sans(
    44,
    48,
    weight: FontWeight.w500,
    tracking: -0.88, // -0.02em: display size only
    tabular: true,
  );

  /// A card's lead figure.
  static TextStyle get balanceLarge =>
      _sans(28, 32, weight: FontWeight.w500, tabular: true);

  /// A secondary balance: an asset, a chain.
  static TextStyle get balanceMedium =>
      _sans(20, 28, weight: FontWeight.w500, tabular: true);

  static TextStyle get numericLarge =>
      _sans(20, 28, weight: FontWeight.w500, tabular: true);

  /// An amount in a row or a summary line.
  static TextStyle get numeric =>
      _sans(14, 20, weight: FontWeight.w500, tabular: true);

  static TextStyle get numericSmall => _sans(13, 20, tabular: true);

  // ── Titles ─────────────────────────────────────────────────────────────────

  /// The page's name. One per screen.
  static TextStyle get pageTitle => _sans(28, 32, weight: FontWeight.w500);

  /// The headline of a pre-wallet screen (picker, welcome, a wizard step).
  static TextStyle get displayTitle => _sans(32, 36, weight: FontWeight.w500);

  /// One wallet's name on the picker.
  static TextStyle get galleryTitle => _sans(20, 28, weight: FontWeight.w500);

  /// The product's name beside its mark on the entry screens.
  static TextStyle get brand => _sans(20, 28, weight: FontWeight.w500);

  /// A card's or a section's title.
  static TextStyle get sectionTitle => _sans(16, 24, weight: FontWeight.w500);

  // ── Text ───────────────────────────────────────────────────────────────────

  static TextStyle get bodyLarge => _sans(16, 24);

  /// Body, row titles.
  static TextStyle get body => _sans(14, 20);

  /// Secondary text under a title, help text.
  static TextStyle get bodySmall => _sans(13, 20);

  /// Captions and row subtitles.
  static TextStyle get caption => _sans(13, 20);

  /// A control's label, a key in a key/value row.
  static TextStyle get label => _sans(13, 20, weight: FontWeight.w500);

  /// The small label that names a block: "Assets", "Security", a table head.
  /// Sentence case, quiet — never uppercase.
  static TextStyle get eyebrow => _sans(12, 16, weight: FontWeight.w500);

  /// A button's text.
  static TextStyle get button => _sans(14, 20, weight: FontWeight.w500);

  /// The text of a `large` button: the screen's lead pair.
  static TextStyle get buttonLarge => _sans(16, 24, weight: FontWeight.w500);

  // ── Navigation ─────────────────────────────────────────────────────────────

  static TextStyle get navItem => _sans(15, 20);

  /// Sidebar group label. Same voice as [eyebrow].
  static TextStyle get navSection => eyebrow;

  static TextStyle get stepIndicator => eyebrow;

  // ── Mono ───────────────────────────────────────────────────────────────────

  static TextStyle get mono => _mono(13, 20);
  static TextStyle get monoSmall => _mono(12, 16);
  static TextStyle get monoLarge => _mono(15, 24, weight: FontWeight.w500);

  // ── Phone-scaled variants ──────────────────────────────────────────────────
  // The large styles above were drawn for a >= 1024 px window; on a phone
  // ([AppLayout.isPhone]) the same voice at a size that leaves room for
  // content. Desktop callers get the plain getter unchanged.

  static TextStyle balanceHeroOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(36, 40, weight: FontWeight.w500, tabular: true)
      : balanceHero;

  static TextStyle balanceLargeOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(24, 32, weight: FontWeight.w500, tabular: true)
      : balanceLarge;

  static TextStyle balanceMediumOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(18, 24, weight: FontWeight.w500, tabular: true)
      : balanceMedium;

  static TextStyle pageTitleOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(24, 28, weight: FontWeight.w500)
      : pageTitle;

  static TextStyle displayTitleOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(28, 32, weight: FontWeight.w500)
      : displayTitle;

  /// "Wallets" on the entry screen: the page is nothing but its title and
  /// the register, so the title is set a step above [displayTitle].
  static TextStyle get entryTitle =>
      _sans(40, 44, weight: FontWeight.w500, tracking: -0.8);

  static TextStyle entryTitleOf(BuildContext context) =>
      AppLayout.isPhone(context) ? displayTitleOf(context) : entryTitle;

  static TextStyle galleryTitleOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(17, 24, weight: FontWeight.w500)
      : galleryTitle;

  static TextStyle sectionTitleOf(BuildContext context) => sectionTitle;

  static TextStyle numericLargeOf(BuildContext context) =>
      AppLayout.isPhone(context)
      ? _sans(18, 24, weight: FontWeight.w500, tabular: true)
      : numericLarge;

  /// Body text on a phone is a step larger: 16 px is the floor below which
  /// iOS and Android zoom or users squint.
  static TextStyle bodyOf(BuildContext context) =>
      AppLayout.isPhone(context) ? _sans(15, 22) : body;

  static TextStyle buttonOf(BuildContext context) => AppLayout.isPhone(context)
      ? _sans(16, 24, weight: FontWeight.w500)
      : button;
}
