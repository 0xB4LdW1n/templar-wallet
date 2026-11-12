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
import '../../shared/widgets/list_rows.dart';
import '../../shared/widgets/page_header.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../protocol/models/protocol_portfolio.dart';
import '../protocol/models/protocol_records.dart';
import '../protocol/protocol_copy.dart';
import 'covenant_timeline.dart';

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
    return Scaffold(
      body: PageBackground.flat(
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + AppSpacing.xxl),
          children: [
            PageHeader(
              title: loan?.ref ?? 'Loan detail',
              subtitle: loan == null
                  ? 'Templar Lend'
                  : '${ProtocolCopy.english.role(loan.role)} · ${ProtocolCopy.english.state(loan.rawState)}',
              actions: [
                GhostButton(
                  label: 'Back to loans',
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => context.go(AppRoutes.loans),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
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
              const Center(child: CircularProgressIndicator())
            else if (loan == null)
              const WarningBanner(
                title: 'Loan not available',
                message:
                    'Refresh Loans or reconnect the site. No cached loan data was found.',
              )
            else ...[
              _NowSection(
                loan: loan,
                busy: _opening,
                now: widget.now,
                onPrimary: () => _primary(loan),
              ),
              const SizedBox(height: AppSpacing.lg),
              _LoanSummary(loan: loan),
              const SizedBox(height: AppSpacing.lg),
              _InstallmentPlan(loan: loan),
              const SizedBox(height: AppSpacing.lg),
              _SectionCard(
                title: 'Covenant lifecycle',
                subtitle:
                    'Each state is one collateral UTXO. Spending replaces it or ends the loan.',
                child: CovenantTimeline(loan: loan),
              ),
              const SizedBox(height: AppSpacing.lg),
              _RiskSection(loan: loan),
              const SizedBox(height: AppSpacing.lg),
              _ActivitySection(loan: loan),
              const SizedBox(height: AppSpacing.lg),
              _TechnicalDetails(loan: loan, tipHeight: portfolio?.tipHeight),
              if (snapshot?.fetchedAt != null || portfolio?.asOf != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Updated ${relativeTimeShort(snapshot?.fetchedAt ?? portfolio!.asOf, now: widget.now)}${stale ? ' · stale' : ''}',
                  style: AppTypography.caption.copyWith(
                    color: stale
                        ? AppScheme.of(context).warning
                        : AppScheme.of(context).inkFaint,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
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
    return FormCard(
      key: const Key('loan-detail-now'),
      title: 'Now',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                requiresAction ? Icons.bolt_rounded : Icons.schedule_rounded,
                color: requiresAction ? s.accent : s.liquid,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expired
                          ? 'The signing request expired'
                          : collateralReturnReady
                          ? 'Your collateral remainder is ready'
                          : loan.nextAction?.label ?? 'No action reported',
                      style: AppTypography.sectionTitleOf(
                        context,
                      ).copyWith(color: s.ink),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _DetailFact(
                      label: 'Amount',
                      value: amount?.display ?? 'No amount supplied',
                    ),
                    _DetailFact(
                      label: 'Deadline',
                      value: deadline == null
                          ? 'No deadline supplied'
                          : '${deadline.toLocal()}${plan?.deadlineHeight == null ? '' : ' · block ${plan!.deadlineHeight}'}',
                    ),
                    _DetailFact(
                      label: 'Consequence',
                      value: ProtocolCopy.english.covenantEffect(
                        collateralReturnReady
                            ? 'collateral_claim'
                            : pending?.action ?? loan.nextAction?.rawKind ?? '',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (requiresAction)
            PrimaryButton(
              key: const Key('loan-detail-primary'),
              label: actionLabel,
              icon: pending != null
                  ? Icons.draw_outlined
                  : Icons.open_in_new_rounded,
              isLoading: busy,
              onPressed: busy ? null : onPrimary,
            )
          else
            SecondaryButton(
              key: const Key('loan-detail-primary'),
              label: actionLabel,
              icon: Icons.open_in_new_rounded,
              isLoading: busy,
              onPressed: busy ? null : onPrimary,
            ),
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
    return SummaryCard(
      title: 'Loan summary',
      rows: [
        (
          label: 'Role',
          value: ProtocolCopy.english.role(loan.role),
          isMono: false,
        ),
        if (loan.principal != null)
          (label: 'Principal', value: loan.principal!.display, isMono: false),
        if (plan?.balance != null)
          (
            label: 'Outstanding balance',
            value: plan!.balance!.display,
            isMono: false,
          ),
        if (loan.collateral != null)
          (label: 'Collateral', value: loan.collateral!.display, isMono: false),
        if (loan.interest?.rateBps != null)
          (
            label: 'Rate',
            value: protocolBpsLabel(loan.interest!.rateBps!),
            isMono: false,
          ),
        if (loan.templarFee != null)
          (
            label: 'Templar fee',
            value:
                '${loan.templarFee!.display}${loan.templarFee!.payer == null ? '' : ' · paid by ${loan.templarFee!.payer}'}',
            isMono: false,
          ),
      ],
    );
  }
}

class _InstallmentPlan extends StatelessWidget {
  const _InstallmentPlan({required this.loan});
  final ProtocolLoan loan;

  @override
  Widget build(BuildContext context) {
    final plan = loan.repaymentPlan;
    if (plan == null || plan.nTotal == null || plan.nPaid == null) {
      return const _SectionCard(
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
    return _SectionCard(
      key: const Key('loan-installment-plan'),
      title: 'Installment plan',
      subtitle: '$paid of $total installments paid',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          _PlanStatus(label: '$paid paid', state: 'paid'),
          if (!loan.isCompleted)
            _PlanStatus(label: '1 due', state: missed > 0 ? 'late' : 'due'),
          if (missed > 0) _PlanStatus(label: '$missed missed', state: 'missed'),
          if (future > 0) _PlanStatus(label: '$future future', state: 'future'),
        ],
      ),
    );
  }
}

class _PlanStatus extends StatelessWidget {
  const _PlanStatus({required this.label, required this.state});
  final String label;
  final String state;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    final color = switch (state) {
      'paid' => s.success,
      'due' => s.liquid,
      'late' || 'missed' => s.danger,
      _ => s.inkFaint,
    };
    return TagChip(label: label, color: color);
  }
}

class _RiskSection extends StatelessWidget {
  const _RiskSection({required this.loan});
  final ProtocolLoan loan;

  @override
  Widget build(BuildContext context) {
    final plan = loan.repaymentPlan;
    final outcome = loan.collateralOutcome;
    if (plan == null && outcome == null) {
      return const _SectionCard(
        key: Key('loan-risk-v1'),
        title: 'Risk and penalty',
        child: WarningBanner(
          title: 'Exact penalty data not supplied',
          message:
              'Portfolio v1 does not expose m/M, s/S, A(penalty), C(forfeit), C(return) or the covenant deadline. The wallet will not estimate them.',
        ),
      );
    }
    return _SectionCard(
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
          _DetailFact(
            label: 'A(penalty)',
            value: plan?.penaltyDue?.display ?? 'Not supplied',
          ),
          _DetailFact(
            label: 'C(forfeit)',
            value: outcome?.forfeit?.display ?? 'Not supplied',
          ),
          _DetailFact(
            label: 'C(return)',
            value: outcome?.returnAmount?.display ?? 'Not supplied',
          ),
          _DetailFact(
            label: 'Deadline',
            value: plan?.deadlineHeight == null
                ? 'Not supplied'
                : 'Block ${plan!.deadlineHeight}${plan.deadlineEstimate == null ? '' : ' · ${plan.deadlineEstimate!.toLocal()}'}',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            loan.role == 'borrower'
                ? 'If the reported trigger is reached, the lender receives C(forfeit). You receive C(return), which may require a collateral-claim signature.'
                : 'If the reported trigger is reached, you receive C(forfeit). The borrower keeps C(return), which may require their signature.',
            style: AppTypography.bodySmall,
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
    final events = <(IconData, String, String)>[
      if (loan.pendingRequest != null)
        (
          Icons.draw_outlined,
          'Signature requested',
          protocolActionLabel(loan.pendingRequest!.action),
        ),
      if (loan.txids.origination != null)
        (
          Icons.add_circle_outline_rounded,
          'Origination transaction',
          'Root covenant created or submitted',
        ),
      for (final node in loan.covenant?.nodes ?? const <ProtocolCovenantNode>[])
        (
          node.isCurrent
              ? Icons.lock_outline_rounded
              : Icons.account_tree_outlined,
          node.isCurrent
              ? 'Covenant current'
              : 'Covenant ${node.status.replaceAll('_', ' ')}',
          node.spentBy == null
              ? 'Generation ${node.index + 1}'
              : protocolActionLabel(node.spentBy!),
        ),
      if (loan.txids.repayment != null)
        (
          Icons.check_circle_outline_rounded,
          'Repayment transaction',
          'Debt closed',
        ),
      if (loan.txids.liquidation != null)
        (
          Icons.gavel_outlined,
          'Default or liquidation transaction',
          'Collateral settlement',
        ),
    ];
    return _SectionCard(
      title: 'Activity',
      child: events.isEmpty
          ? const InfoBanner(
              message: 'No activity events were supplied by the portfolio.',
            )
          : Column(
              children: [
                for (var index = 0; index < events.length; index++) ...[
                  if (index > 0) const Divider(height: AppSpacing.lg),
                  ListRow(
                    icon: events[index].$1,
                    tint: s.liquid,
                    title: events[index].$2,
                    subtitle: events[index].$3,
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
      subtitle: 'Transaction ids, escrow, asset ids and B/n/m/s.',
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      FormCard(title: title, subtitle: subtitle, child: child);
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(color: s.inkSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.bodySmall.copyWith(color: s.ink),
            ),
          ),
        ],
      ),
    );
  }
}
