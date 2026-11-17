// Pixel comparison against images rendered on macOS: text rasterises
// differently on Linux and Windows, so CI (Ubuntu) skips the `golden` tag.
// Run them on a Mac: `flutter test --tags golden`; regenerate after a
// deliberate visual change with `--update-goldens`.
@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/loans/loan_detail_screen.dart';
import 'package:templar_wallet/features/loans/loan_overview_card.dart';
import 'package:templar_wallet/features/protocol/models/protocol_link.dart';
import 'package:templar_wallet/features/protocol/models/protocol_portfolio.dart';
import 'package:templar_wallet/features/protocol/models/protocol_review_agreement.dart';
import 'package:templar_wallet/features/protocol/protocol_confirm_gate.dart';
import 'package:templar_wallet/features/protocol/protocol_copy.dart';
import 'package:templar_wallet/features/protocol/protocol_transaction_review.dart';
import 'package:templar_wallet/features/psbt/models/pset_inspection.dart';
import 'package:templar_wallet/shared/widgets/hybrid_kit.dart';
import 'package:templar_wallet/shared/widgets/list_rows.dart';
import 'package:templar_wallet/theme/app_scheme.dart';
import 'package:templar_wallet/theme/app_spacing.dart';
import 'package:templar_wallet/theme/app_theme.dart';
import 'package:templar_wallet/theme/app_typography.dart';

import '../test_fonts.dart';

const _principal = ProtocolMoney(ticker: 'rUSDt', amount: '10000');
const _balance = ProtocolMoney(ticker: 'rUSDt', amount: '6500');
const _collateral = ProtocolMoney(ticker: 'LBTC', amount: '0.50000000');

ProtocolLoan _loan({
  required int id,
  String role = 'borrower',
  ProtocolLoanState state = ProtocolLoanState.active,
  String next = 'repay',
  int paid = 2,
  int missed = 0,
  ProtocolPendingRequest? pending,
  bool remainderClaimed = true,
}) => ProtocolLoan(
  id: id,
  ref: 'SQ-$id',
  role: role,
  state: state,
  rawState: state.name,
  principal: _principal,
  collateral: _collateral,
  interest: const ProtocolMoney(ticker: 'rUSDt', amount: '200', rateBps: 200),
  templarFee: const ProtocolMoney(
    ticker: 'rUSDt',
    amount: '50',
    payer: 'borrower',
  ),
  owed: state == ProtocolLoanState.repaid
      ? const ProtocolMoney(ticker: 'rUSDt', amount: '0')
      : _balance,
  blocksLeft: state.isOpen ? 30 : 0,
  dueAtEstimate: DateTime.utc(2026, 11, 6, 13),
  nextAction: ProtocolNextAction(
    kind: next == 'repay'
        ? ProtocolNextKind.repay
        : next == 'claim'
        ? ProtocolNextKind.claim
        : state.isOpen
        ? ProtocolNextKind.unknown
        : ProtocolNextKind.none,
    rawKind: next,
    label: switch (next) {
      'renewal' => 'Renew the covenant after one missed installment',
      'claim' => 'Claim installment payments',
      'none' => 'No action required',
      _ => 'Review the next installment',
    },
  ),
  pendingRequest: pending,
  repaymentPlan: ProtocolRepaymentPlan(
    kind: 'installments',
    nTotal: 6,
    nPaid: paid,
    mMissed: missed,
    mMax: 3,
    step: paid + missed,
    sMax: 6,
    balance: state == ProtocolLoanState.repaid
        ? const ProtocolMoney(ticker: 'rUSDt', amount: '0')
        : _balance,
    regularDue: const ProtocolMoney(ticker: 'rUSDt', amount: '1100'),
    earlyDue: const ProtocolMoney(ticker: 'rUSDt', amount: '6550'),
    penaltyDue: const ProtocolMoney(ticker: 'rUSDt', amount: '1200'),
    deadlineHeight: 1600,
    deadlineEstimate: DateTime.utc(2026, 11, 6, 13),
  ),
  covenant: ProtocolCovenant(
    status: state.name,
    currentTxid: state.isOpen ? 'cc33' : null,
    nodes: [
      const ProtocolCovenantNode(
        index: 0,
        status: 'replaced',
        txid: 'aa11',
        createdBy: 'origination',
        spentBy: 'installment',
        successorTxid: 'bb22',
        balance: ProtocolMoney(ticker: 'rUSDt', amount: '8000'),
      ),
      if (state.isOpen)
        ProtocolCovenantNode(
          index: 1,
          status: 'active',
          txid: 'cc33',
          createdBy: next == 'renewal' ? 'renewal' : 'installment',
          balance: _balance,
          n: paid,
          m: missed,
          s: paid + missed,
        )
      else
        ProtocolCovenantNode(
          index: 1,
          status: state == ProtocolLoanState.repaid ? 'repaid' : 'defaulted',
          txid: 'dd44',
          createdBy: state == ProtocolLoanState.repaid
              ? 'repayment'
              : 'default',
          balance: state == ProtocolLoanState.repaid
              ? const ProtocolMoney(ticker: 'rUSDt', amount: '0')
              : _balance,
        ),
    ],
  ),
  collateralOutcome: ProtocolCollateralOutcome(
    locked: state.isOpen ? _collateral : null,
    forfeit: state == ProtocolLoanState.defaulted
        ? const ProtocolMoney(ticker: 'LBTC', amount: '0.35')
        : null,
    returnAmount: state == ProtocolLoanState.defaulted
        ? const ProtocolMoney(ticker: 'LBTC', amount: '0.15')
        : state == ProtocolLoanState.repaid
        ? _collateral
        : null,
    returnClaimed: state == ProtocolLoanState.defaulted
        ? remainderClaimed
        : true,
  ),
);

