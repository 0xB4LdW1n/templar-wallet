// The detail of a loan, a swap or a peg: the payment detail's anatomy
// (history_screen.dart) — glyph row, figure, key/value facts with
// dividers, every transaction id in a code box with its explorer link, and
// at the foot the way to the page where the thing is managed. Read-only:
// nothing here signs or moves anything.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/asset_logo.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'activity_rows.dart';
import 'models/activity_entry.dart';
import 'models/transaction.dart';

/// Where an entry is managed, and the button that goes there.
({String route, String label}) activityManageTarget(ActivityEntry e) =>
    switch (e) {
      LoanEntry(:final siteKey?, :final loan) => (
        route: AppRoutes.loanDetailLocation(siteKey, loan.id),
        label: 'Open loan',
      ),
      LoanEntry() ||
      LoanSignatureEntry() => (route: AppRoutes.loans, label: 'Open Loans'),
      LiquidexSwapEntry() ||
      AtomicSwapEntry() => (route: AppRoutes.swap, label: 'Open LiquiDEX'),
      PegEntry() => (route: AppRoutes.peg, label: 'Open Peg'),
      PaymentEntry() => (route: AppRoutes.history, label: 'Activity'),
    };

/// The line beside the glyph: who reported it.
String activitySourceLabel(ActivityEntry e) => switch (e) {
  LoanEntry(:final siteName) =>
    siteName.isEmpty
        ? 'Templar Protocol'
        : siteName.contains('Templar Protocol')
        ? siteName
        : 'Templar Protocol · $siteName',
  LoanSignatureEntry() => 'Templar Protocol',
  LiquidexSwapEntry() => 'LiquiDEX',
  AtomicSwapEntry() => 'Bitcoin ↔ Liquid HTLC',
  PegEntry(:final order) =>
    order.simulated ? 'Peg provider · simulated' : 'Peg provider',
  PaymentEntry(:final tx) => tx.chain == TxChain.bitcoin ? 'Bitcoin' : 'Liquid',
};

/// `https://explorer/tx/<txid>` for the chain.
String activityExplorerUrl(String base, String txid) {
  final trimmed = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return '$trimmed/tx/$txid';
}

/// Opens [url] in the browser; when nothing can take it, copies it and says
/// so, so the button never reads as dead.
Future<void> openActivityExplorer(BuildContext context, String url) async {
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
  await Clipboard.setData(ClipboardData(text: url));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    const SnackBar(
      content: Text("Couldn't open a browser — explorer link copied"),
    ),
  );
}

class ActivityEntryDetail extends StatelessWidget {
  const ActivityEntryDetail({
    super.key,
    required this.entry,
    required this.useSats,
    required this.btcExplorerUrl,
    required this.liquidExplorerUrl,
    required this.linked,
    required this.onManage,
    this.onSpeedUp,
  });

  final ActivityEntry entry;
  final bool useSats;

  /// Null on a regtest (no public explorer knows it): no link at all.
  final String? btcExplorerUrl;
  final String? liquidExplorerUrl;

  /// On-chain transactions folded into this entry, by txid.
  final Map<String, Transaction> linked;

  /// Leaves the dialog for the page that manages the entry.
  final VoidCallback onManage;

  /// The fee-bump flow for a folded pending Bitcoin transaction; null when
  /// there is none.
  final VoidCallback? onSpeedUp;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppSpacing.isPhone(context);
    final e = entry;
    final primary = e.primary;
    final secondary = e.secondary;
    final target = activityManageTarget(e);

    Widget leg(ActivityAmount a, String text, TextStyle style) => Row(
      children: [
        AssetLogo(ticker: a.ticker, size: AppSpacing.xl),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Amount(text, maxLines: 1, style: style),
          ),
        ),
      ],
    );

    final figure = <Widget>[
      if (primary != null)
        Row(
          children: [
            Flexible(
              child: leg(
                primary,
                primary.format(useSats: useSats),
                AppTypography.numericLargeOf(
                  context,
                ).copyWith(color: e.isPending ? s.inkSecondary : s.ink),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            const PrivacyToggle(),
          ],
        ),
      if (secondary != null) ...[
        const SizedBox(height: AppSpacing.xs),
        leg(
          secondary,
          activitySecondaryText(e, secondary.format(useSats: useSats)),
          AppTypography.numeric.copyWith(color: s.inkSecondary),
        ),
      ],
    ];

    final txBlocks = <Widget>[
      for (final ref in e.txRefs) ...[
        const SizedBox(height: AppSpacing.lg),
        CodeBox(value: ref.txid, label: ref.label),
        _TxFoot(
          tx: linked[ref.txid],
          onExplorer: switch (ref.chain == TxChain.liquid
              ? liquidExplorerUrl
              : btcExplorerUrl) {
            final base? => () => openActivityExplorer(
              context,
              activityExplorerUrl(base, ref.txid),
            ),
            null => null,
          },
        ),
      ],
    ];

    final content = SizedBox(
      width: phone ? null : 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              ActivityKindGlyph(kind: e.kind),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  activitySourceLabel(e),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(color: s.inkSecondary),
                ),
              ),
            ],
          ),
          if (figure.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ...figure,
          ],
          const SizedBox(height: AppSpacing.lg),
          for (final f in e.details)
            KvRow(
              label: f.label,
              value: f.amount != null
                  ? maskAmount(context, f.amount!.format(useSats: useSats))
                  : f.text ?? '',
              divider: true,
            ),
          ...txBlocks,
        ],
      ),
    );

    return AppDialog(
      title: Text(e.title),
      scrollable: true,
      content: content,
      actions: [
        if (onSpeedUp != null)
          SecondaryButton(
            label: 'Speed up',
            icon: Icons.bolt_outlined,
            onPressed: onSpeedUp,
          ),
        SecondaryButton(label: target.label, onPressed: onManage),
        SecondaryButton(
          label: 'Close',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Under a txid's box: what the wallet's own history says about it (when it
/// was folded in from there) and the explorer link.
class _TxFoot extends StatelessWidget {
  const _TxFoot({required this.tx, required this.onExplorer});
  final Transaction? tx;
  final VoidCallback? onExplorer;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final t = tx;
    final explore = onExplorer;
    final facts = t == null
        ? null
        : [
            t.directionLabel,
            t.isConfirmed
                ? '${t.confirmations} confirmation${t.confirmations == 1 ? '' : 's'}'
                : 'Unconfirmed',
            if (t.fee != null) 'fee ${t.fee}',
          ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: facts == null
                ? const SizedBox.shrink()
                : Text(
                    facts,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(color: s.inkFaint),
                  ),
          ),
          if (explore != null)
            GhostButton(
              label: 'View in explorer',
              icon: Icons.open_in_new_outlined,
              onPressed: explore,
            ),
        ],
      ),
    );
  }
}
