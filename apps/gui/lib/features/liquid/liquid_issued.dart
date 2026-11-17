// "Issued assets": the three asset operations — issue, reissue, burn — and
// under them the assets this wallet issued, as this device recorded them at
// issuance (IssuedAssetStore) joined with what the engine says the wallet
// holds.
//
// An issued asset is two things, and the list keeps them apart: the asset
// itself (the units in circulation, which a burn destroys) and its
// reissuance token (the token whose holder may mint more). Each has its own
// line, its own glyph and its own balance, so "can I reissue this?" is read
// off the token line instead of being guessed from a disabled button.
//
// The operations only open the existing screens; review and the password
// gate live there.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../features/dashboard/models/dashboard_data.dart';
import '../../services/issued_asset_store.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'asset_detail_dialog.dart';

/// Opens an issued asset's detail: its record, its holding (or a zero
/// placeholder when none is held) and its reissuance token, when held.
typedef OpenIssued =
    void Function(
      IssuedAssetEntry entry,
      AssetBalance asset,
      AssetBalance? token,
    );

/// One of the three operations, as the strip draws it.
typedef _Operation = ({
  IconData icon,
  String title,
  String caption,
  String route,
  bool destructive,
});

const List<_Operation> _operations = [
  (
    icon: Icons.add,
    title: 'Issue',
    caption: 'Create a new asset',
    route: AppRoutes.issueAsset,
    destructive: false,
  ),
  (
    icon: Icons.autorenew_outlined,
    title: 'Reissue',
    caption: 'Mint more of an asset',
    route: AppRoutes.reissueAsset,
    destructive: false,
  ),
  (
    icon: Icons.local_fire_department_outlined,
    title: 'Burn',
    caption: 'Destroy units for good',
    route: AppRoutes.burnAsset,
    destructive: true,
  ),
];

/// The card: the operations strip, then one entry per issued asset — or one
/// quiet line when nothing was issued here yet.
class IssuedAssetsCard extends StatelessWidget {
  const IssuedAssetsCard({
    super.key,
    required this.issued,
    required this.holdings,
    required this.onOpen,
  });

  final List<IssuedAssetEntry> issued;

  /// What the engine says the wallet holds (Liquid side).
  final List<AssetBalance> holdings;

  final OpenIssued onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final watchOnly = context.select<AppState, bool>(
      (st) => st.isActiveWalletWatchOnly,
    );
    final rule = Divider(height: 1, thickness: 1, color: s.edge);

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OperationsStrip(enabled: !watchOnly, phone: phone),
          if (watchOnly) ...[
            rule,
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kListPad,
                vertical: AppSpacing.md,
              ),
              // Why the three are off, next to them (design.md, "Flows").
              child: Text(
                'Watch-only: this wallet cannot sign an issuance, a reissue '
                'or a burn',
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
            ),
          ],
          rule,
          if (issued.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text(
                'No assets issued from this wallet yet',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(color: s.inkSecondary),
              ),
            )
          else
            for (var i = 0; i < issued.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  color: s.edge,
                  indent: kListTextInset,
                ),
              _IssuedEntry(
                entry: issued[i],
                asset: holdings
                    .where((a) => a.assetId == issued[i].assetId)
                    .firstOrNull,
                token: issued[i].tokenId == null
                    ? null
                    : holdings
                          .where((a) => a.assetId == issued[i].tokenId)
                          .firstOrNull,
                onOpen: onOpen,
              ),
            ],
        ],
      ),
    );
  }
}

// ── The operations ────────────────────────────────────────────────────────────

/// Issue, Reissue and Burn: three cells of one strip on a desktop, three
/// rows on a phone. One object, so they read as the section's controls and
/// not as three cards.
class _OperationsStrip extends StatelessWidget {
  const _OperationsStrip({required this.enabled, required this.phone});

