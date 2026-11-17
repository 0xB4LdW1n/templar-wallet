import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/routes.dart';
import '../../services/protocol_link_service.dart';
import '../../services/protocol_portfolio_service.dart';
import '../../services/protocol_store.dart';
import '../../shared/relative_time.dart';
import '../../shared/widgets/banners.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/cards.dart';
import '../../shared/widgets/code_box.dart';
import '../../shared/widgets/expander.dart';
import '../../shared/widgets/hybrid_kit.dart';
import '../../shared/widgets/privacy.dart';
import '../../shared/widgets/page_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/models/protocol_records.dart';
import '../protocol/protocol_copy.dart';
import 'covenant_timeline.dart';
import 'loan_card.dart';

/// Full loan detail. It renders only portfolio facts and labels every v1 gap.
class LoanDetailScreen extends StatefulWidget {
  const LoanDetailScreen({
    super.key,
    required this.siteKey,
    required this.loanId,
    this.loan,
    this.portfolio,
    this.site,
    this.service,
    this.store,
    this.now,
  });

  final String siteKey;
  final int loanId;
  final ProtocolLoan? loan;
  final ProtocolPortfolio? portfolio;
  final ProtocolConnectedSite? site;
  final ProtocolPortfolioService? service;
  final ProtocolStore? store;
  final DateTime? now;

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  ProtocolPortfolioService get _service =>
      widget.service ?? ProtocolPortfolioService.instance;
  ProtocolStore get _store => widget.store ?? ProtocolStore.instance;

  ProtocolConnectedSite? _site;
  String? _error;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _site = widget.site;
    _service.addListener(_changed);
    if (widget.loan == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final sites = await _store.sites();
    if (!mounted) return;
    _site = sites.where((site) => site.key == widget.siteKey).firstOrNull;
    setState(() {});
    final site = _site;
    if (site != null &&
        site.hasPortfolio &&
        _service.snapshot(site.key) == null) {
      try {
        await _service.refresh(site);
      } on ProtocolPortfolioError catch (error) {
        if (mounted) setState(() => _error = error.message);
      }
    }
  }

  ProtocolPortfolioSnapshot? get _snapshot =>
      widget.loan != null ? null : _service.snapshot(widget.siteKey);

  ProtocolPortfolio? get _portfolio => widget.portfolio ?? _snapshot?.portfolio;

  ProtocolLoan? get _loan {
    if (widget.loan != null) return widget.loan;
    return _portfolio?.loans
        .where((loan) => loan.id == widget.loanId)
        .firstOrNull;
  }

