import 'package:flutter/material.dart';

import '../../features/dashboard/models/dashboard_data.dart';
import '../../services/asset_registry_service.dart';
import '../../services/issued_asset_store.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'asset_logo.dart';
import 'badges.dart';
import 'hybrid_kit.dart';
import 'privacy.dart';

/// A parent asset together with its optional reissuance token (nested inside).
class AssetGroup {
  const AssetGroup({required this.main, this.reissuanceToken});
  final AssetBalance main;
  final AssetBalance? reissuanceToken;
}

/// Groups a flat asset list so reissuance tokens nest under their parent asset.
/// [issued] supplies the parent→token relationship for locally issued assets.
List<AssetGroup> groupAssets(
  List<AssetBalance> assets,
  Map<String, IssuedAssetEntry> issued,
) {
  // token_id → parent asset_id (from the local issued-asset store).
  final tokenToParent = <String, String>{};
  for (final e in issued.values) {
    if (e.tokenId != null) tokenToParent[e.tokenId!] = e.assetId;
  }

  final used = <String>{};
  final groups = <AssetGroup>[];

  for (final asset in assets) {
    if (used.contains(asset.assetId)) continue;
    // Skip tokens that belong to a parent we will render.
    if (tokenToParent.containsKey(asset.assetId)) continue;

    AssetBalance? tokenAsset;
    final entry = issued[asset.assetId];
    if (entry?.tokenId != null) {
      tokenAsset = assets.where((a) => a.assetId == entry!.tokenId).firstOrNull;
      if (tokenAsset != null) used.add(tokenAsset.assetId);
    }
    used.add(asset.assetId);
    groups.add(AssetGroup(main: asset, reissuanceToken: tokenAsset));
  }

  // Orphan reissuance tokens (parent not present on-chain).
  for (final asset in assets) {
    if (!used.contains(asset.assetId)) {
      groups.add(AssetGroup(main: asset));
    }
  }

  return groups;
}

/// The card for an [AssetGroup]: a plain card (`panel`, hairline, radius 12)
/// showing the parent asset. The asset's chain is told by its glyph alone.
/// If the group has a reissuance token, a quiet "Reissuance token" tag
/// appears; its details are in the sheet opened by [onTap].
class GroupedAssetCard extends StatelessWidget {
  const GroupedAssetCard({
    super.key,
    required this.group,
    required this.isHidden,
    required this.onTap,
    this.showFiat,
    this.amountOverride,
    this.compact = false,
  });

  final AssetGroup group;

  /// The user has hidden this asset from the overview: its name and figure
  /// drop to the secondary ink and an eye-off glyph says why.
  final bool isHidden;

  /// One full-width row instead of the vertical grid tile: logo, name and
  /// ticker on the left, the amount right-aligned. For a phone column, where
  /// a 190-px grid cell stretched to the full width is mostly empty space.
  /// The amount ellipsises rather than pushing the name off the row.
  final bool compact;

  /// Replaces the backend-formatted amount string (used to honor the BTC/sats
  /// unit preference for native coins). Null → show [AssetBalance.displayAmount].
  final String? amountOverride;

  /// Opens the asset detail sheet (which includes the RT if present).
  /// Null where no sheet exists — the card then renders non-interactive
  /// (no tap cursor, no dead affordance).
  final VoidCallback? onTap;

  /// Optional fiat string rendered under the amount (BTC / LBTC only).
  final String? showFiat;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final asset = group.main;
    final hasToken = group.reissuanceToken != null;
    final info = AssetRegistryService.instance.get(asset.assetId);
    final displayName = info?.name ?? asset.name;
    final displayTicker = info?.ticker ?? asset.ticker;
    final ink = isHidden ? s.inkSecondary : s.ink;
    final utxos = '${asset.utxoCount} UTXO${asset.utxoCount == 1 ? '' : 's'}';
    final (figure, unit) = _splitUnit(amountOverride ?? asset.displayAmount);

