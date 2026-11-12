import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/history/history_screen.dart';
import 'package:templar_wallet/features/history/models/transaction.dart';
import 'package:templar_wallet/theme/app_colors.dart';

class _ActivityBridge implements WalletBridge {
  @override
  Future<List<Transaction>> listActivity(
    String walletId, {
    String? chain,
    String? asset,
  }) async => [
    Transaction(
      txid: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      direction: TxDirection.outgoing,
      chain: TxChain.bitcoin,
      amount: '-0.001 BTC',
      ticker: 'BTC',
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      confirmations: 0,
      fee: '141 sats',
      feeSats: 141,
      feeRate: 1,
      vsize: 141,
      isReplaceable: true,
      canRbf: true,
      canCpfp: true,
      canCancel: true,
    ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _screen(WalletBridge bridge) => ChangeNotifierProvider<AppState>(
  create: (_) =>
      AppState()..setActiveWallet('w1', name: 'Wallet', type: 'Software'),
  child: MaterialApp(home: HistoryScreen(bridge: bridge)),
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('pending Bitcoin row is grey and exposes direct fee actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_screen(_ActivityBridge()));
    await tester.pumpAndSettle();

    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Speed up'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);

    final pending = tester.widget<Text>(find.text('Pending'));
    expect(pending.style?.color, isNot(AppColors.warning));

    await tester.tap(find.text('Speed up'));
    await tester.pumpAndSettle();
    expect(find.text('Speed up transaction'), findsOneWidget);
    expect(find.text('RBF'), findsOneWidget);
    expect(find.text('CPFP'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Attempt cancellation'), findsOneWidget);
    expect(
      find.textContaining('higher-fee replacement paying your own wallet'),
      findsOneWidget,
    );
  });
}