  Future<void> _openSite() async {
    final site = _site;
    if (site == null || _opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      final uri = site.hasPortfolio
          ? await _service.openLink(site, to: '/loans/${widget.loanId}')
          : Uri.parse(site.origin);
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error = 'The browser did not open.');
      }
    } on ProtocolPortfolioError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _primary(ProtocolLoan loan) {
    final pending = loan.pendingRequest;
    if (pending != null && !pending.isExpired(now: widget.now)) {
      ProtocolLinkService.instance.inject(pending.link);
      return;
    }
    _openSite();
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;
    final portfolio = _portfolio;
    final snapshot = _snapshot;
    final stale = snapshot?.error != null;
    final loading =
        snapshot?.loading ??
        (widget.loan == null && loan == null && _error == null);
    final pad = AppSpacing.pagePadding(context);
    final s = AppScheme.of(context);
    final status = loan == null ? null : loanStatus(s, loan, now: widget.now);
    return Scaffold(
      body: PageBackground.flat(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: AppSpacing.contentMaxWidth + 2 * pad,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + AppSpacing.xxl),
              children: [
                PageHeader(
                  title: loan?.ref ?? 'Loan detail',
                  subtitle: loan == null
                      ? 'Templar Protocol'
                      : '${ProtocolCopy.english.role(loan.role)} · ${status!.word}',
                  actions: [
                    GhostButton(
                      label: 'Back to loans',
                      icon: Icons.arrow_back_outlined,
                      onPressed: () => context.go(AppRoutes.loans),
                    ),
                  ],
                ),
                if (stale) ...[
                  WarningBanner(
                    title: 'Stale loan snapshot',
                    message:
                        '${snapshot!.error!.message} Values below are the last successful answer from ${snapshot.fetchedAt == null ? 'the site' : relativeTimeShort(snapshot.fetchedAt!, now: widget.now)}.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_error != null) ...[
                  DangerBanner(message: _error!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (loading)
                  Center(
                    child: SizedBox.square(
                      dimension: AppSpacing.xl,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: s.inkSecondary,
                      ),
                    ),
                  )
                else if (loan == null)
                  const WarningBanner(
                    title: 'Loan not available',
                    message:
                        'Refresh Loans or reconnect the site. No cached loan data was found.',
                  )
                else
                  _Layout(
                    main: [
                      _NowSection(
                        loan: loan,
                        busy: _opening,
                        now: widget.now,
                        onPrimary: () => _primary(loan),
                      ),
                      _LoanSummary(loan: loan),
                      _InstallmentPlan(loan: loan),
                      _RiskSection(loan: loan, now: widget.now),
                      _TechnicalDetails(
                        loan: loan,
                        tipHeight: portfolio?.tipHeight,
                      ),
                    ],
                    side: [
                      FormCard(
                        title: 'Covenant lifecycle',
                        subtitle:
                            'Each state is one collateral UTXO. Spending replaces it or ends the loan.',
                        child: CovenantTimeline(loan: loan),
                      ),
                      _ActivitySection(loan: loan),
                    ],
                    footer:
                        snapshot?.fetchedAt != null || portfolio?.asOf != null
                        ? Text(
                            'Updated ${relativeTimeShort(snapshot?.fetchedAt ?? portfolio!.asOf, now: widget.now)}${stale ? ' · stale' : ''}',
                            style: AppTypography.caption.copyWith(
                              color: stale ? s.warning : s.inkFaint,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Terms and actions on the left, the covenant's story on the right; one
/// column, in that order, when the window is too narrow for two.
class _Layout extends StatelessWidget {
  const _Layout({required this.main, required this.side, this.footer});
  final List<Widget> main;
  final List<Widget> side;
  final Widget? footer;

  static const double _twoColumns = 960;

  @override
  Widget build(BuildContext context) {
    final gap = AppLayout.isPhone(context) ? AppSpacing.md : AppSpacing.lg;
    Widget column(List<Widget> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          items[i],
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _twoColumns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: column(main)),
                  const SizedBox(width: AppSpacing.xl),
                  Expanded(flex: 2, child: column(side)),
                ],
              )
            else
              column([
                main.first,
                ...side.take(1),
                ...main.skip(1),
                ...side.skip(1),
              ]),
            if (footer != null) ...[
              const SizedBox(height: AppSpacing.md),
              footer!,
            ],
          ],
        );
      },
    );
  }
}

class _NowSection extends StatelessWidget {
  const _NowSection({
    required this.loan,
    required this.onPrimary,
    required this.busy,
    this.now,
  });
  final ProtocolLoan loan;
  final VoidCallback onPrimary;
  final bool busy;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final phone = AppLayout.isPhone(context);
    final plan = loan.repaymentPlan;
    final pending = loan.pendingRequest;
    final expired = pending?.isExpired(now: now) ?? false;
    final collateralReturnReady =
        loan.collateralOutcome?.hasRemainderToClaim ?? false;
    final amount =
        (collateralReturnReady
            ? loan.collateralOutcome?.returnAmount
            : plan?.regularDue) ??
        (loan.nextAction?.kind == ProtocolNextKind.repay ? loan.owed : null);
    final deadline = plan?.deadlineEstimate ?? loan.dueAtEstimate;
    final actionLabel = ProtocolCopy.english.primaryAction(
      state: loan.rawState,
      pendingAction: expired ? null : pending?.action,
      nextKind: loan.nextAction?.rawKind,
      collateralReturnReady: collateralReturnReady,
    );
    final requiresAction = loan.actionRequired(now: now);
    final button = requiresAction
        ? PrimaryButton(
            key: const Key('loan-detail-primary'),
            label: actionLabel,
            icon: pending != null ? Icons.draw_outlined : null,
            isLoading: busy,
            isFullWidth: phone,
            onPressed: busy ? null : onPrimary,
          )
        : SecondaryButton(
            key: const Key('loan-detail-primary'),
            label: actionLabel,
            icon: Icons.open_in_new_outlined,
            isLoading: busy,
            isFullWidth: phone,
            onPressed: busy ? null : onPrimary,
          );
    return FormCard(
      key: const Key('loan-detail-now'),
      title: 'Now',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            expired
                ? 'The signing request expired'
                : collateralReturnReady
                ? 'Your collateral remainder is ready'
                : loan.nextAction?.label ?? 'No action reported',
            style: AppTypography.bodyLarge.copyWith(color: s.ink),
          ),
          const SizedBox(height: AppSpacing.sm),
          _DetailFact(
            label: 'Amount',
            value: amount?.display ?? 'No amount supplied',
            amount: amount != null,
          ),
          _DetailFact(
            label: 'Deadline',
            value: deadline == null
                ? 'No deadline supplied'
                : '${protocolDeadlineLabel(deadline, now: now)}${plan?.deadlineHeight == null ? '' : ' · block ${plan!.deadlineHeight}'}',
          ),
          _DetailFact(
            label: 'Consequence',
            sentence: true,
            value: ProtocolCopy.english.covenantEffect(
              collateralReturnReady
                  ? 'collateral_claim'
                  : pending?.action ?? loan.nextAction?.rawKind ?? '',
            ),
          ),
          SizedBox(height: phone ? AppSpacing.lg : AppSpacing.xl),
          Align(alignment: Alignment.centerRight, child: button),
        ],
      ),
    );
  }
}

