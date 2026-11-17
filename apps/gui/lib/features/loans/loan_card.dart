// One loan as a row: the reference, your role in it, where it stands, the
// amounts at the right edge, and how far it has come — then, on demand, the
// figures and identifiers behind it.
//
// The row is pure presentation over `ProtocolLoan`: it never fetches and
// never signs. "Sign now" hands the loan's `templar://sign` link back to the
// caller, which feeds it to the app's own link handler — the same path a
// link from the browser takes, with the same review and the same gate.
//
// The pieces every loan surface shares — the status dot and word, the 2 px
// progress line, the role tag — live here too, so the Loans list, a single
// overview and the detail page say a loan's state in the same words.

import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/privacy.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/protocol_copy.dart';

class LoanCard extends StatefulWidget {
  const LoanCard({
    super.key,
    required this.loan,
    required this.tipHeight,
    this.onSign,
    this.onOpen,
    this.busy = false,
    this.now,
  });

  final ProtocolLoan loan;

  /// The site's chain tip when the portfolio was computed — the term's "now".
  final int tipHeight;

  /// Called with the pending request when "Sign now" is pressed. Null hides
  /// the button even if a request is pending (a closed site, say).
  final void Function(ProtocolPendingRequest request)? onSign;

  /// "Open on Templar Protocol" for this loan.
  final VoidCallback? onOpen;

  /// An open link is being fetched: the buttons wait.
  final bool busy;

  /// Injectable clock, for the expiry line in tests.
  final DateTime? now;

  @override
  State<LoanCard> createState() => _LoanCardState();
}

class _LoanCardState extends State<LoanCard> {
  bool _details = false;
  bool _hover = false;

  ProtocolLoan get loan => widget.loan;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final pending = loan.pendingRequest;
    final next = loan.nextAction;
    final status = loanStatus(s, loan, now: widget.now);
    final sign = widget.onSign == null || pending == null
        ? null
        : SecondaryButton(
            key: Key('loan-sign-${loan.id}'),
            label: 'Sign now',
            icon: Icons.draw_outlined,
            dense: true,
            isFullWidth: phone,
            onPressed: widget.busy ? null : () => widget.onSign!(pending),
          );

    final head = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LoanTitleLine(loan: loan, status: status),
              if (next != null && next.label.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  next.label,
                  style: AppTypography.caption.copyWith(color: s.inkSecondary),
                ),
              ],
              if (pending != null) ...[
                const SizedBox(height: AppSpacing.xs),
                _PendingLine(pending: pending, now: widget.now),
              ],
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.lg),
        LoanAmounts(
          primary: loan.principal?.display,
          secondary: loan.collateral?.display,
        ),
        const SizedBox(width: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
            _details ? Icons.expand_less_outlined : Icons.expand_more_outlined,
            size: AppSpacing.icon,
            color: s.inkFaint,
          ),
        ),
      ],
    );

    return Container(
      key: Key('loan-card-${loan.id}'),
      color: _hover ? s.hover : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              key: Key('loan-details-${loan.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _details = !_details),
              child: Semantics(
                button: true,
                expanded: _details,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      head,
                      if (loan.state.isOpen) ...[
                        const SizedBox(height: AppSpacing.md),
                        _TermLine(loan: loan, tipHeight: widget.tipHeight),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (sign != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Align(alignment: Alignment.centerRight, child: sign),
            ),
          if (_details)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: _Details(
                loan: loan,
                busy: widget.busy,
                onOpen: widget.onOpen,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Shared pieces ─────────────────────────────────────────────────────────────

/// The colour of a loan state's dot: the status hues for what is going well,
/// at risk or lost, the faint ink for what is over.
Color loanStateColor(AppScheme s, ProtocolLoanState state) => switch (state) {
  ProtocolLoanState.originating => s.warning,
  ProtocolLoanState.active => s.success,
  ProtocolLoanState.repaid => s.inkFaint,
  ProtocolLoanState.defaulted => s.danger,
  ProtocolLoanState.liquidated => s.danger,
  ProtocolLoanState.unknown => s.inkFaint,
};

/// A loan's state as a dot and a word. An active loan is told more exactly
/// from the facts the site sent: missed installments and a passed deadline
/// are danger, a deadline within the week is a warning, anything else is
/// current. Nothing is estimated beyond those facts.
({Color color, String word}) loanStatus(
  AppScheme s,
  ProtocolLoan loan, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  switch (loan.state) {
    case ProtocolLoanState.active:
      final plan = loan.repaymentPlan;
      final missed = plan?.mMissed ?? 0;
      if (missed > 0) {
        return (
          color: s.danger,
          word: '$missed missed installment${missed == 1 ? '' : 's'}',
        );
      }
      final deadline = plan?.deadlineEstimate ?? loan.dueAtEstimate;
      if (deadline != null) {
        final left = deadline.toLocal().difference(ref);
        if (left.isNegative) return (color: s.danger, word: 'Overdue');
        if (left.inDays < 7) {
          return (
            color: s.warning,
            word: 'Due ${protocolDeadlineLabel(deadline, now: ref)}',
          );
        }
      }
      return (color: s.success, word: 'Current');
    case ProtocolLoanState.originating:
      return (
        color: s.warning,
        word: ProtocolCopy.english.state('originating'),
      );
    case ProtocolLoanState.repaid:
    case ProtocolLoanState.defaulted:
    case ProtocolLoanState.liquidated:
    case ProtocolLoanState.unknown:
      return (
        color: loanStateColor(s, loan.state),
        word: ProtocolCopy.english.state(
          loan.state == ProtocolLoanState.unknown
              ? loan.stateLabel
              : loan.rawState,
        ),
      );
  }
}

/// A 6 px dot and the word beside it in the secondary ink.
class LoanStatusDot extends StatelessWidget {
  const LoanStatusDot({super.key, required this.color, required this.word});

  final Color color;
  final String word;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            word,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ),
      ],
    );
  }
}

/// The reference in mono, the role as a quiet tag, the state as a dot.
class LoanTitleLine extends StatelessWidget {
  const LoanTitleLine({super.key, required this.loan, required this.status});

  final ProtocolLoan loan;
  final ({Color color, String word}) status;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(loan.ref, style: AppTypography.mono.copyWith(color: s.ink)),
        QuietTag(label: ProtocolCopy.english.role(loan.role)),
        LoanStatusDot(color: status.color, word: status.word),
      ],
    );
  }
}

