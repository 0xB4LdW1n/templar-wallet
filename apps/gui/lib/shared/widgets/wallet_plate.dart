import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';

/// A wallet's mark: the icon of its kind on a `panelInset` tile, the same
/// glyph tile every list in the app uses.
///
/// The icon says what kind of wallet it is; the name beside it says which
/// one. The wallet's own colour — the one picked in Settings, the brand
/// crimson until then — is a 6 px dot in the tile's corner: identification,
/// not decoration, and because the same widget draws the picker, the
/// sidebar and the phone header, the wallet picked is visibly the wallet
/// open.
class WalletPlate extends StatelessWidget {
  const WalletPlate({
    super.key,
    required this.icon,
    this.tint,
    this.size = 56,
    this.raised = false,
    this.fill,
  });

  final IconData icon;

  /// The wallet's own colour, drawn as the corner dot. Null draws none.
  final Color? tint;

  final double size;

  /// The pointer is on the card that holds the plate: the tile takes the
  /// firmer edge. It does not move.
  final bool raised;

  /// The tile's fill when it is not the plain raised step: the entry
  /// screen washes it with the wallet's colour (`AppScheme.wash`).
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final t = tint;
    final glyph = size >= 44
        ? 24.0
        : size >= 40
        ? 22.0
        : size >= 28
        ? AppSpacing.icon
        : AppSpacing.iconSmall;

    final tile = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.settle,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill ?? s.panelInset,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: raised ? s.edgeStrong : Colors.transparent),
      ),
      child: Icon(icon, size: glyph, color: s.inkSecondary),
    );
    if (t == null) return tile;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            right: AppSpacing.xs,
            top: AppSpacing.xs,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: t,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