class _LoanSummary extends StatelessWidget {
  const _LoanSummary({required this.loan});
  final ProtocolLoan loan;

  @override
  Widget build(BuildContext context) {
    final plan = loan.repaymentPlan;
    return FormCard(
      title: 'Loan summary',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailFact(
            label: 'Role',
            value: ProtocolCopy.english.role(loan.role),
          ),
          if (loan.principal != null)
            _DetailFact(
              label: 'Principal',
              value: loan.principal!.display,
              amount: true,
            ),
          if (plan?.balance != null)
            _DetailFact(
              label: 'Outstanding balance',
              value: plan!.balance!.display,
              amount: true,
            ),
          if (plan?.regularDue != null)
            _DetailFact(
              label: 'Installment',
              value: plan!.regularDue!.display,
              amount: true,
            ),
          if (loan.collateral != null)
            _DetailFact(
              label: 'Collateral',
              value: loan.collateral!.display,
              amount: true,
            ),
          if (loan.interest?.rateBps != null)
            _DetailFact(
              label: 'Rate',
              value: protocolBpsLabel(loan.interest!.rateBps!),
            ),
          if (loan.templarFee != null)
            _DetailFact(
              label: 'Templar fee',
              value:
                  '${loan.templarFee!.display}${loan.templarFee!.payer == null ? '' : ' · paid by ${loan.templarFee!.payer}'}',
              amount: true,
            ),
          if (loan.startHeight != null || loan.termHeight != null)
            _DetailFact(
              label: 'Term',
              value:
                  'Block ${loan.startHeight ?? '—'} → ${loan.termHeight ?? '—'}',
            ),
        ],
      ),
    );
  }
}