ProtocolPortfolio _portfolio(ProtocolLoan loan) => ProtocolPortfolio(
  version: 1,
  site: 'Templar Protocol',
  network: 'liquid-regtest',
  tipHeight: 1570,
  asOf: DateTime.utc(2026, 11, 6, 12),
  wallet: const ProtocolPortfolioWallet(
    label: 'Demo wallet',
    escrowFingerprint: '0bae4c8d',
  ),
  loans: [loan],
  offers: const [],
);

Widget _page({
  required Widget child,
  required bool light,
  String? title,
  Widget? bottom,
}) => _app(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: light ? AppTheme.light() : AppTheme.dark(),
    home: Builder(
      builder: (context) => Scaffold(
        body: PageBackground.flat(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(AppSpacing.pagePadding(context)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (title != null) ...[
                      Text(
                        title,
                        style: AppTypography.pageTitleOf(
                          context,
                        ).copyWith(color: AppScheme.of(context).ink),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                    child,
                  ],
                ),
              ),
            ),
          ),
        ),
        bottomNavigationBar: bottom,
      ),
    ),
  ),
);

/// Loan figures sit behind the privacy mask, which reads [AppState].
Widget _app(Widget app) =>
    ChangeNotifierProvider(create: (_) => AppState(), child: app);

/// The Material icon font, so the documentation images show real glyphs
/// rather than the test harness's boxes. Absent outside a Flutter checkout:
/// the images then fall back to boxes, as before.
Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final file = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (!file.existsSync()) return;
  final bytes = file.readAsBytesSync();
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
}

Future<void> _golden(
  WidgetTester tester, {
  required Size size,
  required Widget child,
  required String file,
  bool phone = false,
}) async {
  // The phone layouts only exist on a mobile platform; the seam lets the
  // host lay them out.
  AppLayout.debugMobileOverride = phone ? true : null;
  addTearDown(() => AppLayout.debugMobileOverride = null);
  await warmUpWalletFonts(tester);
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('../../../../docs/images/templar_lend/$file'),
  );
}