  final bool enabled;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    if (phone) {
      return Column(
        children: [
          for (var i = 0; i < _operations.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: s.edge,
                indent: kListTextInset,
              ),
            _OperationCell(
              operation: _operations[i],
              enabled: enabled,
              chevron: true,
            ),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _operations.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, color: s.edge),
            Expanded(
              child: _OperationCell(
                operation: _operations[i],
                enabled: enabled,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OperationCell extends StatefulWidget {
  const _OperationCell({
    required this.operation,
    required this.enabled,
    this.chevron = false,
  });

  final _Operation operation;
  final bool enabled;
  final bool chevron;

  @override
  State<_OperationCell> createState() => _OperationCellState();
}

class _OperationCellState extends State<_OperationCell> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final op = widget.operation;
    final enabled = widget.enabled;
    void go() => context.go(op.route);

    final cell = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      constraints: const BoxConstraints(minHeight: AppSpacing.huge),
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.md,
      ),
      color: !enabled
          ? Colors.transparent
          : _down
          ? s.pressed
          : _hover
          ? s.hover
          : Colors.transparent,
      foregroundDecoration: _focus && enabled
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Row(
          children: [
            // Burn is loss, so its glyph is in the danger ink; the word and
            // its caption say the same.
            ListIconTile(icon: op.icon, tint: op.destructive ? s.danger : null),
            const SizedBox(width: kListGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    op.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyOf(
                      context,
                    ).copyWith(color: s.ink, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    op.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: s.inkFaint),
                  ),
                ],
              ),
            ),
            if (widget.chevron) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_outlined,
                size: AppSpacing.icon,
                color: s.inkFaint,
              ),
            ],
          ],
        ),
      ),
    );

    if (!enabled) {
      return Semantics(
        button: true,
        enabled: false,
        label: '${op.title}. ${op.caption}',
        excludeSemantics: true,
        child: cell,
      );
    }
    return Semantics(
      button: true,
      label: '${op.title}. ${op.caption}',
      excludeSemantics: true,
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
              go();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: go,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          child: cell,
        ),
      ),
    );
  }
}

// ── One issued asset ──────────────────────────────────────────────────────────

/// The asset over its reissuance token: two lines, one tap target that
/// opens the asset's detail (where its own Reissue and Burn are).
class _IssuedEntry extends StatefulWidget {
  const _IssuedEntry({
    required this.entry,
    required this.asset,
    required this.token,
    required this.onOpen,
  });

  final IssuedAssetEntry entry;

  /// The holding, or null when the wallet holds none of it right now.
  final AssetBalance? asset;
  final AssetBalance? token;
  final OpenIssued onOpen;

  @override
  State<_IssuedEntry> createState() => _IssuedEntryState();
}

