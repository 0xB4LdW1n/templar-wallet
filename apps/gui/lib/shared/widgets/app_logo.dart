import 'package:flutter/material.dart';
import '../../theme/app_scheme.dart';

/// App brand mark — the Templar cross on the dark brand squircle, drawn as
/// the artwork is: no glow, no shadow, no tile behind it.
///
/// Renders `assets/images/templar-wallet-logo.png`; if the asset is ever
/// missing, a plain `panelInset` square with a shield glyph keeps the layout
/// so the app still builds.
///
/// Both that PNG and the platform app icons are BUILD PRODUCTS of
/// `assets/brand/templar-icon.svg` — edit the SVG, then run
/// `./scripts/generate_icons.sh`. Do not hand-edit the rasters.
/// `assets/images/templar-cross.svg` is the bare mark (no squircle) for places
/// that need the cross on its own.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 40, this.radius});

  final double size;

  /// Corner of the fallback square only; the PNG carries its own squircle.
  final double? radius;

  @override
  Widget build(BuildContext context) {
    // No ClipRRect: the PNG carries its own squircle with transparent corners,
    // and clipping it again shaved a second, tighter radius off the artwork.
    return Image.asset(
      'assets/images/templar-wallet-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (context, _, _) => _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(radius ?? size * 0.25),
      ),
      child: Icon(
        Icons.shield_outlined,
        color: s.inkSecondary,
        size: size * 0.5,
      ),
    );
  }
}