ProtocolRequest _request(String action) {
  final role = action == 'renewal' || action == 'default'
      ? 'lender'
      : 'borrower';
  return ProtocolRequest(
    version: 1,
    kind: 'sign',
    site: 'Templar Protocol',
    network: 'liquid-regtest',
    nonce: 'demo',
    callback: Uri.parse('http://127.0.0.1/signed'),
    expiresAt: 2000000000,
    id: 'request-$action',
    action: action,
    loanRef: 'SQ-42',
    summary: ProtocolSummary(
      role: role,
      lines: [
        if (action == 'origination')
          const ProtocolSummaryLine(
            label: 'You receive',
            amount: '10,000 rUSDt',
          ),
        if (action == 'installment')
          const ProtocolSummaryLine(label: 'You send', amount: '1,100 rUSDt'),
        if (action == 'default')
          const ProtocolSummaryLine(label: 'You receive', amount: '0.35 LBTC'),
        if (action != 'default')
          const ProtocolSummaryLine(
            label: 'Collateral remains locked',
            amount: '0.5 LBTC',
          ),
        if (action == 'renewal') ...const [
          ProtocolSummaryLine(label: 'Missed installments m/M', amount: '1/3'),
          ProtocolSummaryLine(label: 'Steps s/S', amount: '3/6'),
          ProtocolSummaryLine(label: 'A(penalty)', amount: '1,200 rUSDt'),
          ProtocolSummaryLine(label: 'Deadline block', amount: '1600'),
        ],
        if (action == 'default') ...const [
          ProtocolSummaryLine(
            label: 'Trigger',
            amount: '3 consecutive missed installments',
          ),
          ProtocolSummaryLine(label: 'C(forfeit)', amount: '0.35 LBTC'),
          ProtocolSummaryLine(label: 'C(return)', amount: '0.15 LBTC'),
          ProtocolSummaryLine(label: 'Deadline block', amount: '1600'),
        ],
        const ProtocolSummaryLine(
          label: 'Network fee',
          amount: '0.00000024 LBTC',
        ),
      ],
    ),
    pset: 'cHNldP8B',
  );
}

PsetInspection _inspection(String action) => PsetInspection(
  feeSats: 24,
  feeDisplay: '0.00000024 LBTC',
  recipients: const [],
  sigsHave: 0,
  sigsNeeded: 1,
  signersPresent: const [],
  signersMissing: const [],
  canFinalize: false,
  rawPset: 'cHNldP8B',
  netChangeLines: [
    if (action == 'origination')
      const PsetNetChange(
        assetId: 'principal',
        ticker: 'rUSDt',
        amountSats: 1000000000000,
        displayAmount: '+10,000 rUSDt',
      ),
    if (action == 'installment')
      const PsetNetChange(
        assetId: 'principal',
        ticker: 'rUSDt',
        amountSats: -110000000000,
        displayAmount: '-1,100 rUSDt',
      ),
    if (action == 'default')
      const PsetNetChange(
        assetId: 'lbtc',
        ticker: 'LBTC',
        amountSats: 35000000,
        displayAmount: '+0.35 LBTC',
      ),
  ],
  outputs: action == 'default'
      ? const []
      : const [
          PsetOutput(
            index: 0,
            kind: 'escrow',
            scriptType: 'p2wsh',
            ticker: 'LBTC',
            amountSats: 50000000,
            displayAmount: '0.50000000 LBTC',
          ),
        ],
);

Widget _signReview(String action, {bool light = false}) {
  final request = _request(action);
  final inspection = _inspection(action);
  final agreement = ProtocolReviewAgreement.compare(request, inspection);
  // The request screen's own pieces, in its order: the heading, the review,
  // and the consent step — pinned under the page on a phone.
  final phone = action == 'installment';
  final gate = ProtocolConfirmGate(
    statement:
        'I reviewed the amounts computed by this wallet, the covenant effect and the fee',
    buttonLabel: 'Sign ${ProtocolCopy.english.action(action).toLowerCase()}',
    onConfirm: () {},
    cancelLabel: 'Cancel request',
    onCancel: () {},
    disabledReason: 'Signing is blocked: the site and the wallet do not agree',
  );
  return _page(
    light: light,
    bottom: phone ? _Pinned(child: gate) : null,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.formMaxWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ProtocolRequestHeading(
              title: '${ProtocolCopy.english.action(action)} · SQ-42',
              site: request.site,
              network: request.network,
              origin: 'http://127.0.0.1:8080',
              walletName: 'Demo wallet',
            ),
            ProtocolTransactionReview(
              request: request,
              inspection: inspection,
              agreement: agreement,
            ),
            if (!phone) ...[const SizedBox(height: AppSpacing.xl), gate],
          ],
        ),
      ),
    ),
  );
}

