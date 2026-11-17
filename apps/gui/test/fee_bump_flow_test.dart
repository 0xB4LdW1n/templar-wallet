// The fee-bump dialog draws the bump as the flow: the transaction before and
// after, side by side, from the engine's own reading of the replacement
// PSBT. "Before" is only drawn where it can be worked out exactly from what
// the engine gave — an RBF replacement of the same size, a cancellation, a
// CPFP child of a payment of ours; anything else gets the one diagram.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/history/fee_bump_dialog.dart';
import 'package:templar_wallet/features/history/models/fee_bump_preview.dart';
import 'package:templar_wallet/features/history/models/transaction.dart';
import 'package:templar_wallet/features/psbt/models/psbt_inspection.dart';
import 'package:templar_wallet/shared/widgets/tx_flow.dart';

class _BumpBridge implements WalletBridge {
  _BumpBridge({this.newVsize = 141, this.method = 'rbf'});

  /// 141 is the original's size: equal means the same coins and outputs.
  final int newVsize;

  /// `rbf`, `cancel` or `cpfp`: what the engine answers with.
  final String method;

  bool get _cpfp => method == 'cpfp';

  @override
  Future<FeeBumpPreview> previewFeeBump({
    required String walletId,
    required String txid,
    required String action,
    required String method,
    required double feeRate,
  }) async => FeeBumpPreview(
    method: this.method,
    originalTxid: txid,
    psbtBase64: 'cHNidP8=',
    oldFeeSats: 141,
    oldFeeRate: 1,
    oldVsize: 141,
    newFeeSats: _cpfp ? 1000 : 1128,
    newFeeRate: 8,
    newVsize: _cpfp ? 125 : newVsize,
    extraFeeSats: _cpfp ? 1000 : 987,
    effectiveFeeRate: 8,
    totalFeeSats: _cpfp ? 1141 : 1128,
  );

  /// The payment's coin; a CPFP child spends the payment's change instead.
  static const _coin = PsbtInput(
    outpoint: 'aa11:0',
    amountSats: 50000,
    displayAmount: '0.00050000 BTC',
    isMine: true,
  );
  static const _parentChange = PsbtInput(
    outpoint: 'bb22:1',
    amountSats: 9859,
    displayAmount: '0.00009859 BTC',
    isMine: true,
  );

  static PsbtOutput _mine(int sats) => PsbtOutput(
    address: 'tb1qchange',
    amountSats: sats,
    displayAmount: '$sats sats',
    isMine: true,
  );

