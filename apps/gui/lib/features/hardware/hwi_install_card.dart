import 'package:flutter/material.dart';

import '../../bridge/bridge_provider.dart';
import '../../services/hwi_installer.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Offer to download and install the HWI toolkit when no `hwi` binary is
/// available. One flow for every OS: the official standalone binary from
/// bitcoin-core/HWI releases lands in the app's data directory and is
/// activated in the running backend — no restart, no Python.
class HwiInstallCard extends StatefulWidget {
  const HwiInstallCard({required this.onInstalled, super.key});

  /// Called after the binary is installed and activated.
  final VoidCallback onInstalled;

  @override
  State<HwiInstallCard> createState() => _HwiInstallCardState();
}

class _HwiInstallCardState extends State<HwiInstallCard> {
  final _installer = HwiInstaller();

  HwiReleaseInfo? _release;
  bool _installing = false;
  HwiInstallPhase? _phase;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final release = await _installer.resolveLatest();
      if (mounted) {
        setState(() {
          _release = release;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _error = null;
      _progress = 0;
    });
    try {
      await _installer.install(
        bridge: walletBridge,
        release: _release,
        onProgress: (phase, progress) {
          if (mounted) {
            setState(() {
              _phase = phase;
              _progress = progress;
            });
          }
        },
      );
      if (mounted) {
        setState(() => _installing = false);
        widget.onInstalled();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _installing = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  String get _phaseLabel => switch (_phase) {
    HwiInstallPhase.resolving => 'Finding the latest release…',
    HwiInstallPhase.downloading => 'Downloading… ${(_progress * 100).round()}%',
    HwiInstallPhase.verifying => 'Verifying checksum…',
    HwiInstallPhase.extracting => 'Extracting…',
    HwiInstallPhase.activating => 'Activating…',
    null => '',
  };

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final release = _release;
    final error = _error;

    // A quiet card with one action: the status icon says what kind of notice
    // this is, the surface stays the card's.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.download_outlined,
                color: s.warning,
                size: AppSpacing.icon,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'HWI toolkit required',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'USB hardware wallets are driven by HWI (Hardware Wallet '
            'Interface, a Bitcoin Core project). It is not installed yet. '
            'Templar can download the official signed build and set it up '
            'automatically.',
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_installing) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              child: LinearProgressIndicator(
                minHeight: AppSpacing.xs,
                value: _phase == HwiInstallPhase.downloading ? _progress : null,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _phaseLabel,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ] else
            SecondaryButton(
              label: release == null
                  ? 'Install HWI'
                  : 'Install HWI ${release.version} (${release.sizeDisplay})',
              icon: Icons.download_outlined,
              onPressed: _install,
            ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Install failed',
              style: AppTypography.caption.copyWith(color: s.danger),
            ),
            const SizedBox(height: AppSpacing.xs),
            _TechnicalDetail(detail: error),
          ],
        ],
      ),
    );
  }
}

/// The raw words behind a failure, folded away until asked for: selectable
/// `mono` in a well, because it is what goes into a bug report.
class _TechnicalDetail extends StatefulWidget {
  const _TechnicalDetail({required this.detail});
  final String detail;

  @override
  State<_TechnicalDetail> createState() => _TechnicalDetailState();
}

class _TechnicalDetailState extends State<_TechnicalDetail> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GhostButton(
          label: _open ? 'Hide details' : 'Show details',
          icon: _open ? Icons.expand_less_outlined : Icons.expand_more_outlined,
          onPressed: () => setState(() => _open = !_open),
        ),
        if (_open) ...[
          const SizedBox(height: AppSpacing.xs),
          DataWell(
            child: SelectableText(
              widget.detail,
              style: AppTypography.mono.copyWith(color: s.ink),
            ),
          ),
        ],
      ],
    );
  }
}
