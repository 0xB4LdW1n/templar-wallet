import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';

/// An asset's glyph — one of the two places a chain hue is allowed
/// (design.md, "The accent").
///
///   BTC                  → the Bitcoin logo, as published (bitcoin.svg)
///   LIQUID (the chain)   → the Liquid Network emblem, as published
///                          (liquid.svg)
///   LBTC / legacy L-BTC  → Liquid teal disc, ₿ tilted 14° as in Bitcoin's
///                          mark (pegged to BTC, lives on Liquid)
///   any other token      → Liquid teal disc, the water drop
///
/// A reissuance token reuses its parent's glyph inside a dashed hairline ring:
/// the ring states a fact (this is a derived token), so it stays, drawn as
/// quietly as every other outline.
///
/// Sizes snap to the 4 px grid (24 / 32 / 40 are the usual ones).
class AssetLogo extends StatelessWidget {
  const AssetLogo({
    super.key,
    required this.ticker,
    this.size = 32,
    this.isReissuanceToken = false,
  });

  final String ticker;
  final double size;

  /// When true, draws the parent glyph inside a dashed ring to signal a
  /// derived (reissuance) token. Pass the *parent* ticker as [ticker].
  final bool isReissuanceToken;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final side = math.max(AppSpacing.lg, (size / 4).round() * 4.0);
    if (!isReissuanceToken) return _logo(s, side);

    // The ring takes the outer 4 px; the parent glyph sits inside it.
    return SizedBox.square(
      dimension: side,
      child: CustomPaint(
        painter: _DashedRingPainter(color: s.edgeStrong),
        child: Center(child: _logo(s, side - AppSpacing.sm)),
      ),
    );
  }

  Widget _logo(AppScheme s, double side) {
    final t = ticker.toUpperCase();
    final mark = switch (t) {
      'BTC' => bitcoinSvg,
      'LIQUID' => liquidSvg,
      _ => null,
    };
    if (mark != null) {
      return SvgPicture.asset(
        mark,
        width: side,
        height: side,
        excludeFromSemantics: true,
      );
    }
    final (hue, glyph, tilt) = switch (t) {
      'LBTC' || 'L-BTC' => (s.liquid, Icons.currency_bitcoin, _bitcoinTilt),
      _ => (s.liquid, Icons.water_drop, 0.0),
    };
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
      // White on the hue in both themes: the glyph is the asset's mark, not
      // text on a surface.
      child: Transform.rotate(
        angle: tilt,
        child: Icon(glyph, size: side * 0.64, color: Colors.white),
      ),
    );
  }

  /// The chains' own marks, drawn as their owners publish them.
  static const String bitcoinSvg = 'assets/images/bitcoin.svg';
  static const String liquidSvg = 'assets/images/liquid.svg';

  /// Bitcoin's mark leans its ₿ 14° clockwise.
  static const double _bitcoinTilt = 14 * math.pi / 180;
}

/// A dashed hairline ring (marks a reissuance token's glyph).
class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - paint.strokeWidth / 2;
    const dashCount = 16;
    const gapFraction = 0.45; // portion of each segment that is a gap
    const sweep = 2 * math.pi / dashCount;
    for (var i = 0; i < dashCount; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * (1 - gapFraction),
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

/// Wallet-type glyph used in the wallet picker: an outlined icon in the
/// secondary ink on the raised tile — the same tile a list row's icon sits on.
class WalletTypeIcon extends StatelessWidget {
  const WalletTypeIcon({super.key, required this.type, this.size = 40});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final icon = switch (type.toLowerCase()) {
      'multisig' => Icons.group_outlined,
      'watch-only' || 'watchonly' || 'watch_only' => Icons.visibility_outlined,
      _ => Icons.key_outlined,
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: s.panelInset,
        borderRadius: BorderRadius.circular(
          size > 40 ? AppSpacing.radiusLg : AppSpacing.radiusMd,
        ),
      ),
      child: Icon(
        icon,
        size: size >= 48 ? 24 : AppSpacing.icon,
        color: s.inkSecondary,
      ),
    );
  }
}
