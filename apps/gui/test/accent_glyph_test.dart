// The accent as a glyph (design.md, "The accent"): the icon of a neutral
// button, the current destination's icon, a spinner. Whatever colour a
// wallet was given, the glyph has to stand clear of the surface it sits on
// — and stay that wallet's colour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/services/wallet_customization_store.dart';
import 'package:templar_wallet/theme/app_colors.dart';
import 'package:templar_wallet/theme/app_scheme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  tearDown(() => AppColors.applyAccent(null));

  test(
    'every wallet colour reads as a glyph, in the dark and in the light',
    () {
      for (final accent in [
        AppColors.accentDefault,
        ...WalletCustomizationStore.palette,
      ]) {
        AppColors.applyAccent(accent);
        for (final b in Brightness.values) {
          final s = AppScheme.forBrightness(b);
          expect(
            _contrast(s.accentGlyph, s.panelInset),
            greaterThanOrEqualTo(3),
            reason: '$accent on $b',
          );
          // Still the wallet's hue: only its lightness may have moved.
          final was = HSLColor.fromColor(accent);
          final now = HSLColor.fromColor(s.accentGlyph);
          expect((now.hue - was.hue).abs(), lessThan(2), reason: '$accent hue');
        }
      }
    },
  );

  test('the brand crimson is lifted on dark, short of the danger red', () {
    AppColors.applyAccent(null);
    const dark = AppScheme.forBrightness(Brightness.dark);
    final glyph = dark.accentGlyph;
    expect(glyph, isNot(AppColors.accentDefault));
    // Danger is kept brighter on purpose; the glyph stays under it.
    expect(
      HSLColor.fromColor(glyph).lightness,
      lessThan(HSLColor.fromColor(dark.danger).lightness),
    );
  });

  test('a re-tint moves the glyph with it', () {
    const dark = AppScheme.forBrightness(Brightness.dark);
    AppColors.applyAccent(const Color(0xFF3B82F6));
    final blue = dark.accentGlyph;
    AppColors.applyAccent(null);
    expect(dark.accentGlyph, isNot(blue));
  });
}
