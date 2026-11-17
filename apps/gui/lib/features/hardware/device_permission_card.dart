// Linux: one-click fix for "the OS won't let us open the device".
//
// This is the counterpart of [HwiInstallCard]. HWI being installed is only
// half of what a Linux user needs — without udev rules the toolkit runs fine
// and simply reports no devices, which is indistinguishable from a broken
// cable unless the app says so.

import 'package:flutter/material.dart';

import '../../services/udev_installer.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class DevicePermissionCard extends StatefulWidget {
  const DevicePermissionCard({required this.onFixed, this.detail, super.key});

  /// Called after the rules were installed, so the host can rescan.
  final VoidCallback onFixed;

  /// The backend's own words about the failure, when this card is shown in
  /// response to a specific error rather than a proactive check.
  final String? detail;

  @override
  State<DevicePermissionCard> createState() => _DevicePermissionCardState();
}

class _DevicePermissionCardState extends State<DevicePermissionCard> {
  bool _running = false;
  String? _error;
  String? _success;

  Future<void> _fix() async {
    setState(() {
      _running = true;
      _error = null;
      _success = null;
    });
    final result = await UdevInstaller.install();
    if (!mounted) return;
    setState(() {
      _running = false;
      if (result.ok) {
        _success = result.message;
      } else {
        _error = result.message;
      }
    });
    if (result.ok) widget.onFixed();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final detail = widget.detail;
    final success = _success;
    final error = _error;

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
                Icons.usb_off_outlined,
                color: s.warning,
                size: AppSpacing.icon,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Device permissions needed',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'On Linux, a normal user cannot talk to a hardware wallet until '
            'udev rules grant access to it. Templar ships the official rules '
            'from the HWI project and can install them for you — you will be '
            'asked for your password once.',
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              detail,
              style: AppTypography.monoSmall.copyWith(color: s.inkFaint),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (_running) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusXs),
              child: const LinearProgressIndicator(minHeight: AppSpacing.xs),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Waiting for authentication…',
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ] else
            SecondaryButton(
              label: 'Fix device permissions',
              icon: Icons.admin_panel_settings_outlined,
              onPressed: _fix,
            ),
          if (success != null) ...[
            const SizedBox(height: AppSpacing.md),
            _StatusLine(color: s.success, text: success),
          ],
          if (error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not install the rules — the manual steps are below',
              style: AppTypography.caption.copyWith(color: s.danger),
            ),
            const SizedBox(height: AppSpacing.xs),
            // Selectable: the fallback is a block of shell commands the user
            // has to copy into a terminal, so it must not be plain Text.
            _TechnicalDetail(detail: error, label: 'manual steps'),
          ],
        ],
      ),
    );
  }
}

/// A status: a 6 px dot and the words beside it.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 20,
          child: Center(
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: AppTypography.caption.copyWith(color: s.ink),
          ),
        ),
      ],
    );
  }
}

/// The raw words behind a failure, folded away until asked for: selectable
/// `mono` in a well.
class _TechnicalDetail extends StatefulWidget {
  const _TechnicalDetail({required this.detail, this.label = 'details'});
  final String detail;
  final String label;

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
          label: _open ? 'Hide ${widget.label}' : 'Show ${widget.label}',
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