/// The right-hand amounts of a loan row: the lead figure in `numeric` and
/// the ink, the second one quieter beneath it. Both hide behind the privacy
/// mask.
class LoanAmounts extends StatelessWidget {
  const LoanAmounts({super.key, this.primary, this.secondary});

  final String? primary;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (primary != null)
          Amount(
            primary!,
            textAlign: TextAlign.end,
            style: AppTypography.numeric.copyWith(color: s.ink),
          ),
        if (secondary != null)
          Amount(
            secondary!,
            textAlign: TextAlign.end,
            style: AppTypography.numericSmall.copyWith(color: s.inkSecondary),
          ),
      ],
    );
  }
}

/// A single goal's progress: its words above, a 2 px neutral line below.
/// Null [fraction] prints the words alone.
class LoanProgressLine extends StatelessWidget {
  const LoanProgressLine({
    super.key,
    required this.label,
    this.fraction,
    this.trailing,
    this.trailingKey,
  });

  final String label;
  final double? fraction;
  final String? trailing;
  final Key? trailingKey;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final faint = AppTypography.caption.copyWith(color: s.inkSecondary);
    final f = fraction;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: faint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null && trailing!.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(trailing!, key: trailingKey, style: faint),
            ],
          ],
        ),
        if (f != null) ...[
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 2,
              child: Stack(
                children: [
                  Container(color: s.edge),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: f.clamp(0.0, 1.0),
                    child: Container(color: s.inkSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Row pieces ────────────────────────────────────────────────────────────────

/// The request waiting for this wallet: what it is and how long it lives.
class _PendingLine extends StatelessWidget {
  const _PendingLine({required this.pending, this.now});
  final ProtocolPendingRequest pending;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final p = pending;
    String? expiry;
    if (p.expiresAt != null) {
      final ref = (now ?? DateTime.now()).toUtc();
      final left = p.expiresAt!.difference(ref);
      expiry = left.isNegative
          ? 'request expired — the site will issue a new one'
          : left.inMinutes >= 1
          ? 'request expires in ${left.inMinutes} min'
          : 'request expires in under a minute';
    }
    return LoanStatusDot(
      color: s.warning,
      word: [
        'Your signature',
        protocolActionLabel(p.action),
        ?expiry,
      ].join(' · '),
    );
  }
}

/// How much of the term has run, in blocks, with the time it stands for.
class _TermLine extends StatelessWidget {
  const _TermLine({required this.loan, required this.tipHeight});
  final ProtocolLoan loan;
  final int tipHeight;

  @override
  Widget build(BuildContext context) {
    final plan = loan.repaymentPlan;
    if (plan?.nTotal != null && plan!.nPaid != null && plan.nTotal! > 0) {
      return LoanProgressLine(
        label: '${plan.nPaid} of ${plan.nTotal} installments paid',
        fraction: plan.nPaid! / plan.nTotal!,
      );
    }
    final progress = loan.termProgress(tipHeight);
    final left = protocolBlocksLeftLabel(loan.blocksLeft);
    final due = loan.dueAtEstimate;
    final label = progress == null
        ? (loan.state == ProtocolLoanState.originating
              ? 'Term starts when the opening transaction confirms'
              : 'No term yet')
        : 'Block ${_g(loan.startHeight)} → ${_g(loan.termHeight)}';
    final right = [
      if (left.isNotEmpty) left,
      if (due != null) 'due ≈ ${_localShort(due)}',
    ].join(' · ');
    return LoanProgressLine(
      label: label,
      fraction: progress,
      trailing: right,
      trailingKey: const Key('loan-time-left'),
    );
  }

  static String _g(int? n) => n == null ? '—' : protocolGroupDigits('$n');
}

/// The figures and identifiers behind the row, folded until asked for:
/// what is owed, the terms, the escrow and the transactions someone checks
/// against an explorer, and the way to the loan on the site.
class _Details extends StatelessWidget {
  const _Details({required this.loan, required this.busy, this.onOpen});
  final ProtocolLoan loan;
  final bool busy;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final owed = loan.owed;
    final amounts = <(String, String)>[
      if (owed != null && loan.state.isOpen)
        (loan.role == 'lender' ? 'Owed to you' : 'You owe', owed.display),
      if (loan.principal != null) ('Principal', loan.principal!.display),
      if (loan.collateral != null) ('Collateral', loan.collateral!.display),
      if (loan.interest != null)
        (
          'Interest',
          '${loan.interest!.display}'
              '${loan.interest!.rateBps != null ? ' · ${protocolBpsLabel(loan.interest!.rateBps!)}' : ''}',
        ),
      if (loan.templarFee != null)
        (
          'Templar fee',
          '${loan.templarFee!.display}'
              '${(loan.templarFee!.payer ?? '').isNotEmpty ? ' · paid by ${loan.templarFee!.payer}' : ''}',
        ),
    ];
    final tx = loan.txids;
    final ids = <(String, String)>[
      if ((loan.escrowAddress ?? '').isNotEmpty)
        ('Escrow', loan.escrowAddress!),
      if ((tx.origination ?? '').isNotEmpty) ('Opened in', tx.origination!),
      if ((tx.repayment ?? '').isNotEmpty) ('Repaid in', tx.repayment!),
      if ((tx.liquidation ?? '').isNotEmpty) ('Liquidated in', tx.liquidation!),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: s.edge),
        const SizedBox(height: AppSpacing.sm),
        for (final (label, value) in amounts)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.bodyOf(
                      context,
                    ).copyWith(color: s.inkSecondary),
                  ),
                ),
                Amount(
                  value,
                  textAlign: TextAlign.end,
                  style: AppTypography.numeric.copyWith(color: s.ink),
                ),
              ],
            ),
          ),
        if (loan.openedAt != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Opened',
                    style: AppTypography.bodyOf(
                      context,
                    ).copyWith(color: s.inkSecondary),
                  ),
                ),
                Text(
                  _localShort(loan.openedAt!),
                  style: AppTypography.bodyOf(context).copyWith(color: s.ink),
                ),
              ],
            ),
          ),
        if (ids.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          DataWell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < ids.length; i++) ...[
                  if (i > 0) Divider(height: AppSpacing.md, color: s.edge),
                  CopyRow(label: ids[i].$1, value: ids[i].$2),
                ],
              ],
            ),
          ),
        ],
        if (amounts.isEmpty && ids.isEmpty && loan.openedAt == null)
          Text(
            'The site sent no details for this loan yet',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        if (onOpen != null) ...[
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerRight,
            child: SecondaryButton(
              key: Key('loan-open-${loan.id}'),
              label: 'Open on Templar Protocol',
              icon: Icons.open_in_new_outlined,
              onPressed: busy ? null : onOpen,
              isLoading: busy,
              isFullWidth: phone,
            ),
          ),
        ],
      ],
    );
  }
}

/// `3 Oct, 14:32` in the local zone — enough to recognise a day and an hour.
String _localShort(DateTime t) {
  final l = t.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hh = l.hour.toString().padLeft(2, '0');
  final mm = l.minute.toString().padLeft(2, '0');
  final now = DateTime.now();
  final year = l.year == now.year ? '' : ' ${l.year}';
  return '${l.day} ${months[l.month - 1]}$year, $hh:$mm';
}
