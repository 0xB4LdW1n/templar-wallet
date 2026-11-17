// The detail of one Liquid asset, in the anatomy of a transaction's detail
// (History): a glyph row, the figure, its facts as key/value rows, the id in
// a code box, and the ways out at the foot. A dialog on desktop, a sheet on a
// phone — `showAppDialog` decides.
//
// Nothing here moves coins. Send, Receive, Reissue and Burn hand the user to
// their own screens, which carry the review step and the password gate.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../features/dashboard/models/dashboard_data.dart';
import '../../services/asset_registry_service.dart';
import '../../services/issued_asset_store.dart';
import '../../services/price_service.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Opens the detail of [asset] as the app's dialog (a sheet on a phone).
///
/// - [reissuanceToken]: the reissuance token of [asset] this wallet holds,
///   when it holds one; its row opens the token's own detail.
/// - [issued]: what this device recorded when the asset was issued here
///   (name, ticker, precision, domain) — the fallback when the registry has
///   nothing, and what marks the asset as issued by this wallet.
/// - [isReissuanceToken]: [asset] itself is a reissuance token.
/// - [isHidden] / [onToggleHidden]: the overview's hide switch; the control
///   is left out when [onToggleHidden] is null.
///
/// [context] must sit under the app's router: the actions navigate with it
/// after the dialog closes.
Future<void> showAssetDetailDialog(
  BuildContext context, {
  required AssetBalance asset,
  AssetBalance? reissuanceToken,
  IssuedAssetEntry? issued,
  bool isReissuanceToken = false,
  bool isHidden = false,
  VoidCallback? onToggleHidden,
}) {
  return showAppDialog<void>(
    context,
    builder: (dialogContext) => AssetDetail(
      asset: asset,
      reissuanceToken: reissuanceToken,
      issued: issued,
      isReissuanceToken: isReissuanceToken,
      isHidden: isHidden,
      onToggleHidden: onToggleHidden,
      // Leave the dialog first, then act from the page's context, which
      // outlives it.
      onNavigate: (route) {
        Navigator.of(dialogContext).pop();
        if (context.mounted) context.go(route);
      },
      onOpenToken: reissuanceToken == null
          ? null
          : () {
              Navigator.of(dialogContext).pop();
              if (!context.mounted) return;
              showAssetDetailDialog(
                context,
                asset: reissuanceToken,
                issued: issued,
                isReissuanceToken: true,
              );
            },
    ),
  );
}

/// The Reissue or Burn screen with [assetId] already chosen. The screens
/// read the `asset` query parameter and fall back to their own default.
String liquidOperationRoute(String route, String assetId) =>
    Uri(path: route, queryParameters: {'asset': assetId}).toString();

/// The asset's display name: the registry, then what this device recorded at
/// issuance, then the engine's own name.
String liquidAssetName(
  AssetBalance asset, {
  IssuedAssetEntry? issued,
  bool isRt = false,
}) {
  final reg = AssetRegistryService.instance;
  if (reg.get(asset.assetId)?.name != null) return reg.displayName(asset);
  if (isRt && issued != null && issued.name.isNotEmpty) {
    return '${issued.name} reissuance token';
  }
  if (!isRt && issued != null && issued.name.isNotEmpty) return issued.name;
  final name = reg.displayName(asset, isRt: isRt);
  return name == 'Unknown Asset' ? liquidAssetTicker(asset) : name;
}

/// The asset's ticker, with the same precedence as [liquidAssetName].
String liquidAssetTicker(
  AssetBalance asset, {
  IssuedAssetEntry? issued,
  bool isRt = false,
}) {
  final reg = AssetRegistryService.instance;
  if (reg.get(asset.assetId)?.ticker != null) return reg.displayTicker(asset);
  if (!isRt && issued != null && issued.ticker.isNotEmpty) {
    return issued.ticker;
  }
  return reg.displayTicker(asset, isRt: isRt);
}

/// "1,000 FOO" → the number, and its unit.
(String, String?) splitAmountUnit(String text) {
  final i = text.lastIndexOf(' ');
  if (i <= 0) return (text, null);
  return (text.substring(0, i), text.substring(i + 1));
}

/// The dialog's body. Public for tests; open it with [showAssetDetailDialog].
class AssetDetail extends StatelessWidget {
  const AssetDetail({
    super.key,
    required this.asset,
    required this.onNavigate,
    this.reissuanceToken,
    this.issued,
    this.isReissuanceToken = false,
    this.isHidden = false,
    this.onToggleHidden,
    this.onOpenToken,
  });

  final AssetBalance asset;
  final AssetBalance? reissuanceToken;
  final IssuedAssetEntry? issued;
  final bool isReissuanceToken;
  final bool isHidden;
  final VoidCallback? onToggleHidden;
  final VoidCallback? onOpenToken;

  /// Close the dialog and go to a route.
  final ValueChanged<String> onNavigate;

  bool get _isLbtc => asset.ticker == 'LBTC';

  String _explorerUrl(String base) {
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmed/asset/${asset.assetId}';
  }

