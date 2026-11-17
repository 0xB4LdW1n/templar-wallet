// Shown *below* the device list on platforms where some device families are out
// of reach — today only macOS, where the App Sandbox blocks the HWI helper
// process that Trezor, Coldcard, KeepKey and BitBox still need. Ledger and Jade
// are driven in-process and pair normally, so this is a note, not a wall.
//
// It used to carry its own copy of the connected-device list, which meant one
// device could appear twice on the screen: once here, once in the scan results.
// The device rows now live in a single place ([DeviceListSection]) and carry
// their own "not usable here" state, so this card is left with the one job it
// is good at — explaining why, and what to do instead.

import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'hw_platform.dart';

class UsbUnsupportedCard extends StatelessWidget {
  const UsbUnsupportedCard({required this.onUseAirgap, super.key});

  /// Switch the user to the air-gap flow, which does work here.
  final VoidCallback onUseAirgap;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);

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
                Icons.info_outlined,
                color: s.inkSecondary,
                size: AppSpacing.icon,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Some devices cannot be used over USB here',
                  style: AppTypography.sectionTitle.copyWith(color: s.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            usbPartialSupportReason,
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'What works today',
            style: AppTypography.eyebrow.copyWith(color: s.inkFaint),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '$jadeLiquidStillWorks\n\n$usbUnsupportedAlternative',
            style: AppTypography.body.copyWith(color: s.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          SecondaryButton(
            label: 'Set up as air-gap instead',
            icon: Icons.qr_code_2_outlined,
            onPressed: onUseAirgap,
          ),
        ],
      ),
    );
  }
}
