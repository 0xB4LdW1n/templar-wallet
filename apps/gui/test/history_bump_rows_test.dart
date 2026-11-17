// A sped-up payment in Activity is one row and one detail window, whatever
// the chain holds for it. What is offered follows what is possible: a
// payment that came in can only be sped up by a child, and is never
// cancellable; once its fee was raised the "Speed up" slot is the filled
// yellow "Sped up", and the detail spells the bump out.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/history/history_screen.dart';
import 'package:templar_wallet/features/history/models/transaction.dart';
import 'package:templar_wallet/features/history/speed_up_button.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';
import 'package:templar_wallet/shared/widgets/buttons.dart';
import 'package:templar_wallet/theme/app_scheme.dart';

final _parent = 'af2395${'0' * 52}0bb115';
final _child = '95b0fa${'1' * 52}8b5fa2';

class _Bridge implements WalletBridge {
  _Bridge({this.bumped = false, this.confirmations = 0});

  /// The CPFP child is on the chain too.
  final bool bumped;
  final int confirmations;

  @override
  Future<List<Transaction>> listActivity(
    String walletId, {
    String? chain,
    String? asset,
  }) async => [
    Transaction(
      txid: _parent,
      direction: TxDirection.incoming,
      chain: TxChain.bitcoin,
      amount: '+0.00141193 BTC',
      ticker: 'BTC',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        confirmations > 0 ? 1790000000000 : 0,
      ),
      confirmations: confirmations,
      fee: '141 sats',
      feeSats: 141,
      feeRate: 1,
      vsize: 141,
      // Not ours to replace; a child can pay for it until one has.
      canCpfp: !bumped && confirmations == 0,
      feeBumpUnavailableReason: bumped
          ? 'No replaceable input or spendable child output is available'
          : null,
    ),
    if (bumped)
      Transaction(
        txid: _child,
        direction: TxDirection.self,
        chain: TxChain.bitcoin,
        amount: '-0.00001787 BTC',
        ticker: 'BTC',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          confirmations > 0 ? 1790000000000 : 0,
        ),
        confirmations: confirmations,
        fee: '1787 sats',
        feeSats: 1787,
        isReplaceable: true,
        canRbf: confirmations == 0,
        canCancel: confirmations == 0,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(WalletBridge bridge, {String? openTxid}) =>
    ChangeNotifierProvider<AppState>(
      create: (_) =>
          AppState()..setActiveWallet('w1', name: 'Wallet', type: 'Software'),
      child: MaterialApp(
        home: HistoryScreen(bridge: bridge, openTxid: openTxid),
      ),
    );

Future<void> _pump(WidgetTester t, Widget app) async {
  t.view.physicalSize = const Size(1400, 1400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(app);
  await t.pumpAndSettle();
}

/// The record the app keeps when it broadcasts a CPFP child.
Map<String, Object> _bumpRecord() => {
  'fee_bump_records_v1': json.encode([
    {
      'wallet_id': 'w1',
      'original_txid': _parent,
      'replacement_txid': _child,
      'method': 'cpfp',
      'target_fee_rate': 12.5,
      'new_fee_sats': 1787,
      'new_fee_rate': 14.3,
      'created_at': 0,
    },
  ]),
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a pending payment that came in offers "Speed up" alone', (
    t,
  ) async {
    await _pump(t, _screen(_Bridge()));

    expect(find.byType(SpeedUpButton), findsOneWidget);
    // It is not ours to cancel: no Cancel is drawn at all.
    expect(find.widgetWithText(GhostButton, 'Cancel'), findsNothing);

    // And the only way is a child: the dialog offers no method to choose.
    await t.tap(find.text('Speed up'));
    await t.pumpAndSettle();
    expect(find.text('Speed up transaction'), findsOneWidget);
    expect(find.text('RBF'), findsNothing);
    expect(find.text('Method'), findsNothing);
  });

  testWidgets('sped up with CPFP, parent and child are one row', (t) async {
    SharedPreferences.setMockInitialValues(_bumpRecord());
    await _pump(t, _screen(_Bridge(bumped: true)));

    // One row: the payment, under its own title and amount.
    expect(find.text('Received'), findsOneWidget);
    expect(find.textContaining('CPFP child'), findsNothing);
    expect(find.textContaining('0.00001787'), findsNothing);
    expect(find.textContaining('0.00141193'), findsOneWidget);
    // The row says what was done to it and what it cost.
    expect(find.textContaining('CPFP · fee 1,787 sats'), findsOneWidget);

    // The "Speed up" slot is the filled yellow "Sped up" with its tick; no
    // second "Speed up", no Cancel.
    expect(find.byType(SpedUpButton), findsOneWidget);
    expect(find.byType(SpeedUpButton), findsNothing);
    expect(find.widgetWithText(GhostButton, 'Cancel'), findsNothing);
    final s = AppScheme.of(t.element(find.byType(HistoryScreen)));
    final fill = t
        .widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(SpedUpButton),
            matching: find.byType(AnimatedContainer),
          ),
        )
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .first;
    expect(fill.color, s.boost);
    expect(
      find.descendant(
        of: find.byType(SpedUpButton),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('"Sped up" opens the one window that spells the bump out', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues(_bumpRecord());
    await _pump(t, _screen(_Bridge(bumped: true)));

    await t.tap(find.byType(SpedUpButton));
    await t.pumpAndSettle();

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Fee raised with CPFP'), findsOneWidget);
    expect(find.text('Child transaction'), findsOneWidget);
    expect(find.textContaining('1,787 sats'), findsWidgets);
    expect(find.textContaining('12.50 sat/vB'), findsOneWidget);
    // Both txids are in the window: the payment's and the child's.
    expect(find.text('Transaction ID'), findsOneWidget);
    expect(find.textContaining('95b0fa'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('confirmed, it is still one row, marked as sped up', (t) async {
    SharedPreferences.setMockInitialValues(_bumpRecord());
    await _pump(t, _screen(_Bridge(bumped: true, confirmations: 3)));

    expect(find.text('Received'), findsOneWidget);
    expect(find.textContaining('CPFP child'), findsNothing);
    expect(find.textContaining('0.00001787'), findsNothing);
    expect(find.textContaining('CPFP · fee 1,787 sats'), findsOneWidget);
    // Nothing left to do to it: no fee buttons.
    expect(find.byType(SpedUpButton), findsNothing);
    expect(find.byType(SpeedUpButton), findsNothing);
    // The double bolt marks the row.
    expect(find.byType(DoubleBolt), findsOneWidget);
  });

  testWidgets('asked for a transaction, the screen opens its detail', (
    t,
  ) async {
    await _pump(t, _screen(_Bridge(), openTxid: _parent));

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Transaction ID'), findsOneWidget);
    expect(find.textContaining('af2395'), findsWidgets);
  });

  testWidgets('asked for the child of a bump, it opens the payment', (t) async {
    SharedPreferences.setMockInitialValues(_bumpRecord());
    await _pump(t, _screen(_Bridge(bumped: true), openTxid: _child));

    expect(find.byType(AppDialog), findsOneWidget);
    expect(find.text('Fee raised with CPFP'), findsOneWidget);
  });
}