    final name = Text(
      displayName,
      style: (compact ? AppTypography.bodyOf(context) : AppTypography.body)
          .copyWith(color: ink, fontWeight: FontWeight.w500),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final hiddenGlyph = Icon(
      Icons.visibility_off_outlined,
      size: AppSpacing.iconSmall,
      color: s.inkFaint,
    );
    final meta = AppTypography.caption.copyWith(color: s.inkFaint);

    // The figure in the medium balance size, its unit one step down and
    // quiet beside it (design.md, "Type").
    Widget balance(TextAlign align) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Amount(
            figure,
            style: AppTypography.balanceMediumOf(context).copyWith(color: ink),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
          ),
        ),
        if (unit != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Text(
            unit,
            maxLines: 1,
            style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
          ),
        ],
      ],
    );

    Widget? fiat(TextAlign align) => showFiat == null
        ? null
        : Amount(
            showFiat!,
            style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
          );

    if (compact) {
      return _AssetSurface(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            AssetLogo(ticker: asset.ticker, size: 32),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(child: name),
                      if (isHidden) ...[
                        const SizedBox(width: AppSpacing.xs),
                        hiddenGlyph,
                      ],
                    ],
                  ),
                  Row(
                    children: [
                      AssetBadge(ticker: displayTicker),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          info?.domain ?? utxos,
                          style: meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  balance(TextAlign.end),
                  ?fiat(TextAlign.end),
                  if (hasToken) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const _ReissuanceTag(),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return _AssetSurface(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.cardPaddingSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AssetLogo(ticker: asset.ticker, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: AssetBadge(ticker: displayTicker)),
              const Spacer(),
              if (isHidden) hiddenGlyph,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          name,
          if (info?.domain != null)
            Text(info!.domain!, style: meta, overflow: TextOverflow.ellipsis),
          const SizedBox(height: AppSpacing.xs),
          balance(TextAlign.start),
          ?fiat(TextAlign.start),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(utxos, style: meta),
              // Non-interactive — the token's details live in the sheet.
              if (hasToken) const _ReissuanceTag(),
            ],
          ),
        ],
      ),
    );
  }

  /// "1,234.5 USDT" → ("1,234.5", "USDT"): the unit is drawn quieter than
  /// the figure. A string without a trailing word stays whole.
  static (String, String?) _splitUnit(String amount) {
    final t = amount.trim();
    final i = t.lastIndexOf(' ');
    if (i <= 0) return (t, null);
    final unit = t.substring(i + 1);
    // Only a word is a unit; "1 234" (a grouped figure) is not.
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9\-]*$').hasMatch(unit)) return (t, null);
    return (t.substring(0, i), unit);
  }
}

/// A card that knows the pointer: the hover and press layers over `panel`,
/// a focus ring, and nothing at all when it has no [onTap].
class _AssetSurface extends StatefulWidget {
  const _AssetSurface({
    required this.onTap,
    required this.padding,
    required this.child,
  });

  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Widget child;

  @override
  State<_AssetSurface> createState() => _AssetSurfaceState();
}

class _AssetSurfaceState extends State<_AssetSurface> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final onTap = widget.onTap;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);
    final lit = enabled && (_hover || _down);
    final card = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: lit
            ? Color.alphaBlend(_down ? s.pressed : s.hover, s.panel)
            : s.panel,
        borderRadius: radius,
        border: Border.all(color: lit ? s.edgeStrong : s.edge),
        boxShadow: s.panelShadow,
      ),
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: s.focus, width: 2),
            )
          : null,
      child: widget.child,
    );
    if (!enabled) return card;
    return Semantics(
      button: true,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() {
          _hover = v;
          if (!v) _down = false;
        }),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: card,
        ),
      ),
    );
  }
}

/// Says the asset carries a reissuance token. A fact, so a quiet tag.
class _ReissuanceTag extends StatelessWidget {
  const _ReissuanceTag();

  @override
  Widget build(BuildContext context) => const Tooltip(
    message: 'Has a reissuance token',
    child: QuietTag(label: 'RT', icon: Icons.autorenew_outlined),
  );
}
