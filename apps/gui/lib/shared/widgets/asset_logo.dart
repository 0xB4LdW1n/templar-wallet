import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';

/// An asset's glyph: a flat circle in its chain's hue with a white mark — one
/// of the two places a chain hue is allowed (design.md, "The accent").
///
///   BTC                  → Bitcoin orange, ₿
///   LBTC / legacy L-BTC  → Liquid teal, ₿ (pegged to BTC, lives on Liquid)
///   any other token      → Liquid teal, the water drop
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
    final (hue, glyph) = switch (t) {
      'BTC' => (s.bitcoin, Icons.currency_bitcoin_outlined),
      'LBTC' || 'L-BTC' => (s.liquid, Icons.currency_bitcoin_outlined),
      _ => (s.liquid, Icons.water_drop_outlined),
    };
    return Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
      // White on the hue in both themes: the glyph is the asset's mark, not
      // text on a surface.
      child: Icon(glyph, size: side * 0.56, color: Colors.white),
    );
  }
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
