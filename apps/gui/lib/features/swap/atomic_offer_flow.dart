import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../dashboard/models/dashboard_data.dart';
import 'models/swap_offer.dart';

Future<AtomicSwap?> openAtomicOfferFlow(BuildContext context) {
  final walletId = context.read<AppState>().activeWalletId;
  final assets =
      context
          .read<AppState>()
          .cachedDashboard
          ?.assets
          .where((asset) => asset.ticker != 'BTC')
          .toList() ??
      const <AssetBalance>[];
  if (walletId == null) return Future.value(null);
  return showAppDialog<AtomicSwap>(
    context,
    builder: (_) => _AtomicOfferDialog(walletId: walletId, assets: assets),
  );
}

class _AtomicOfferDialog extends StatefulWidget {
  const _AtomicOfferDialog({required this.walletId, required this.assets});
  final String walletId;
  final List<AssetBalance> assets;

  @override
  State<_AtomicOfferDialog> createState() => _AtomicOfferDialogState();
}

class _AtomicOfferDialogState extends State<_AtomicOfferDialog> {
  final _btc = TextEditingController(text: '0.001');
  final _liquid = TextEditingController();
  String _direction = 'btc-to-liquid';
  AssetBalance? _asset;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.assets.isNotEmpty) _asset = widget.assets.first;
  }

  @override
  void dispose() {
    _btc.dispose();
    _liquid.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final asset = _asset;
    if (asset == null) {
      setState(() => _error = 'Sync a Liquid-enabled wallet first.');
      return;
    }
    final precision = _precision(asset);
    final btc = _baseUnits(_btc.text, 8);
    final liquid = _baseUnits(_liquid.text, precision);
    if (btc == null || liquid == null || btc < 1000 || liquid < 1000) {
      setState(
        () => _error = 'Both amounts must be at least 1,000 base units.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final swap = await walletBridge.atomicSwapCreate(
        walletId: widget.walletId,
        direction: _direction,
        btcAmountSats: btc,
        liquidAssetId: asset.assetId,
        liquidTicker: asset.ticker,
        liquidName: asset.name,
        liquidPrecision: precision,
        liquidAmountSats: liquid,
        note: 'Created in Templar Wallet',
      );
      if (mounted) {
        Navigator.of(context).pop(swap);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('New cross-chain offer'),
    content: SizedBox(
      width: 500,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WarningBanner(
              title: 'Testnet HTLC v1',
              message:
                  'Real funds move on Bitcoin testnet and Liquid testnet. The '
                  'Liquid contract output exposes its asset and amount; wallet '
                  'keys never leave this device.',
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<String>(
              initialValue: _direction,
              decoration: const InputDecoration(labelText: 'You offer'),
              items: const [
                DropdownMenuItem(
                  value: 'btc-to-liquid',
                  child: Text('BTC · receive Liquid asset'),
                ),
                DropdownMenuItem(
                  value: 'liquid-to-btc',
                  child: Text('Liquid asset · receive BTC'),
                ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _direction = value!),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _btc,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'BTC amount',
                suffixText: 'tBTC',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<AssetBalance>(
              initialValue: _asset,
              decoration: const InputDecoration(labelText: 'Liquid asset'),
              items: [
                for (final asset in widget.assets)
                  DropdownMenuItem(
                    value: asset,
                    child: Text('${asset.ticker} · ${asset.name}'),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _asset = value),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _liquid,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Liquid amount',
                suffixText: _asset?.ticker ?? 'asset',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: AppTypography.caption.copyWith(color: Colors.redAccent),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      GhostButton(
        label: 'Cancel',
        onPressed: _busy ? null : () => Navigator.of(context).pop(),
      ),
      PrimaryButton(
        label: _busy ? 'Publishing…' : 'Publish offer',
        icon: Icons.lock_clock_outlined,
        onPressed: _busy ? null : _create,
      ),
    ],
  );
}

int _precision(AssetBalance asset) {
  final match = RegExp(r'\.(\d+)').firstMatch(asset.displayAmount);
  return match?.group(1)?.length.clamp(0, 8) ?? 8;
}

int? _baseUnits(String raw, int precision) {
  final value = raw.trim();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) return null;
  final parts = value.split('.');
  if (parts.length == 2 && parts[1].length > precision) return null;
  final fraction = parts.length == 2
      ? parts[1].padRight(precision, '0')
      : ''.padRight(precision, '0');
  return int.tryParse('${parts[0]}$fraction');
}
