import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../app/app_state.dart';
import '../../app/routes.dart';
import '../../bridge/bridge_provider.dart';
import '../../features/dashboard/models/dashboard_data.dart';
import '../../services/asset_registry_service.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/page_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'form_parts.dart';

class BurnScreen extends StatefulWidget {
  const BurnScreen({super.key});

  @override
  State<BurnScreen> createState() => _BurnScreenState();
}

class _BurnScreenState extends State<BurnScreen> {
  final _bridge = walletBridge;

  List<AssetBalance> _liquidAssets = [];
  AssetBalance? _selectedAsset;
  bool _loadingAssets = true;

  final _amountController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _submitting = false;
  String? _error;
  String? _resultTxid;

  // Confirmation uses the display ticker: on-chain tickers can be raw hex ids,
  // which the user only ever sees resolved through the registry.
  String get _confirmTicker => _selectedAsset == null
      ? ''
      : AssetRegistryService.instance.displayTicker(_selectedAsset!);

  bool get _confirmed =>
      _confirmTicker.isNotEmpty &&
      _confirmController.text.trim() == _confirmTicker;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _confirmController.addListener(() => setState(() {}));
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
    try {
      final data = await _bridge.getWalletSummary(walletId);
      final liquid = data.assets
          .where((a) => a.ticker != 'BTC' && a.ticker != 'LBTC')
          .toList();
      if (mounted) {
        final wanted = _requestedAssetId();
        setState(() {
          _liquidAssets = liquid;
          _selectedAsset =
              liquid.where((a) => a.assetId == wanted).firstOrNull ??
              (liquid.isNotEmpty ? liquid.first : null);
          _loadingAssets = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingAssets = false);
    }
  }

  /// The asset the caller asked for (`?asset=<id>`, from a row or an asset's
  /// detail), or null. Read after the first frame: the router's state is an
  /// inherited lookup.
  String? _requestedAssetId() {
    try {
      return GoRouterState.of(context).uri.queryParameters['asset'];
    } catch (_) {
      return null; // Not under the router (a widget test).
    }
  }

  Future<void> _onBurn() async {
    final asset = _selectedAsset;
    if (asset == null) return;
    if (!_confirmed) return;
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than 0');
      return;
    }
    if (amount > asset.amount) {
      setState(
        () => _error =
            'Amount exceeds current holdings (${asset.amount} base units)',
      );
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final walletId = context.read<AppState>().activeWalletId ?? 'wallet-1';
      final txid = await _bridge.burnAsset(
        walletId: walletId,
        assetId: asset.assetId,
        amountSats: amount,
      );
      if (mounted) {
        setState(() {
          _resultTxid = txid;
          _submitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppSpacing.formMaxWidth,
            ),
            child: _resultTxid != null ? _buildResult() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _backToAssets() => GhostButton(
    label: 'Back to assets',
    icon: Icons.arrow_back,
    onPressed: () => context.go(AppRoutes.liquid),
  );

  // Burn is loss, so the screen's action is the danger button and nothing on
  // it is filled with the accent.
  Widget _buildForm() {
    final reg = AssetRegistryService.instance;
    final asset = _selectedAsset;
    return ListView(
      padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
      children: [
        PageHeader(title: 'Burn asset', actions: [_backToAssets()]),
        const DangerBanner(
          title: 'This action is irreversible',
          message:
              'Burned tokens are permanently destroyed. The total supply will '
              'be permanently reduced. This cannot be undone.',
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_loadingAssets)
          const Center(child: CircularProgressIndicator())
        else ...[
          FieldBlock(
            label: 'Asset',
            child: _liquidAssets.isEmpty
                ? Text(
                    'No burnable assets found',
                    style: AppTypography.body.copyWith(
                      color: AppScheme.of(context).inkSecondary,
                    ),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: asset?.assetId,
                    isExpanded: true,
                    items: _liquidAssets
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.assetId,
                            child: Text(
                              '${reg.displayTicker(a)} — ${reg.displayName(a)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() {
                      _selectedAsset = _liquidAssets.firstWhere(
                        (a) => a.assetId == v,
                      );
                      _confirmController.clear();
                    }),
                    decoration: const InputDecoration(hintText: 'Select asset'),
                  ),
          ),
          if (asset != null) ...[
            const SizedBox(height: AppSpacing.lg),
            SummaryCard(
              rows: [
                (
                  label: 'Current holdings',
                  value: asset.displayAmount,
                  isMono: false,
                ),
                (label: 'Base units', value: '${asset.amount}', isMono: true),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          FieldBlock(
            label: 'Amount to burn',
            help: 'In base units',
            trailing: asset == null
                ? null
                : GhostButton(
                    label: 'Burn all',
                    onPressed: () => setState(
                      () => _amountController.text = '${asset.amount}',
                    ),
                  ),
            child: TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: AppTypography.numeric,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(hintText: '0'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FieldBlock(
            label: 'Type "$_confirmTicker" to confirm',
            child: TextField(
              controller: _confirmController,
              decoration: InputDecoration(hintText: _confirmTicker),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            DangerBanner(message: _error!),
          ],
          const SizedBox(height: AppSpacing.xl),
          DangerButton(
            label: _submitting ? 'Broadcasting…' : 'Burn',
            icon: Icons.local_fire_department_outlined,
            isFullWidth: true,
            onPressed: _confirmed && _liquidAssets.isNotEmpty && !_submitting
                ? _onBurn
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildResult() {
    return ListView(
      padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
      children: [
        PageHeader(title: 'Burned', actions: [_backToAssets()]),
        const InfoBanner(message: 'Burn transaction broadcast on-chain'),
        const SizedBox(height: AppSpacing.xl),
        CodeBox(label: 'TxID', value: _resultTxid!),
        const SizedBox(height: AppSpacing.xl),
        PrimaryButton(
          label: 'Done',
          isFullWidth: true,
          onPressed: () => context.go(AppRoutes.liquid),
        ),
      ],
    );
  }
}
