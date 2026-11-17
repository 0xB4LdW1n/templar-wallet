import 'package:flutter/material.dart';

import '../../shared/relative_time.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/protocol_copy.dart';
import 'loan_card.dart';

/// One loan in the Loans list: a row, meant to sit with its siblings in one
/// card ([LoanList]). Detailed money flow and transaction data live on
/// [LoanDetailScreen]; the row says where the loan stands and, when the loan
/// waits for the user, offers the one thing to do.
///
/// Reading order: the reference, your role, the state as a dot; the site's
/// own "what happens now"; the progress of the plan; the outstanding figure
/// and the collateral at the right edge.
class LoanOverviewCard extends StatefulWidget {
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

  /// The loan's action (sign, review, claim). Offered as a button only when
  /// the loan waits for the user, or when [primaryEmphasis] asks for it.
  final VoidCallback onPrimary;

  /// The row itself: the loan's detail page.
  final VoidCallback onOpen;
  final bool stale;
  final bool updating;

  /// The first loan that needs the user: its button is the page's primary.
  final bool primaryEmphasis;
  final bool busy;
  final DateTime? now;

  @override
  State<LoanOverviewCard> createState() => _LoanOverviewCardState();
}

class _LoanOverviewCardState extends State<LoanOverviewCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final loan = widget.loan;
    final s = AppScheme.of(context);
    final phone = AppLayout.isCompact(context);
    final referenceNow = widget.now ?? DateTime.now();
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
    final status = loanStatus(s, loan, now: referenceNow);
    final hasPlan = plan?.nTotal != null && plan!.nPaid != null;
    final progress = hasPlan
        ? '${plan.nPaid} of ${plan.nTotal} installments paid'
        : 'Installment progress unavailable in portfolio v1';
    final deadline = plan?.deadlineEstimate ?? loan.dueAtEstimate;
    final deadlineHeight = plan?.deadlineHeight ?? loan.termHeight;
    // The lead figure: what is still owed while the loan runs — the plan's
    // balance, else the site's amount to close now — and the principal once
    // it is over.
    final (String, ProtocolMoney?) lead = loan.isCompleted
        ? ('Principal', loan.principal)
        : plan?.balance != null
        ? ('Outstanding', plan!.balance)
        : loan.owed != null
        ? ('To close now', loan.owed)
        : ('Principal', loan.principal);
    final locked =
        loan.collateralOutcome?.locked ??
        (!loan.isCompleted ? loan.collateral : null);
    final missed = plan?.mMissed ?? 0;
    final threshold = plan?.periodsBeforeDefault;
    final next = expired
        ? 'Signing request expired. Open the loan for a new request.'
        : loan.nextAction?.label ?? 'No action reported by the site';
    // The status word may already say when the deadline falls; the meta
    // line then adds only its block.
    final dueInStatus = status.word.startsWith('Due ');
    final meta = [
      if (!loan.isCompleted && deadline != null)
        dueInStatus
            ? (deadlineHeight != null ? 'Deadline block $deadlineHeight' : '')
            : 'Next due ${protocolDeadlineLabel(deadline, now: referenceNow)}'
                  '${deadlineHeight != null ? ' · block $deadlineHeight' : ''}',
      if (missed > 0 && threshold != null)
        '$threshold period${threshold == 1 ? '' : 's'} before default',
    ].where((part) => part.isNotEmpty).join(' · ');

    final showAction =
        widget.primaryEmphasis || loan.actionRequired(now: referenceNow);
    final button = !showAction
        ? null
        : widget.primaryEmphasis
        ? PrimaryButton(
            key: Key('loan-primary-${loan.id}'),
            label: actionLabel,
            isLoading: widget.busy,
            isFullWidth: phone,
            onPressed: widget.busy ? null : widget.onPrimary,
          )
        : SecondaryButton(
            key: Key('loan-primary-${loan.id}'),
            label: actionLabel,
            isLoading: widget.busy,
            isFullWidth: phone,
            onPressed: widget.busy ? null : widget.onPrimary,
          );

    final updated = widget.updatedAt == null
        ? null
        : 'Updated ${relativeTimeShort(widget.updatedAt!, now: referenceNow)}'
              '${widget.stale ? ' · last known snapshot' : ''}';

    final faint = AppTypography.caption.copyWith(color: s.inkFaint);
    final figures = <(String, String, bool)>[
      if (lead.$2 != null) (lead.$1, lead.$2!.display, true),
      if (locked != null) ('Collateral locked', locked.display, false),
    ];
    // Desktop: the figures in their own right-aligned column. Compact: the
    // text needs the width, so they follow it as key/value lines.
    final Widget figuresColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < figures.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          Text(figures[i].$1, style: faint),
          figures[i].$3
              ? LoanAmounts(primary: figures[i].$2)
              : LoanAmounts(secondary: figures[i].$2),
        ],
      ],
    );
    final Widget figuresLines = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in figures)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(child: Text(f.$1, style: faint)),
                f.$3
                    ? LoanAmounts(primary: f.$2)
                    : LoanAmounts(secondary: f.$2),
              ],
            ),
          ),
      ],
    );
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LoanTitleLine(loan: loan, status: status),
                    if (widget.stale)
                      QuietTag(label: 'Stale data', dot: s.warning),
                    if (widget.updating) const QuietTag(label: 'Updating'),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  next,
                  style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    meta,
                    style: AppTypography.caption.copyWith(
                      color: s.inkSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                LoanProgressLine(
                  label: progress,
                  fraction: hasPlan && plan.nTotal! > 0
                      ? plan.nPaid! / plan.nTotal!
                      : null,
                ),
                if (phone && figures.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  figuresLines,
                ],
              ],
            ),
          ),
          if (!phone && figures.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.xl),
            figuresColumn,
          ],
          const SizedBox(width: AppSpacing.xs),
          Icon(
            Icons.chevron_right_outlined,
            size: AppSpacing.icon,
            color: s.inkFaint,
          ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label:
          '${loan.ref}, ${ProtocolCopy.english.role(loan.role)}, ${ProtocolCopy.english.state(loan.rawState)}',
      child: Column(
        key: Key('loan-overview-${loan.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onOpen,
              child: AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.instant),
                curve: AppMotion.settle,
                color: _hover ? s.hover : Colors.transparent,
                child: row,
              ),
            ),
          ),
          if (button != null || updated != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: phone
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ?button,
                        if (updated != null) ...[
                          if (button != null)
                            const SizedBox(height: AppSpacing.sm),
                          Text(
                            updated,
                            style: faint.copyWith(
                              color: widget.stale ? s.warning : s.inkFaint,
                            ),
                          ),
                        ],
                      ],
                    )
                  : Row(
                      children: [
                        if (updated != null)
                          Expanded(
                            child: Text(
                              updated,
                              style: faint.copyWith(
                                color: widget.stale ? s.warning : s.inkFaint,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        ?button,
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// The card a run of loan rows sits on: one surface, a hairline between
/// rows (design.md, "Rows, not a card each"). The rows carry no glyph tile,
/// so the hairlines start at the row padding rather than past an icon.
class LoanList extends StatelessWidget {
  const LoanList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: s.panel,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: s.edge),
        boxShadow: s.panelShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: s.edge,
                indent: AppSpacing.lg,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}