/// The phone's pinned consent bar, as the request screen draws it.
class _Pinned extends StatelessWidget {
  const _Pinned({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = AppScheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.edge)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: child,
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await loadTestFonts();
    await _loadIcons();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('golden overview dark desktop', (tester) async {
    final due = _loan(id: 42);
    final renewal = _loan(id: 43, role: 'lender', next: 'renewal', missed: 1);
    await _golden(
      tester,
      size: const Size(1200, 1050),
      file: 'overview-dark-desktop.png',
      child: _page(
        light: false,
        title: 'Loans',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const ListSectionLabel(label: 'Action required · 2'),
            LoanList(
              children: [
                LoanOverviewCard(
                  loan: due,
                  updatedAt: DateTime.utc(2026, 11, 6, 12),
                  now: DateTime.utc(2026, 11, 6, 12, 2),
                  primaryEmphasis: true,
                  onPrimary: () {},
                  onOpen: () {},
                ),
                LoanOverviewCard(
                  loan: renewal,
                  updatedAt: DateTime.utc(2026, 11, 6, 12),
                  now: DateTime.utc(2026, 11, 6, 12, 2),
                  onPrimary: () {},
                  onOpen: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('golden borrower due light mobile', (tester) async {
    final loan = _loan(id: 42);
    await _golden(
      tester,
      size: const Size(390, 844),
      file: 'borrower-due-light-mobile.png',
      phone: true,
      child: _page(
        light: true,
        title: 'Installment due',
        child: LoanList(
          children: [
            LoanOverviewCard(
              loan: loan,
              updatedAt: DateTime.utc(2026, 11, 6, 12),
              now: DateTime.utc(2026, 11, 6, 12, 2),
              primaryEmphasis: true,
              onPrimary: () {},
              onOpen: () {},
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('golden lender renewal', (tester) async {
    final loan = _loan(id: 43, role: 'lender', next: 'renewal', missed: 1);
    await _golden(
      tester,
      size: const Size(900, 720),
      file: 'lender-renewal-dark.png',
      child: _page(
        light: false,
        title: 'Renewal after missed installment',
        child: LoanList(
          children: [
            LoanOverviewCard(
              loan: loan,
              updatedAt: DateTime.utc(2026, 11, 6, 12),
              now: DateTime.utc(2026, 11, 6, 12, 2),
              primaryEmphasis: true,
              onPrimary: () {},
              onOpen: () {},
            ),
          ],
        ),
      ),
    );
  });

  testWidgets('golden partial repayment covenant', (tester) async {
    final loan = _loan(id: 44, paid: 2);
    await _golden(
      tester,
      size: const Size(1100, 1900),
      file: 'partial-repayment-detail.png',
      child: _app(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(),
          home: LoanDetailScreen(
            siteKey: 'demo',
            loanId: loan.id,
            loan: loan,
            portfolio: _portfolio(loan),
            now: DateTime.utc(2026, 11, 6, 12, 2),
          ),
        ),
      ),
    );
  });

  testWidgets('golden default penalty', (tester) async {
    final loan = _loan(
      id: 45,
      state: ProtocolLoanState.defaulted,
      next: 'none',
      paid: 2,
      missed: 3,
      remainderClaimed: false,
    );
    await _golden(
      tester,
      size: const Size(1100, 1900),
      file: 'default-penalty-detail.png',
      child: _app(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: LoanDetailScreen(
            siteKey: 'demo',
            loanId: loan.id,
            loan: loan,
            portfolio: _portfolio(loan),
            now: DateTime.utc(2026, 11, 6, 12, 2),
          ),
        ),
      ),
    );
  });

  testWidgets('golden closed loan', (tester) async {
    final loan = _loan(
      id: 46,
      state: ProtocolLoanState.repaid,
      next: 'none',
      paid: 6,
    );
    await _golden(
      tester,
      size: const Size(900, 700),
      file: 'closed-loan-dark.png',
      child: _page(
        light: false,
        title: 'Completed',
        child: LoanList(
          children: [
            LoanOverviewCard(
              loan: loan,
              updatedAt: DateTime.utc(2026, 11, 6, 12),
              now: DateTime.utc(2026, 11, 6, 12, 2),
              onPrimary: () {},
              onOpen: () {},
            ),
          ],
        ),
      ),
    );
  });

  for (final action in ['origination', 'installment', 'renewal', 'default']) {
    testWidgets('golden sign $action', (tester) async {
      await _golden(
        tester,
        size: action == 'installment'
            ? const Size(390, 1100)
            : const Size(900, 1050),
        file:
            'sign-$action-${action == 'installment' ? 'mobile' : 'desktop'}.png',
        phone: action == 'installment',
        child: _signReview(action, light: action == 'origination'),
      );
    });
  }
}
