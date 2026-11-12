import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:templar_wallet/features/loans/covenant_timeline.dart';
import 'package:templar_wallet/features/loans/loan_detail_screen.dart';
import 'package:templar_wallet/features/loans/loan_overview_card.dart';
import 'package:templar_wallet/features/protocol/models/protocol_portfolio.dart';
import 'package:templar_wallet/shared/widgets/buttons.dart';
import 'package:templar_wallet/theme/app_theme.dart';

const _balance = ProtocolMoney(ticker: 'rUSDt', amount: '6500');
const _collateral = ProtocolMoney(ticker: 'LBTC', amount: '0.5');

ProtocolLoan _loan({
  int id = 42,
  String role = 'borrower',
  ProtocolLoanState state = ProtocolLoanState.active,
  ProtocolPendingRequest? pending,
  bool withPlan = true,
  bool returnClaimed = true,
}) => ProtocolLoan(
  id: id,
  ref: 'SQ-$id',
  role: role,
  state: state,
  rawState: state.name,
  principal: const ProtocolMoney(ticker: 'rUSDt', amount: '10000'),
  collateral: _collateral,
  owed: _balance,
  blocksLeft: 30,
  dueAtEstimate: DateTime.utc(2026, 11, 6, 13),
  nextAction: ProtocolNextAction(
    kind: state == ProtocolLoanState.active
        ? ProtocolNextKind.repay
        : ProtocolNextKind.none,
    rawKind: state == ProtocolLoanState.active ? 'repay' : 'none',
    label: state == ProtocolLoanState.active
        ? 'Review the next installment'
        : 'Loan complete',
  ),
  pendingRequest: pending,
  repaymentPlan: withPlan
      ? ProtocolRepaymentPlan(
          kind: 'installments',
          nTotal: 6,
          nPaid: 2,
          mMissed: 1,
          mMax: 3,
          step: 2,
          sMax: 6,
          balance: _balance,
          regularDue: const ProtocolMoney(ticker: 'rUSDt', amount: '1100'),
          penaltyDue: const ProtocolMoney(ticker: 'rUSDt', amount: '1200'),
          deadlineHeight: 1600,
          deadlineEstimate: DateTime.utc(2026, 11, 6, 13),
        )
      : null,
  covenant: withPlan
      ? const ProtocolCovenant(
          status: 'active',
          currentTxid: 'cc33',
          nodes: [
            ProtocolCovenantNode(
              index: 0,
              status: 'replaced',
              txid: 'aa11',
              spentBy: 'installment',
              successorTxid: 'bb22',
              balance: ProtocolMoney(ticker: 'rUSDt', amount: '8000'),
            ),
            ProtocolCovenantNode(
              index: 1,
              status: 'active',
              txid: 'bb22',
              createdBy: 'installment',
              balance: _balance,
            ),
          ],
        )
      : null,
  collateralOutcome: withPlan
      ? ProtocolCollateralOutcome(
          locked: _collateral,
          forfeit: ProtocolMoney(ticker: 'LBTC', amount: '0.35'),
          returnAmount: ProtocolMoney(ticker: 'LBTC', amount: '0.15'),
          returnClaimed: returnClaimed,
        )
      : null,
);

ProtocolPendingRequest _request({required DateTime expiresAt}) =>
    ProtocolPendingRequest(
      id: 'req-42',
      action: 'installment',
      link: Uri.parse('templar://sign?url=https%3A%2F%2Fhost%2Freq-42&nonce=n'),
      expiresAt: expiresAt,
    );

