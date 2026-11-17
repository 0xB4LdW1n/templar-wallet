import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../features/send/models/tx_preview.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'buttons.dart';
import 'code_box.dart';
import 'app_dialog.dart';
import 'live_edge.dart';
import 'seal_mark.dart';
import 'tx_recap.dart';

/// The moment a transaction is signed and broadcast: the seal stamps, and
/// the recap of what was sent sits above the txid (copy + explorer).
/// Shared by the software, hardware, and air-gap send paths.
///
/// The seal is the right mark here and only here: this dialog opens after a
/// signature has landed. A multisig send still collecting signatures never
/// reaches it — that outcome is the co-signer hand-off, with its own tally.
///
/// [onViewInActivity] is where "View in activity" goes: the caller leaves
/// for Activity with this transaction's detail open. Null hides the button.
Future<void> showTxSuccessDialog(
  BuildContext context, {
  required String txid,
  required TxPreview preview,
  required String ticker,
  VoidCallback? onViewInActivity,
}) {
  // Dialog on desktop, bottom sheet on a phone. Not dismissible from
  // outside: the txid is the one thing the user must not lose by accident.
  return showAppDialog<void>(
    context,
    barrierDismissible: false,
    builder: (_) => _TxSuccessDialog(
      txid: txid,
      preview: preview,
      ticker: ticker,
      onViewInActivity: onViewInActivity,
    ),
  );
}

class _TxSuccessDialog extends StatelessWidget {
  const _TxSuccessDialog({
    required this.txid,
    required this.preview,
    required this.ticker,
    this.onViewInActivity,
  });

  final String txid;
  final TxPreview preview;
  final String ticker;
  final VoidCallback? onViewInActivity;

  bool get _isLiquid => preview.chain == 'liquid';

  Future<void> _openExplorer(BuildContext context, String base) async {
    final trimmed = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final uri = Uri.parse('$trimmed/tx/$txid');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final app = maybeAppState(context);
    // Null on a regtest (no public explorer knows it): no link at all.
    final explorerBase =
        _isLiquid ? app?.liquidExplorerBase : app?.btcExplorerBase;
    final network = _isLiquid
        ? 'Liquid ${app?.liquidNetworkName ?? 'testnet'}'
        : 'Bitcoin ${app?.bitcoinNetworkName ?? 'testnet'}';

    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Stamps itself on mount.
        const Center(
          child: SealMark(
            stamped: true,
            size: 48,
            semanticLabel: 'Signed and sent',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Sent',
          textAlign: TextAlign.center,
          style: AppTypography.sectionTitle.copyWith(color: s.ink),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Broadcast to the $network',
          textAlign: TextAlign.center,
          style: AppTypography.bodyOf(context).copyWith(color: s.inkSecondary),
        ),
        SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
        TxRecapPanel(preview: preview, ticker: ticker),
        const SizedBox(height: AppSpacing.md),
        CodeBox(value: txid, label: 'TxID'),
      ],
    );

    final explorer = explorerBase == null
        ? null
        : GhostButton(
            label: 'View in explorer',
            icon: Icons.open_in_new_outlined,
            isFullWidth: phone,
            onPressed: () => _openExplorer(context, explorerBase),
          );
    final done = PrimaryButton(
      label: 'Done',
      isFullWidth: phone,
      onPressed: () => Navigator.of(context).pop(),
    );
    // Beside the explorer: the same transaction in this wallet's own
    // record, its detail open.
    final toActivity = onViewInActivity;
    final activity = toActivity == null
        ? null
        : SecondaryButton(
            label: 'View in activity',
            icon: Icons.history_outlined,
            isFullWidth: phone,
            onPressed: () {
              Navigator.of(context).pop();
              toActivity();
            },
          );

    final actions = phone
        ? <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                done,
                if (activity != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  activity,
                ],
                if (explorer != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  explorer,
                ],
              ],
            ),
          ]
        : <Widget>[?explorer, ?activity, done];

    return AppDialog(
      // It landed: the dialog's edge draws itself closed in the success
      // green as the seal stamps (design.md, "Motion").
      edge: LiveEdgeMode.done,
      edgeColor: s.success,
      // The sheet scrolls its own content; the desktop dialog needs a width
      // and a scroll view of its own.
      content: phone
          ? body
          : SizedBox(width: 520, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}
