import 'package:flutter/material.dart';

import '../../shared/relative_time.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/protocol_copy.dart';
import 'loan_card.dart' show loanStateColor;

/// Concise overview card. Detailed money flow and transaction data live on
/// [LoanDetailScreen], leaving one decision and one CTA here.
class LoanOverviewCard extends StatelessWidget {
  const LoanOverviewCard({
    super.key,
    required this.loan,
    required this.updatedAt,
    required this.onPrimary,
    required this.onOpen,
    this.stale = false,
    this.updating = false,
    this.primaryEmphasis = false,
    this.busy = false,
    this.now,
  });

  final ProtocolLoan loan;
  final DateTime? updatedAt;
  final VoidCallback onPrimary;
  final VoidCallback onOpen;
  final bool stale;
  final bool updating;
  final bool primaryEmphasis;
  final bool busy;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isCompact(context);
    final referenceNow = now ?? DateTime.now();
    final plan = loan.repaymentPlan;
    final pending = loan.pendingRequest;
    final expired = pending?.isExpired(now: referenceNow) ?? false;
    final actionLabel = ProtocolCopy.english.primaryAction(
      state: loan.rawState,
      pendingAction: expired ? null : pending?.action,
      nextKind: loan.nextAction?.rawKind,
      collateralReturnReady:
          loan.collateralOutcome?.hasRemainderToClaim ?? false,
    );
    final progress = plan?.nTotal != null && plan!.nPaid != null
        ? '${plan.nPaid} of ${plan.nTotal} installments paid'
        : 'Installment progress unavailable in portfolio v1';
    final deadline = plan?.deadlineEstimate ?? loan.dueAtEstimate;
    final balance = plan?.balance;
    final locked =
        loan.collateralOutcome?.locked ??
        (!loan.isCompleted ? loan.collateral : null);

    final button = primaryEmphasis
        ? PrimaryButton(
            key: Key('loan-primary-${loan.id}'),
            label: actionLabel,
            icon: _actionIcon(loan, requestExpired: expired),
            isLoading: busy,
            isFullWidth: phone,
            onPressed: busy ? null : onPrimary,
          )
        : SecondaryButton(
            key: Key('loan-primary-${loan.id}'),
            label: actionLabel,
            icon: _actionIcon(loan, requestExpired: expired),
            isLoading: busy,
            isFullWidth: phone,
            onPressed: busy ? null : onPrimary,
          );

    return Semantics(
      button: true,
      label:
          '${loan.ref}, ${ProtocolCopy.english.role(loan.role)}, ${ProtocolCopy.english.state(loan.rawState)}',
      child: FormCard(
        key: Key('loan-overview-${loan.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListIconTile(
                      icon: loan.role == 'lender'
                          ? Icons.call_made_rounded
                          : Icons.call_received_rounded,
                      tint: loan.role == 'lender' ? s.accent : s.liquid,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                loan.ref,
                                style: AppTypography.sectionTitleOf(
                                  context,
                                ).copyWith(color: s.ink),
                              ),
                              TagChip(
                                label: ProtocolCopy.english.role(loan.role),
                                color: s.inkSecondary,
                              ),
                              TagChip(
                                label: ProtocolCopy.english.state(
                                  loan.rawState,
                                ),
                                color: loanStateColor(s, loan.state),
                              ),
                              if (stale)
                                TagChip(label: 'Stale data', color: s.warning),
                              if (updating)
                                TagChip(label: 'Updating', color: s.liquid),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            expired
                                ? 'Signing request expired. Open the loan for a new request.'
                                : loan.nextAction?.label ??
                                      'No action reported by the site.',
                            style: AppTypography.bodySmall.copyWith(
                              color: expired ? s.warning : s.inkSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: s.inkFaint),
                  ],
                ),
              ),
            ),
            Divider(height: AppSpacing.md, color: s.edge),
            _Fact(label: 'Installments', value: progress),
            if ((plan?.mMissed ?? 0) > 0)
              _Fact(
                label: 'Missed',
                value:
                    '${plan!.mMissed} consecutive missed payment${plan.mMissed == 1 ? '' : 's'}',
                danger: true,
              ),
            if (plan?.periodsBeforeDefault != null)
              _Fact(
                label: 'Default threshold',
                value:
                    '${plan!.periodsBeforeDefault} period${plan.periodsBeforeDefault == 1 ? '' : 's'} before default',
                danger: (plan.periodsBeforeDefault ?? 0) <= 1,
              ),
            _Fact(
              label: 'Deadline',
              value: deadline == null
                  ? 'Not supplied by portfolio'
                  : '${protocolDeadlineLabel(deadline, now: referenceNow)} · block ${plan?.deadlineHeight ?? loan.termHeight ?? '—'}',
            ),
            _Fact(
              label: balance != null
                  ? 'Outstanding debt'
                  : 'Amount to close now',
              value:
                  balance?.display ??
                  loan.owed?.display ??
                  'Not supplied by portfolio',
              amount: balance != null || loan.owed != null,
            ),
            _Fact(
              label: 'Collateral locked',
              value:
                  locked?.display ??
                  (loan.isCompleted
                      ? 'No active covenant'
                      : 'Not supplied by portfolio'),
              amount: locked != null,
            ),
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerLeft, child: button),
            if (updatedAt != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Updated ${relativeTimeShort(updatedAt!, now: referenceNow)}${stale ? ' · last known snapshot' : ''}',
                style: AppTypography.caption.copyWith(
                  color: stale ? s.warning : s.inkFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _actionIcon(
    ProtocolLoan loan, {
    required bool requestExpired,
  }) {
    if (loan.pendingRequest != null && !requestExpired) {
      return Icons.draw_outlined;
    }
    if (loan.collateralOutcome?.hasRemainderToClaim == true) {
      return Icons.lock_open_rounded;
    }
    return switch (loan.nextAction?.rawKind) {
      'repay' => Icons.event_repeat_rounded,
      'claim' => Icons.savings_outlined,
      'renewal' => Icons.autorenew_rounded,
      _ => Icons.open_in_new_rounded,
    };
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.amount = false,
    this.danger = false,
  });
  final String label;
  final String value;
  final bool amount;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style:
                  (amount
                          ? AppTypography.numericSmall
                          : AppTypography.bodySmall)
                      .copyWith(
                        color: danger ? s.danger : s.ink,
                        fontWeight: amount || danger
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}