class _InstallmentPlan extends StatelessWidget {
  const _InstallmentPlan({required this.loan});
  final ProtocolLoan loan;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final plan = loan.repaymentPlan;
    if (plan == null || plan.nTotal == null || plan.nPaid == null) {
      return const FormCard(
        key: Key('loan-plan-v1'),
        title: 'Installment plan',
        child: InfoBanner(
          title: 'Not included in portfolio v1',
          message:
              'The site has not supplied N, paid installments, consecutive misses, current step or remaining balance.',
        ),
      );
    }
    final paid = plan.nPaid!;
    final total = plan.nTotal!;
    final missed = plan.mMissed ?? 0;
    final future = (total - paid - (missed > 0 ? 1 : 0)).clamp(0, total);
    return FormCard(
      key: const Key('loan-installment-plan'),
      title: 'Installment plan',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoanProgressLine(
            label: '$paid of $total installments paid',
            fraction: total > 0 ? paid / total : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.lg,
            runSpacing: AppSpacing.sm,
            children: [
              LoanStatusDot(color: s.ink, word: '$paid paid'),
              if (!loan.isCompleted)
                LoanStatusDot(
                  color: missed > 0 ? s.danger : s.warning,
                  word: '1 due',
                ),
              if (missed > 0)
                LoanStatusDot(color: s.danger, word: '$missed missed'),
              if (future > 0)
                LoanStatusDot(color: s.edgeStrong, word: '$future future'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskSection extends StatelessWidget {
  const _RiskSection({required this.loan, this.now});
  final ProtocolLoan loan;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final plan = loan.repaymentPlan;
    final outcome = loan.collateralOutcome;
    if (plan == null && outcome == null) {
      return const FormCard(
        key: Key('loan-risk-v1'),
        title: 'Risk and penalty',
        child: WarningBanner(
          title: 'Exact penalty data not supplied',
          message:
              'Portfolio v1 does not expose m/M, s/S, A(penalty), C(forfeit), C(return) or the covenant deadline. The wallet will not estimate them.',
        ),
      );
    }
    return FormCard(
      key: const Key('loan-risk-penalty'),
      title: 'Risk and penalty',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DetailFact(
            label: 'Default trigger',
            value: plan?.mMax == null || plan?.sMax == null
                ? 'Not supplied'
                : '${plan!.mMissed ?? 0}/${plan.mMax} consecutive misses or step ${plan.step ?? 0}/${plan.sMax}',
          ),
          // The protocol's own names for these figures, kept verbatim so
          // they match the site and the contract.
          _DetailFact(
            label: 'A(penalty)',
            monoLabel: true,
            value: plan?.penaltyDue?.display ?? 'Not supplied',
            amount: plan?.penaltyDue != null,
          ),
          _DetailFact(
            label: 'C(forfeit)',
            monoLabel: true,
            value: outcome?.forfeit?.display ?? 'Not supplied',
            amount: outcome?.forfeit != null,
          ),
          _DetailFact(
            label: 'C(return)',
            monoLabel: true,
            value: outcome?.returnAmount?.display ?? 'Not supplied',
            amount: outcome?.returnAmount != null,
          ),
          _DetailFact(
            label: 'Deadline',
            value: plan?.deadlineHeight == null
                ? 'Not supplied'
                : 'Block ${plan!.deadlineHeight}${plan.deadlineEstimate == null ? '' : ' · ${protocolDeadlineLabel(plan.deadlineEstimate!, now: now)}'}',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            loan.role == 'borrower'
                ? 'If the reported trigger is reached, the lender receives C(forfeit). You receive C(return), which may require a collateral-claim signature.'
                : 'If the reported trigger is reached, you receive C(forfeit). The borrower keeps C(return), which may require their signature.',
            style: AppTypography.caption.copyWith(color: s.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.loan});
  final ProtocolLoan loan;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final events = <(String, String)>[
      if (loan.pendingRequest != null)
        (
          'Signature requested',
          protocolActionLabel(loan.pendingRequest!.action),
        ),
      if (loan.txids.origination != null)
        ('Origination transaction', 'Root covenant created or submitted'),
      for (final node in loan.covenant?.nodes ?? const <ProtocolCovenantNode>[])
        (
          node.isCurrent
              ? 'Covenant current'
              : 'Covenant ${node.status.replaceAll('_', ' ')}',
          node.spentBy == null
              ? 'Generation ${node.index + 1}'
              : protocolActionLabel(node.spentBy!),
        ),
      if (loan.txids.repayment != null)
        ('Repayment transaction', 'Debt closed'),
      if (loan.txids.liquidation != null)
        ('Default or liquidation transaction', 'Collateral settlement'),
    ];
    return FormCard(
      title: 'Activity',
      child: events.isEmpty
          ? const InfoBanner(
              message: 'No activity events were supplied by the portfolio.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < events.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: s.edge),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          events[i].$1,
                          style: AppTypography.bodyOf(
                            context,
                          ).copyWith(color: s.ink),
                        ),
                        Text(
                          events[i].$2,
                          style: AppTypography.caption.copyWith(
                            color: s.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _TechnicalDetails extends StatelessWidget {
  const _TechnicalDetails({required this.loan, this.tipHeight});
  final ProtocolLoan loan;
  final int? tipHeight;

  @override
  Widget build(BuildContext context) {
    final plan = loan.repaymentPlan;
    return ExpanderCard(
      key: const Key('loan-technical-details'),
      title: 'Technical details',
      subtitle: 'Transaction ids, escrow, asset ids and B/n/m/s',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (loan.principal?.asset != null)
            CopyRow(label: 'Principal asset', value: loan.principal!.asset!),
          if (loan.collateral?.asset != null)
            CopyRow(label: 'Collateral asset', value: loan.collateral!.asset!),
          if (loan.escrowAddress != null)
            CopyRow(label: 'Escrow address', value: loan.escrowAddress!),
          if (loan.covenant?.currentTxid != null)
            CopyRow(
              label: 'Current covenant',
              value: loan.covenant!.currentTxid!,
            ),
          if (loan.txids.origination != null)
            CopyRow(label: 'Origination txid', value: loan.txids.origination!),
          if (loan.txids.repayment != null)
            CopyRow(label: 'Repayment txid', value: loan.txids.repayment!),
          if (loan.txids.liquidation != null)
            CopyRow(label: 'Liquidation txid', value: loan.txids.liquidation!),
          const SizedBox(height: AppSpacing.sm),
          KvRow(label: 'B', value: plan?.balance?.display ?? 'not supplied'),
          KvRow(label: 'n', value: plan?.nPaid?.toString() ?? 'not supplied'),
          KvRow(label: 'm', value: plan?.mMissed?.toString() ?? 'not supplied'),
          KvRow(label: 's', value: plan?.step?.toString() ?? 'not supplied'),
          KvRow(
            label: 'Chain tip',
            value: tipHeight?.toString() ?? 'not supplied',
          ),
          KvRow(label: 'Raw state', value: loan.rawState),
          KvRow(
            label: 'Raw action',
            value:
                loan.pendingRequest?.action ??
                loan.nextAction?.rawKind ??
                'none',
          ),
        ],
      ),
    );
  }
}

/// A key/value line: the key in the secondary ink (in mono when it is one of
/// the protocol's formula names), the value beside it — an amount in the
/// tabular `numeric`, a sentence wrapping in `body`.
class _DetailFact extends StatelessWidget {
  const _DetailFact({
    required this.label,
    required this.value,
    this.amount = false,
    this.monoLabel = false,
    this.sentence = false,
  });
  final String label;
  final String value;

  /// A figure: tabular, and hidden behind the privacy mask.
  final bool amount;
  final bool monoLabel;

  /// A sentence takes the full width under its key instead of a ragged
  /// right edge.
  final bool sentence;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final body = AppTypography.bodyOf(context);
    final key = Text(
      label,
      style: (monoLabel ? AppTypography.mono : body).copyWith(
        color: s.inkSecondary,
      ),
    );
    if (sentence) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            key,
            const SizedBox(height: AppSpacing.xs),
            Text(value, style: body.copyWith(color: s.ink)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 136, child: key),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: amount
                ? Amount(
                    value,
                    textAlign: TextAlign.end,
                    style: AppTypography.numeric.copyWith(color: s.ink),
                  )
                : Text(
                    value,
                    textAlign: TextAlign.end,
                    style: body.copyWith(color: s.ink),
                  ),
          ),
        ],
      ),
    );
  }
}