Widget _host(Widget child, {bool light = false}) => MaterialApp(
  theme: light ? AppTheme.light() : AppTheme.dark(),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  ),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('overview remains concise and overflow-free at target widths', (
    tester,
  ) async {
    for (final width in [360.0, 768.0, 1440.0]) {
      tester.view
        ..physicalSize = Size(width, 1000)
        ..devicePixelRatio = 1;
      await tester.pumpWidget(
        _host(
          LoanOverviewCard(
            loan: _loan(),
            updatedAt: DateTime.utc(2026, 11, 6, 12),
            primaryEmphasis: true,
            onPrimary: () {},
            onOpen: () {},
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('SQ-42'), findsOneWidget);
      expect(find.text('2 of 6 installments paid'), findsOneWidget);
      expect(find.byType(PrimaryButton), findsOneWidget);
    }
    addTearDown(tester.view.reset);
  });

  testWidgets('pending and expired requests have distinct safe states', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(768, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _host(
        Column(
          children: [
            LoanOverviewCard(
              loan: _loan(
                id: 1,
                pending: _request(expiresAt: DateTime.utc(2026, 11, 6, 13)),
              ),
              now: DateTime.utc(2026, 11, 6, 12),
              updatedAt: DateTime.utc(2026, 11, 6, 12),
              primaryEmphasis: true,
              onPrimary: () {},
              onOpen: () {},
            ),
            LoanOverviewCard(
              loan: _loan(
                id: 2,
                pending: _request(expiresAt: DateTime.utc(2026, 11, 6, 11)),
              ),
              now: DateTime.utc(2026, 11, 6, 12),
              updatedAt: DateTime.utc(2026, 11, 6, 12),
              stale: true,
              onPrimary: () {},
              onOpen: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Review and sign'), findsOneWidget);
    expect(find.textContaining('Signing request expired'), findsOneWidget);
    expect(find.text('STALE DATA'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsOneWidget);
  });

  testWidgets('a collateral remainder is the current action, not history', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 1200)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loan = _loan(
      state: ProtocolLoanState.defaulted,
      returnClaimed: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LoanDetailScreen(
          siteKey: 'site',
          loanId: loan.id,
          loan: loan,
          now: DateTime.utc(2026, 11, 6, 12),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Your collateral remainder is ready'), findsOneWidget);
    expect(find.text('Claim collateral remainder'), findsOneWidget);
    expect(
      find.text(
        'Claims the collateral remainder already assigned to the borrower.',
      ),
      findsOneWidget,
    );
    expect(find.text('No action required'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail exposes human sections and technical facts on demand', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1200, 4000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loan = _loan(role: 'lender');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: LoanDetailScreen(
          siteKey: 'site',
          loanId: loan.id,
          loan: loan,
          portfolio: ProtocolPortfolio(
            version: 1,
            site: 'Templar Protocol',
            network: 'liquid-regtest',
            tipHeight: 1570,
            asOf: DateTime.utc(2026, 11, 6, 12),
            wallet: const ProtocolPortfolioWallet(
              label: 'Lender',
              escrowFingerprint: '0bae4c8d',
            ),
            loans: [loan],
            offers: const [],
          ),
        ),
      ),
    );
    await tester.pump();

    for (final heading in [
      'Now',
      'Loan summary',
      'Installment plan',
      'Covenant lifecycle',
      'Risk and penalty',
      'Activity',
      'Technical details',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }
    expect(find.text('Lender'), findsWidgets);
    expect(find.text('Covenant spent and replaced'), findsOneWidget);
    expect(find.text('Successor covenant active'), findsOneWidget);
    expect(find.text('cc33'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('cc33'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed and default covenant states remain explicit', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loan = ProtocolLoan(
      id: 9,
      ref: 'SQ-9',
      role: 'borrower',
      state: ProtocolLoanState.defaulted,
      rawState: 'defaulted',
      covenant: const ProtocolCovenant(
        status: 'defaulted',
        nodes: [
          ProtocolCovenantNode(index: 0, status: 'pending'),
          ProtocolCovenantNode(index: 1, status: 'active'),
          ProtocolCovenantNode(index: 2, status: 'replaced'),
          ProtocolCovenantNode(index: 3, status: 'repaid'),
          ProtocolCovenantNode(index: 4, status: 'defaulted'),
        ],
      ),
    );
    await tester.pumpWidget(_host(CovenantTimeline(loan: loan)));
    await tester.pump();

    for (final state in [
      'PENDING',
      'CURRENT',
      'REPLACED',
      'REPAID',
      'DEFAULTED',
    ]) {
      expect(find.text(state), findsOneWidget);
    }
    expect(find.text('Covenant destroyed without successor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('portfolio v1 fallback does not invent installment state', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(CovenantTimeline(loan: _loan(withPlan: false)), light: true),
    );
    expect(find.text('Covenant history not supplied'), findsOneWidget);
    expect(find.textContaining('will not reconstruct'), findsOneWidget);
  });
}