  Future<void> _openExplorer(BuildContext context, String base) async {
    final url = _explorerUrl(base);
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    // Nothing took the link: hand it over rather than fail silently.
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text("Couldn't open a browser — explorer link copied"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final masked = balancesHidden(context);
    final watchOnly = context.select<AppState, bool>(
      (st) => st.isActiveWalletWatchOnly,
    );
    // Null on a regtest: no public explorer knows that chain.
    final explorer = context.select<AppState, String?>(
      (st) => st.liquidExplorerBase,
    );
    final info = AssetRegistryService.instance.get(asset.assetId);
    final isRt = isReissuanceToken;
    final name = liquidAssetName(asset, issued: issued, isRt: isRt);
    final ticker = liquidAssetTicker(asset, issued: issued, isRt: isRt);
    final (figure, unit) = splitAmountUnit(asset.displayAmount);
    // Only L-BTC has a price (the BTC price; it is pegged one to one). A
    // token without a price feed shows no fiat line rather than a made-up
    // one.
    final fiat = _isLbtc && !masked
        ? PriceService.instance.fiatDisplay(asset.amount)
        : null;
    final precision = info?.precision ?? issued?.precision;
    final domain = (info?.domain?.isNotEmpty ?? false)
        ? info!.domain
        : ((issued?.domain.isNotEmpty ?? false) ? issued!.domain : null);
    final issuedHere = issued != null && !isRt;
    final coins = '${asset.utxoCount}';
    final token = reissuanceToken;

    // ── The figure ─────────────────────────────────────────────────────────
    final figureRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  masked ? kMaskedAmount : figure,
                  maxLines: 1,
                  style: AppTypography.numericLargeOf(
                    context,
                  ).copyWith(color: s.ink),
                ),
                if (!masked) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    unit ?? ticker,
                    maxLines: 1,
                    style: AppTypography.numeric.copyWith(color: s.inkFaint),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        const PrivacyToggle(),
      ],
    );

    // ── Verbs on the asset ─────────────────────────────────────────────────
    // Reissue needs the token; burning needs something to burn. L-BTC is
    // the chain's own coin: it is neither reissued nor burnt from here.
    final canIssueOps = !_isLbtc && !isRt && !watchOnly;
    final showReissue = canIssueOps && (issuedHere || token != null);
    final canReissue = showReissue && token != null && token.amount > 0;
    final canBurn = canIssueOps && asset.amount > 0;
    final reasons = <String>[
      if (watchOnly) 'Watch-only: this wallet cannot sign',
      if (showReissue && !canReissue)
        'Reissue needs the reissuance token, which this wallet does not hold',
      if (canIssueOps && !canBurn) 'Nothing to burn: this wallet holds none',
    ];

    final verbs = <Widget>[
      if (!watchOnly)
        SecondaryButton(
          label: 'Send',
          icon: Icons.north_east_outlined,
          isFullWidth: phone,
          onPressed: asset.amount > 0 ? () => onNavigate(AppRoutes.send) : null,
        ),
      SecondaryButton(
        label: 'Receive',
        icon: Icons.south_west_outlined,
        isFullWidth: phone,
        onPressed: () => onNavigate(AppRoutes.receive),
      ),
      if (showReissue)
        SecondaryButton(
          label: 'Reissue',
          icon: Icons.autorenew_outlined,
          isFullWidth: phone,
          onPressed: canReissue
              ? () => onNavigate(
                  liquidOperationRoute(AppRoutes.reissueAsset, asset.assetId),
                )
              : null,
        ),
      if (canIssueOps)
        DangerButton(
          label: 'Burn',
          icon: Icons.local_fire_department_outlined,
          isFullWidth: phone,
          onPressed: canBurn
              ? () => onNavigate(
                  liquidOperationRoute(AppRoutes.burnAsset, asset.assetId),
                )
              : null,
        ),
    ];

    final content = SizedBox(
      width: phone ? null : 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              AssetLogo(
                ticker: asset.ticker,
                size: 32,
                isReissuanceToken: isRt,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  issuedHere ? 'Liquid · issued by this wallet' : 'Liquid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(color: s.inkSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          figureRow,
          if (fiat != null)
            Text(
              fiat,
              style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
            ),
          if (verbs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            if (phone)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < verbs.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.sm),
                    verbs[i],
                  ],
                ],
              )
            else
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: verbs,
              ),
          ],
          for (final r in reasons)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                r,
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          if (ticker.isNotEmpty && ticker != asset.assetId)
            KvRow(label: 'Ticker', value: ticker, divider: true),
          if (precision != null)
            KvRow(label: 'Precision', value: '$precision', divider: true),
          KvRow(label: 'UTXOs', value: coins, divider: true),
          if (domain != null)
            KvRow(label: 'Issuer', value: domain, divider: true),
          if (!isRt && !_isLbtc && (issuedHere || token != null))
            KvRow(
              label: 'Reissuance',
              value: token == null
                  ? 'Token not held'
                  : 'Token held · ${masked ? kMaskedAmount : token.displayAmount}',
              divider: true,
            ),
          if (isRt)
            KvRow(
              label: 'Role',
              value: 'Lets this wallet mint more of its asset',
              divider: true,
            ),
          if (isHidden)
            KvRow(
              label: 'Overview',
              value: 'Hidden from the overview',
              divider: true,
            ),
          if (onOpenToken != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: GhostButton(
                label: 'Open the reissuance token',
                icon: Icons.chevron_right_outlined,
                onPressed: onOpenToken,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          CodeBox(value: asset.assetId, label: 'Asset ID', maxLines: 2),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.visibility_off_outlined,
                  size: AppSpacing.iconSmall,
                  color: s.inkFaint,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Confidential asset: amounts are blinded on-chain',
                  style: AppTypography.caption.copyWith(color: s.inkFaint),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return AppDialog(
      title: Text(name),
      scrollable: true,
      content: content,
      actions: [
        if (explorer != null)
          GhostButton(
            label: 'View in explorer',
            icon: Icons.open_in_new_outlined,
            onPressed: () => _openExplorer(context, explorer),
          ),
        if (onToggleHidden != null)
          GhostButton(
            label: isHidden ? 'Unhide' : 'Hide',
            icon: isHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            onPressed: () {
              Navigator.of(context).pop();
              onToggleHidden!();
            },
          ),
        SecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