class _IssuedEntryState extends State<_IssuedEntry> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;

  /// Glyph of the token line: smaller than the asset's, so the pair reads
  /// as a thing and what belongs to it.
  static const double _tokenGlyph = AppSpacing.xl;

  AssetBalance get _asset =>
      widget.asset ??
      AssetBalance(
        assetId: widget.entry.assetId,
        ticker: widget.entry.ticker,
        name: widget.entry.name,
        amount: 0,
        displayAmount: '0 ${widget.entry.ticker}',
      );

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final masked = balancesHidden(context);
    final e = widget.entry;
    final asset = _asset;
    final token = widget.token;
    final name = liquidAssetName(asset, issued: e);
    final ticker = liquidAssetTicker(asset, issued: e);
    final hasToken = token != null && token.amount > 0;
    final held = asset.amount > 0;

    final assetMeta = [
      ticker,
      if (e.domain.isNotEmpty) e.domain,
      if (!held) 'none held',
    ].join(' · ');
    // The token line states the fact a reissue depends on.
    final tokenFact = hasToken
        ? 'Held here · lets this wallet mint more $ticker'
        : e.tokenId == null
        ? 'None was issued · the supply is fixed'
        : 'Not in this wallet · reissue from the wallet that holds it';

    Widget amount(String display, {required bool strong, String? fallback}) {
      final (figure, unit) = splitAmountUnit(display);
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                masked ? kMaskedAmount : figure,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.numeric.copyWith(
                  color: strong ? s.ink : s.inkSecondary,
                ),
              ),
            ),
            if (!masked && (unit ?? fallback) != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Text(
                unit ?? fallback!,
                maxLines: 1,
                style: AppTypography.numericSmall.copyWith(color: s.inkFaint),
              ),
            ],
          ],
        ),
      );
    }

    final assetAmount = amount(
      asset.displayAmount,
      strong: held,
      fallback: ticker,
    );
    final tokenAmount = hasToken
        ? amount(token.displayAmount, strong: false)
        : null;

    // A phone has half the width: each balance goes under its name instead
    // of beside it, so neither is cut.
    final assetLine = Row(
      children: [
        AssetLogo(ticker: asset.ticker, size: kListTile),
        const SizedBox(width: kListGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyOf(
                  context,
                ).copyWith(color: s.ink, fontWeight: FontWeight.w500),
              ),
              Text(
                assetMeta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
              if (phone) ...[
                const SizedBox(height: AppSpacing.xs),
                assetAmount,
              ],
            ],
          ),
        ),
        if (!phone) ...[const SizedBox(width: AppSpacing.md), assetAmount],
        const SizedBox(width: AppSpacing.xs),
        Icon(
          Icons.chevron_right_outlined,
          size: AppSpacing.icon,
          color: s.inkFaint,
        ),
      ],
    );

    // Indented under the asset's name, behind an elbow from the asset's
    // glyph: the token belongs to the asset above it.
    final tokenLine = Row(
      crossAxisAlignment: phone
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: kListTile,
          height: _tokenGlyph,
          child: CustomPaint(painter: _Elbow(color: s.edgeStrong)),
        ),
        const SizedBox(width: kListGap),
        Opacity(
          opacity: hasToken ? 1 : 0.4,
          child: AssetLogo(
            ticker: asset.ticker,
            size: _tokenGlyph,
            isReissuanceToken: true,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reissuance token',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyOf(
                  context,
                ).copyWith(color: hasToken ? s.ink : s.inkSecondary),
              ),
              Text(
                tokenFact,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: s.inkFaint),
              ),
              if (phone && tokenAmount != null) ...[
                const SizedBox(height: AppSpacing.xs),
                tokenAmount,
              ],
            ],
          ),
        ),
        if (!phone && tokenAmount != null) ...[
          const SizedBox(width: AppSpacing.md),
          tokenAmount,
        ],
        // Keeps the token's balance in the asset's amount column.
        const SizedBox(width: AppSpacing.xs + AppSpacing.icon),
      ],
    );

    final entry = AnimatedContainer(
      duration: AppMotion.of(context, AppMotion.instant),
      curve: AppMotion.settle,
      color: _down
          ? s.pressed
          : _hover
          ? s.hover
          : Colors.transparent,
      foregroundDecoration: _focus
          ? BoxDecoration(border: Border.all(color: s.focus, width: 2))
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          assetLine,
          const SizedBox(height: AppSpacing.sm),
          tokenLine,
        ],
      ),
    );

    final open = Semantics(
      button: true,
      child: MergeSemantics(
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
                widget.onOpen(e, asset, token);
                return null;
              },
            ),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onOpen(e, asset, token),
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            child: entry,
          ),
        ),
      ),
    );
    // The public registry is Liquid testnet's; on a regtest the name lives
    // in the test server's order book instead.
    if (!e.canReregister || context.watch<AppState>().isLiquidRegtest) {
      return open;
    }

    // Issued here and not yet in the registry: other wallets show it by its
    // id until it is. The way to fix that sits with the asset it concerns.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        open,
        Padding(
          padding: const EdgeInsets.fromLTRB(
            kListTextInset,
            0,
            kListPad,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: s.warning,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Not in the asset registry yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: () => context.go(AppRoutes.assetOperations),
                style: TextButton.styleFrom(
                  foregroundColor: s.ink,
                  minimumSize: Size(
                    0,
                    phone
                        ? AppLayout.minTouchTarget
                        : AppSpacing.controlHeightSmall,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  textStyle: AppTypography.label,
                ),
                child: const Text('Register'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The elbow that ties a reissuance token to its asset: down from under the
/// asset's glyph, then across to the token's.
class _Elbow extends CustomPainter {
  const _Elbow({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final y = size.height / 2;
    const r = AppSpacing.xs;
    final path = Path()
      ..moveTo(x, -AppSpacing.sm)
      ..lineTo(x, y - r)
      ..quadraticBezierTo(x, y, x + r, y)
      ..lineTo(size.width + AppSpacing.sm, y);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_Elbow old) => old.color != color;
}