  @override
  Future<PsbtInspection> inspectPsbt(String psbtBase64) async => PsbtInspection(
    inputs: [_cpfp ? _parentChange : _coin],
    outputs: switch (method) {
      // The child returns the change less its own fee.
      'cpfp' => [_mine(8859)],
      // Everything comes back, less the new fee.
      'cancel' => [_mine(48872)],
      _ => [
        const PsbtOutput(
          address: 'tb1qrecipient',
          amountSats: 40000,
          displayAmount: '0.00040000 BTC',
          isMine: false,
        ),
        _mine(8872),
      ],
    },
    feeSats: _cpfp ? 1000 : 1128,
    feeDisplay: '${_cpfp ? 1000 : 1128} sats',
    sigsPresent: 0,
    sigsRequired: 1,
    signers: const [],
    policyHint: '',
    rawPsbt: 'cHNidP8=',
    ownershipKnown: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _pending = Transaction(
  txid: 'a' * 64,
  direction: TxDirection.outgoing,
  chain: TxChain.bitcoin,
  // As the engine lists it: the net outflow, 40,000 paid plus 141 of fee.
  amount: '-0.00040141 BTC',
  ticker: 'BTC',
  timestamp: DateTime.fromMillisecondsSinceEpoch(0),
  confirmations: 0,
  feeSats: 141,
  feeRate: 1,
  vsize: 141,
  isReplaceable: true,
  canRbf: true,
  canCpfp: true,
  canCancel: true,
);

Future<void> _openAndPrice(
  WidgetTester t,
  WalletBridge bridge, {
  bool cancel = false,
  bool cpfp = false,
}) async {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    ChangeNotifierProvider<AppState>(
      create: (_) => AppState(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showFeeBumpDialog(
                context,
                bridge: bridge,
                walletId: 'w1',
                transaction: _pending,
                cancel: cancel,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  if (cpfp) {
    await t.tap(find.text('CPFP'));
    await t.pumpAndSettle();
  }
  await t.tap(find.text('Preview fee bump'));
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('an RBF of the same size is drawn before and after', (t) async {
    await _openAndPrice(t, _BumpBridge(newVsize: 141));

    expect(find.text('Before · inputs (1)'), findsOneWidget);
    expect(find.text('After · inputs (1)'), findsOneWidget);
    // The coin and the payment are the same on both sides.
    expect(find.text('0.00050000 BTC'), findsNWidgets(2));
    expect(find.text('0.00040000 BTC'), findsNWidgets(2));
    // Before: the engine's old fee, and the change that fee left —
    // 50,000 − 40,000 − 141.
    expect(find.textContaining('141 sats'), findsWidgets);
    expect(find.text('0.00009859 BTC'), findsOneWidget);
    // After: the replacement's own change, and what the bump moved from
    // one box to the other.
    expect(find.text('0.00008872 BTC'), findsOneWidget);
    expect(find.text('+987 sats'), findsOneWidget);
    expect(find.text('−987 sats'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the pair is two compact diagrams side by side, to one scale', (
    t,
  ) async {
    await _openAndPrice(t, _BumpBridge());

    final flows = t.widgetList<TxFlowDiagram>(find.byType(TxFlowDiagram));
    expect(flows, hasLength(2));
    expect(flows.every((f) => f.compact), isTrue);
    expect(flows.first.scaleSats, flows.last.scaleSats);
    // Before on the left, an arrow, After on the right, on one line.
    final before = t.getTopLeft(find.text('Before · inputs (1)'));
    final after = t.getTopLeft(find.text('After · inputs (1)'));
    final arrow = t.getCenter(find.byIcon(Icons.arrow_forward_outlined));
    expect(before.dy, after.dy);
    expect(before.dx, lessThan(arrow.dx));
    expect(arrow.dx, lessThan(after.dx));
    // To scale: the fee's box grew with the fee.
    double heightOf(String amount) => t
        .getSize(
          find
              .ancestor(of: find.text(amount), matching: find.byType(Tooltip))
              .first,
        )
        .height;
    expect(heightOf('1,128 sats'), greaterThan(heightOf('141 sats')));
  });

  testWidgets('a cancellation shows the payment going and the coins coming '
      'back', (t) async {
    await _openAndPrice(t, _BumpBridge(method: 'cancel'), cancel: true);

    expect(find.text('Before · inputs (1)'), findsOneWidget);
    expect(find.text('After · inputs (1)'), findsOneWidget);
    // Before: the payment (net outflow less its fee), its change, its fee.
    expect(find.text('Outputs (2) and fee'), findsOneWidget);
    expect(find.text('0.00040000 BTC'), findsOneWidget);
    expect(find.text('0.00009859 BTC'), findsOneWidget);
    expect(find.text('141 sats'), findsOneWidget);
    // After: one output, back to this wallet, and the larger fee.
    expect(find.text('Outputs (1) and fee'), findsOneWidget);
    expect(find.text('To you'), findsOneWidget);
    expect(find.text('0.00048872 BTC'), findsOneWidget);
    expect(find.text('1,128 sats'), findsOneWidget);
    expect(find.text('+987 sats'), findsOneWidget);
  });

  testWidgets('a CPFP shows the same payment with less change and both fees', (
    t,
  ) async {
    await _openAndPrice(t, _BumpBridge(method: 'cpfp'), cpfp: true);

    expect(find.text('Before · inputs (1)'), findsOneWidget);
    expect(find.text('After · inputs (1)'), findsOneWidget);
    // The payment's coins and its recipient are the same on both sides.
    expect(find.text('0.00050000 BTC'), findsNWidgets(2));
    expect(find.text('0.00040000 BTC'), findsNWidgets(2));
    // The change the child spends, and what it returns.
    expect(find.text('0.00009859 BTC'), findsOneWidget);
    expect(find.text('0.00008859 BTC'), findsOneWidget);
    expect(find.text('−1,000 sats'), findsOneWidget);
    // One fee before, both after.
    expect(find.text('141 sats'), findsOneWidget);
    expect(find.text('1,141 sats'), findsOneWidget);
    expect(find.text('+1,000 sats'), findsOneWidget);
  });

  testWidgets('a size that is only an estimate apart is still the same '
      'transaction', (t) async {
    // The engine sizes the replacement from its fee and rate: a vbyte or
    // two off the original's exact size, with nothing added or removed.
    await _openAndPrice(t, _BumpBridge(newVsize: 143));

    expect(find.text('Before · inputs (1)'), findsOneWidget);
    expect(find.text('After · inputs (1)'), findsOneWidget);
    expect(find.text('0.00009859 BTC'), findsOneWidget);
  });

  testWidgets('a replacement of another size is drawn alone', (t) async {
    // A different size means a coin was added or the change dropped: the
    // original cannot be redrawn from the replacement, so it is not.
    await _openAndPrice(t, _BumpBridge(newVsize: 209));

    expect(find.textContaining('Before'), findsNothing);
    expect(find.text('Replacement · inputs (1)'), findsOneWidget);
    expect(find.text('0.00009859 BTC'), findsNothing);
    expect(find.text('0.00008872 BTC'), findsOneWidget);
    expect(
      find.textContaining('only the replacement is drawn'),
      findsOneWidget,
    );
  });
}
