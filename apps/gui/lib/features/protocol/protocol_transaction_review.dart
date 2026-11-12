import 'package:flutter/material.dart';

import '../../shared/widgets/banners.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../psbt/models/pset_inspection.dart';
import 'models/protocol_link.dart';
import 'models/protocol_review_agreement.dart';
import 'protocol_copy.dart';

/// Human transaction review. The wallet's PSET inspection is authoritative;
/// the site's summary is used only for the explicit agreement check.
class ProtocolTransactionReview extends StatelessWidget {
  const ProtocolTransactionReview({
    super.key,
    required this.request,
    required this.inspection,
    required this.agreement,
  });

  final ProtocolRequest request;
  final PsetInspection inspection;
  final ProtocolReviewAgreement agreement;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final outgoing = inspection.netChangeLines
        .where((line) => !line.isIncoming)
        .toList();
    final incoming = inspection.netChangeLines
        .where((line) => line.isIncoming)
        .toList();
    final locked = inspection.outputs
        .where((output) => output.isEscrow)
        .toList();
    final role = request.summary?.role ?? '';
    final risk = _riskLines(request);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!agreement.canSign) ...[
          DangerBanner(
            key: const Key('protocol-summary-mismatch'),
            title: 'Wallet and site do not agree',
            message: agreement.hasUnverifiedOutputs
                ? 'The transaction contains an output whose commitment the wallet cannot verify. Signing is blocked.'
                : '${agreement.mismatches.join(' ')} Signing is blocked because the wallet inspection is authoritative.',
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        FormCard(
          key: const Key('protocol-human-review'),
          title: 'Transaction review',
          subtitle:
              'Amounts below come from Templar Core, not from the site summary.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReviewRow(
                icon: Icons.person_outline_rounded,
                tint: s.liquid,
                label: 'Your role',
                values: [ProtocolCopy.english.role(role)],
              ),
              _ReviewRow(
                icon: Icons.north_east_rounded,
                tint: s.warning,
                label: 'You send',
                values: outgoing.map((line) => line.displayAmount).toList(),
                empty: 'No net spend from this wallet',
              ),
              _ReviewRow(
                icon: Icons.south_west_rounded,
                tint: s.success,
                label: 'You receive',
                values: incoming.map((line) => line.displayAmount).toList(),
                empty: 'No incoming amount in this transaction',
              ),
              _ReviewRow(
                icon: Icons.lock_outline_rounded,
                tint: s.liquid,
                label: 'Remains locked',
                values: locked
                    .map((output) => output.displayAmount ?? 'Blinded amount')
                    .toList(),
                empty: inspection.touchesEscrow
                    ? 'No successor covenant output'
                    : 'No covenant output',
              ),
              _ReviewRow(
                icon: Icons.account_tree_outlined,
                tint: s.accent,
                label: 'Covenant effect',
                values: [
                  ProtocolCopy.english.covenantEffect(request.action ?? ''),
                ],
              ),
              _ReviewRow(
                icon: Icons.local_gas_station_outlined,
                tint: s.inkSecondary,
                label: 'Network fee',
                values: [inspection.feeDisplay],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (risk.isNotEmpty)
          WarningBanner(
            key: const Key('protocol-risk-warning'),
            title: request.action == 'default'
                ? 'Default and collateral split'
                : 'Missed installment and penalty risk',
            message: risk.join(' · '),
          )
        else if (request.action == 'default' || request.action == 'renewal')
          const DangerBanner(
            key: Key('protocol-risk-missing'),
            title: 'Penalty data missing from the request',
            message:
                'The site did not provide the trigger, m/M, s/S, A(penalty), C(forfeit), C(return) and deadline. The wallet will not invent them.',
          ),
        const SizedBox(height: AppSpacing.lg),
        InfoBanner(
          key: const Key('protocol-summary-check'),
          title: agreement.couldCompare
              ? '${agreement.checked} site amount${agreement.checked == 1 ? '' : 's'} matched'
              : 'No comparable site amount',
          message: agreement.couldCompare
              ? 'Every unambiguous amount in the site summary matches the wallet inspection.'
              : 'The site summary had no unambiguous “You send”, “You receive”, locked collateral or network-fee line. Only the wallet reading above is authoritative.',
        ),
      ],
    );
  }

  static List<String> _riskLines(ProtocolRequest request) {
    if (request.action != 'default' && request.action != 'renewal') {
      return const [];
    }
    final terms = <String>[
      'trigger',
      'miss',
      'penalty',
      'forfeit',
      'return',
      'deadline',
      'block',
      'm/',
      's/',
    ];
    return [
      for (final line
          in request.summary?.lines ?? const <ProtocolSummaryLine>[])
        if (terms.any((term) => line.label.toLowerCase().contains(term)))
          '${line.label}: ${line.amount}',
    ];
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.icon,
    required this.tint,
    required this.label,
    required this.values,
    this.empty = 'Not provided',
  });

  final IconData icon;
  final Color tint;
  final String label;
  final List<String> values;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final shown = values.where((value) => value.trim().isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListIconTile(icon: icon, tint: tint, size: 36),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
                const SizedBox(height: 2),
                for (final value in shown.isEmpty ? [empty] : shown)
                  Text(
                    value,
                    style: AppTypography.numericSmall.copyWith(
                      color: shown.isEmpty ? s.inkFaint : s.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
