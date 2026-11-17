import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../services/issued_asset_store.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class AssetOperationsScreen extends StatefulWidget {
  const AssetOperationsScreen({super.key});

  @override
  State<AssetOperationsScreen> createState() => _AssetOperationsScreenState();
}

class _AssetOperationsScreenState extends State<AssetOperationsScreen> {
  final _bridge = walletBridge;

  /// Issued assets whose registry submission is still pending and which carry
  /// enough persisted contract data (name/ticker/precision/domain) to retry.
  List<IssuedAssetEntry> _unregistered = [];

  /// Asset ID currently being submitted to the registry, if any.
  String? _registering;

  @override
  void initState() {
    super.initState();
    _loadUnregistered();
  }

  Future<void> _loadUnregistered() async {
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    final issued = await IssuedAssetStore.instance.getIssuedAssets(walletId);
    if (mounted) {
      setState(() {
        _unregistered = issued.values.where((e) => e.canReregister).toList();
      });
    }
  }

  Future<void> _onRegister(IssuedAssetEntry entry) async {
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    setState(() => _registering = entry.assetId);
    bool ok = false;
    String? failure;
    try {
      // The FFI rebuilds the contract from these fields, validates it against
      // the on-chain issuance, and re-submits it to the registry.
      ok = (await _bridge.reregisterAsset(
        walletId: walletId,
        assetId: entry.assetId,
        name: entry.name,
        ticker: entry.ticker,
        precision: entry.precision,
        domain: entry.domain,
      )).registered;
    } catch (e) {
      failure = e.toString();
    }
    if (ok) {
      await IssuedAssetStore.instance.markRegistered(walletId, entry.assetId);
    }
    if (!mounted) return;
    setState(() {
      _registering = null;
      if (ok) {
        _unregistered.removeWhere((e) => e.assetId == entry.assetId);
      }
    });
    // The snackbar takes the theme's neutral surface: the words carry the
    // outcome, not a green or red slab.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${entry.ticker} registered'
              : failure != null
              ? 'Registration error: $failure'
              : 'Registration failed — ensure the domain proof file on '
                    '${entry.domain} is live, then try again',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.formMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
              children: [
                const PageHeader(title: 'Asset operations'),
                const ListSectionLabel(label: 'Manage assets'),
                const AssetOpsRows(),
                // The public registry is Liquid testnet's: a regtest asset
                // can never be in it (its name lives in the order book's).
                if (_unregistered.isNotEmpty &&
                    !context.watch<AppState>().isLiquidRegtest) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const ListSectionLabel(label: 'Asset registry'),
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'Assets issued from this wallet that are not yet in the '
                      'Liquid asset registry. Make sure the domain proof file '
                      'is live before registering.',
                      style: AppTypography.caption.copyWith(
                        color: s.inkSecondary,
                      ),
                    ),
                  ),
                  ListCard(
                    children: [
                      for (final entry in _unregistered)
                        _RegistryRow(
                          entry: entry,
                          busy: _registering == entry.assetId,
                          // Serialize submissions — one at a time.
                          onRegister: _registering == null
                              ? () => _onRegister(entry)
                              : null,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The three Liquid asset operations as one card of rows.
///
/// Shared by both entry points (this screen and the Liquid page on a phone)
/// so Issue/Reissue/Burn is the same object wherever it is reached. The
/// glyphs are in the secondary ink; Burn's is in the danger ink because it
/// destroys supply.
class AssetOpsRows extends StatelessWidget {
  const AssetOpsRows({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return ListCard(
      children: [
        ListRow(
          icon: Icons.add,
          title: 'Issue asset',
          subtitle: 'Create a new Liquid asset',
          chevron: true,
          onTap: () => context.go(AppRoutes.issueAsset),
        ),
        ListRow(
          icon: Icons.autorenew_outlined,
          title: 'Reissue',
          subtitle: 'Mint more of an asset you control',
          chevron: true,
          onTap: () => context.go(AppRoutes.reissueAsset),
        ),
        ListRow(
          icon: Icons.local_fire_department_outlined,
          tint: s.danger,
          title: 'Burn',
          subtitle: 'Destroy supply — irreversible',
          chevron: true,
          onTap: () => context.go(AppRoutes.burnAsset),
        ),
      ],
    );
  }
}

/// One asset awaiting registration: its ticker and name, its domain (what
/// decides whether registration succeeds), and the action.
class _RegistryRow extends StatelessWidget {
  const _RegistryRow({
    required this.entry,
    required this.busy,
    required this.onRegister,
  });

  final IssuedAssetEntry entry;
  final bool busy;
  final VoidCallback? onRegister;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final shortId = entry.assetId.length > 16
        ? '${entry.assetId.substring(0, 16)}…'
        : entry.assetId;

    final identity = Row(
      children: [
        const ListIconTile(icon: Icons.public_outlined),
        const SizedBox(width: kListGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.ticker} — ${entry.name}',
                style: AppTypography.bodyOf(
                  context,
                ).copyWith(color: s.ink, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                // On a phone the domain alone: it decides whether the
                // registration will succeed, so the asset id gives up its half
                // of the line.
                phone ? entry.domain : '$shortId · ${entry.domain}',
                style: AppTypography.caption.copyWith(color: s.inkSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );

    final action = SecondaryButton(
      label: phone ? 'Register' : 'Register in asset registry',
      icon: Icons.public_outlined,
      isFullWidth: phone,
      isLoading: busy,
      onPressed: onRegister,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kListPad,
        vertical: AppSpacing.md,
      ),
      child: phone
          // Stacked: the label plus its glyph wants ~200 dp of a ~350 dp row.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: AppSpacing.md),
                action,
              ],
            )
          : Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: AppSpacing.lg),
                action,
              ],
            ),
    );
  }
}
