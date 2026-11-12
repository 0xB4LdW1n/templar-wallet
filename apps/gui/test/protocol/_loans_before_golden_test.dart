import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/loans/loan_card.dart';
import 'package:templar_wallet/features/protocol/models/protocol_portfolio.dart';
import 'package:templar_wallet/theme/app_theme.dart';

import '../test_fonts.dart';

void main() {
  setUpAll(loadTestFonts);

  testWidgets('capture loans before redesign', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await warmUpWalletFonts(tester);
    tester.view
      ..physicalSize = const Size(1200, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loan = ProtocolLoan(
      id: 42,
      ref: 'SQ-42',
      role: 'borrower',
      state: ProtocolLoanState.active,
      rawState: 'active',
      principal: const ProtocolMoney(ticker: 'rUSDt', amount: '10000'),
      collateral: const ProtocolMoney(ticker: 'LBTC', amount: '0.5'),
      interest: const ProtocolMoney(
        ticker: 'rUSDt',
        amount: '200',
        rateBps: 200,
      ),
      templarFee: const ProtocolMoney(
        ticker: 'rUSDt',
        amount: '50',
        payer: 'borrower',
      ),
      owed: const ProtocolMoney(ticker: 'rUSDt', amount: '10200'),
      startHeight: 118,
      termHeight: 168,
      blocksLeft: 50,
      dueAtEstimate: DateTime.utc(2026, 11, 6, 12),
      nextAction: ProtocolNextAction(
        kind: ProtocolNextKind.sign,
        rawKind: 'sign',
        label: 'Sign the repayment of SQ-42',
        url: Uri.parse('https://host/loans/42'),
      ),
      pendingRequest: ProtocolPendingRequest(
        id: 'req_42',
        action: 'installment',
        link: Uri.parse(
          'templar://sign?url=https%3A%2F%2Fhost%2Freq_42&nonce=n',
        ),
        expiresAt: DateTime.utc(2026, 11, 6, 13),
      ),
      txids: const ProtocolLoanTxids(origination: 'aa11'),
      escrowAddress: 'el1qqescrow',
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(),
        home: ChangeNotifierProvider(
          create: (_) => AppState(),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(32),
              child: SingleChildScrollView(
                child: LoanCard(loan: loan, tipHeight: 143, onSign: (_) {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../../../../docs/images/loans-before.png'),
    );
  });
}
