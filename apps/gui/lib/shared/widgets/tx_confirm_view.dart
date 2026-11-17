import 'package:flutter/material.dart';

import '../../app/app_state.dart';

import '../../features/send/models/tx_preview.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'buttons.dart';
import 'app_dialog.dart';
import 'hybrid_kit.dart';
import 'tx_recap.dart';

/// Last stop before anything is signed: a compact recap of the transaction —
/// every recipient, the change, the fee, the total — and how it will be
/// signed.
///
/// Returns true when the user confirms. The caller then runs its signing path
/// (software key behind the password gate, hardware device, or air-gap QR)
/// and shows the success recap.
Future<bool> showTxConfirmDialog(
  BuildContext context, {
  required TxPreview preview,
  required String ticker,
  required String signLabel,
  required String signHint,
}) async {
  // Dialog on desktop, bottom sheet on a phone; neither dismisses on an
  // outside tap — leaving a confirmation is an explicit Back.
  final ok = await showAppDialog<bool>(
    context,
    barrierDismissible: false,
    builder: (_) => _TxConfirmDialog(
      preview: preview,
      ticker: ticker,
      signLabel: signLabel,
      signHint: signHint,
    ),
  );
  return ok ?? false;
}

class _TxConfirmDialog extends StatelessWidget {
  const _TxConfirmDialog({
    required this.preview,
    required this.ticker,
    required this.signLabel,
    required this.signHint,
  });

  final TxPreview preview;
  final String ticker;

  /// Primary button text — differs per signing path ("Sign and send",
  /// "Sign on device", "Export PSBT").
  final String signLabel;

  /// One line telling the user what happens when they confirm.
  final String signHint;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final isLiquid = preview.chain == 'liquid';
    final app = maybeAppState(context);
    final phone = AppLayout.isPhone(context);

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Nothing has been signed yet. A sent transaction cannot be recalled.',
          style: AppTypography.bodyOf(context).copyWith(color: s.inkSecondary),
        ),
        SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
        TxRecapPanel(preview: preview, ticker: ticker),
        const SizedBox(height: AppSpacing.lg),
        // The network is a fact of the transaction: its name with the
        // chain's dot, and what confirming does.
        Align(
          alignment: Alignment.centerLeft,
          child: TagChip(
            label: isLiquid
                ? 'Liquid ${app?.liquidNetworkName ?? 'testnet'}'
                : 'Bitcoin ${app?.bitcoinNetworkName ?? 'testnet'}',
            color: isLiquid ? s.liquid : s.bitcoin,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          signHint,
          style: AppTypography.caption.copyWith(color: s.inkSecondary),
        ),
      ],
    );

    final actions = phone
        ? <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                PrimaryButton(
                  label: signLabel,
                  isFullWidth: true,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: AppSpacing.sm),
                GhostButton(
                  label: 'Back',
                  isFullWidth: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ]
        : <Widget>[
            GhostButton(
              label: 'Back',
              onPressed: () => Navigator.of(context).pop(false),
            ),
            PrimaryButton(
              label: signLabel,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ];

    return AppDialog(
      title: const Text('Confirm this transaction'),
      // The sheet scrolls its own content; the desktop dialog needs a width
      // and a scroll view of its own.
      content: phone
          ? body
          : SizedBox(width: 520, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}
