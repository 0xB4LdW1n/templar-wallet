// The Peg screen on the real peg: who moves the coins is said first; Fund and
// Claim are the only signing steps and each asks twice (what will be signed,
// then the app password); refusals are explained by their engine tag; final
// and legacy orders offer nothing to pay.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/dashboard/models/dashboard_data.dart';
import 'package:templar_wallet/features/peg/models/peg_models.dart';
import 'package:templar_wallet/features/test_coins/test_coins.dart';
import 'package:templar_wallet/features/peg/peg_screen.dart';
import 'package:templar_wallet/features/receive/models/address_info.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';

Map<String, dynamic> _order({
  String id = 'pg_00000001',
  String direction = 'in',
  String status = 'awaiting_deposit',
  String provider = 'native',
  int confirmations = 0,
  bool simulated = false,
  String? lastError,
  String? txidDeposit,
}) => {
  'order_id': id,
  'wallet_id': 'w1',
  'direction': direction,
  'status': status,
  'deposit_address': direction == 'in'
      ? '2MwZFDfh4yR5ahSbq2mqgzhv77kPxPQELUY'
      : '',
  'deposit_expected_sats': 100000,
  'payout_address': direction == 'in'
      ? 'el1qqtcmkssvvujtewm895nz963ht02fhzjvtf8v25gc5lad5kjr6levtrxmw6q70xhwj9j65hm5v432svzsdk7mq3va922gxrx7v'
      : 'bcrt1q3ndhdq08nthfzed2ta6x2c4gxpgxm0dstk2dfc',
  'payout_expected_sats': direction == 'in' ? 99965 : 100000,
  'created_at': 1794877403,
  'updated_at': 1794877403,
  'eta_minutes': 21,
  'txid_deposit': txidDeposit,
  'txid_payout': null,
  'txid_claim': null,
  'simulated': simulated,
  'provider': provider,
  'confirmations': confirmations,
  'confirmations_required': 2,
  'deposit_received_sats': null,
  'valid_until_liquid_height': direction == 'in' && provider == 'native'
      ? 189
      : null,
  'last_error': lastError,
  'expires_at': null,
  'status_history': [
    {'status': status, 'at': 1794877403},
  ],
};

/// Answers the peg methods from a script and records what was asked.
class _PegBridge implements WalletBridge {
  _PegBridge({
    List<Map<String, dynamic>> orders = const [],
    this.provider = 'native',
    this.startError,
    this.fundError,
    this.claimError,
  }) : orders = [...orders];

  final List<Map<String, dynamic>> orders;
  final String provider;
  final String? startError;
  final String? fundError;
  final String? claimError;
  final calls = <String>[];

  Map<String, dynamic> _find(String id) =>
      orders.firstWhere((o) => o['order_id'] == id);

  @override
  Future<List<PegOrder>> pegList(String walletId) async {
    calls.add('list');
    return orders.map(PegOrder.fromJson).toList();
  }

  @override
  Future<PegQuote> pegQuote(String direction, int amountSats) async =>
      PegQuote.fromJson({
        'direction': direction,
        'amount_sats': amountSats,
        'rate': 1.0,
        'service_fee_sats': provider == 'sideswap' ? amountSats ~/ 100 : 0,
        'network_fee_sats': 35,
        'receive_sats': amountSats - 35,
        'min_sats': 10000,
        'max_sats': 2100000000000000,
        'eta_minutes': 21,
        'simulated': false,
        'provider': provider,
        'confirmations_required': 2,
        'network_fee_included': true,
      });

  @override
  Future<PegOrder> pegStart(
    String walletId,
    String direction,
    int amountSats,
    String payoutAddress,
  ) async {
    calls.add('start');
    if (startError != null) throw Exception('wallet-ffi: $startError');
    final o = _order(id: 'pg_new00001', direction: direction);
    orders.insert(0, o);
    return PegOrder.fromJson(o);
  }

  @override
  Future<PegOrder> pegFund(String orderId, {double? feeRate}) async {
    calls.add('fund $orderId');
    if (fundError != null) throw Exception('wallet-ffi: $fundError');
    final o = _find(orderId)
      ..['status'] = 'deposit_seen'
      ..['txid_deposit'] = 'ab' * 32;
    return PegOrder.fromJson(o);
  }

  @override
  Future<PegOrder> pegClaim(String orderId) async {
    calls.add('claim $orderId');
    if (claimError != null) throw Exception('wallet-ffi: $claimError');
    final o = _find(orderId)
      ..['status'] = 'settling'
      ..['txid_claim'] = 'cd' * 32;
    return PegOrder.fromJson(o);
  }

  @override
  Future<PegOrder> pegCancel(String orderId) async {
    calls.add('cancel $orderId');
    return PegOrder.fromJson(_find(orderId)..['status'] = 'cancelled');
  }

  @override
  Future<AddressInfo> generateReceiveAddress(
    String walletId,
    String asset, {
    bool fresh = false,
  }) async => AddressInfo(
    address: asset == 'BTC'
        ? 'bcrt1q3ndhdq08nthfzed2ta6x2c4gxpgxm0dstk2dfc'
        : 'el1qqtcmkssvvujtewm895nz963ht02fhzjvtf8v25gc5lad5kjr6levtrxmw6q70xhwj9j65hm5v432svzsdk7mq3va922gxrx7v',
    index: 0,
    asset: asset,
  );

  /// BTC and L-BTC in this wallet (null = no summary at all).
  int? btcSats;
  int lbtcSats = 0;
  final faucet = <String>[];

  @override
  Future<DashboardData> getWalletSummary(String walletId) async {
    final btc = btcSats;
    if (btc == null) throw Exception('wallet-ffi: no summary');
    return DashboardData(
      walletId: walletId,
      walletName: 'Throwaway',
      totalBalanceDisplay: '',
      syncState: 'synced',
      recentActivity: const [],
      assets: [
        AssetBalance(
          assetId: 'BTC',
          ticker: 'BTC',
          name: 'Bitcoin',
          amount: btc,
          displayAmount: '',
        ),
        AssetBalance(
          assetId: 'b0' * 32,
          ticker: 'LBTC',
          name: 'Liquid Bitcoin',
          amount: lbtcSats,
          displayAmount: '',
        ),
      ],
    );
  }

  @override
  Future<FaucetPayment> testServerFaucet(String walletId, String asset) async {
    faucet.add(asset);
    return FaucetPayment(
      txid: 'fa' * 32,
      asset: asset,
      network: asset == 'btc' ? 'bitcoin-regtest' : 'liquid-regtest',
      amountSat: 1000000,
      address: 'bcrt1qfaucet',
      ticker: asset == 'btc' ? 'BTC' : 'LBTC',
      precision: 8,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppState _state({String? provider = 'native', String? reason}) => AppState()
  ..setActiveWallet('w1', name: 'Throwaway', type: 'Software', liquid: true)
  ..setLiquidNetworkInfo(
    LiquidNetworkInfo(
      network: provider == 'sideswap' ? 'liquid-testnet' : 'liquid-regtest',
      shortName: provider == 'sideswap' ? 'testnet' : 'regtest',
      policyAsset: 'b0' * 32,
      backend: 'electrum',
      backendDescription: 'electrum tcp://127.0.0.1:19061',
      pegProvider: provider,
      pegUnavailableReason: reason,
    ),
  );

Future<void> _pump(
  WidgetTester tester,
  _PegBridge bridge, {
  AppState? state,
  Size size = const Size(1280, 1800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state ?? _state(),
      child: MaterialApp(
        home: PegScreen(bridge: bridge, pollInterval: const Duration(hours: 1)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens an order's detail by its status badge.
Future<void> _expand(WidgetTester tester, String badge) async {
  await tester.tap(find.text(badge).first);
  await tester.pumpAndSettle();
}

Future<void> _tapDialog(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(PromptDialog), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _passGate(WidgetTester tester) async {
  expect(find.text('Confirm with your app password'), findsOneWidget);
  await tester.enterText(
    find.descendant(
      of: find.byType(PromptDialog),
      matching: find.byType(TextField),
    ),
    'app password',
  );
  await _tapDialog(tester, 'Sign');
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('native: says who moves the coins, quotes real fields', (
    tester,
  ) async {
    final bridge = _PegBridge();
    await _pump(tester, bridge);

    expect(find.textContaining('Native peg'), findsWidgets);
    expect(find.textContaining('Simulated'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '0.001');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('2 Bitcoin confirmations'), findsOneWidget);
    expect(find.text('35 sats, taken from the amount'), findsOneWidget);
    expect(find.text('Start peg-in'), findsOneWidget);
  });

  testWidgets('no provider: the reason, no form, orders still listed', (
    tester,
  ) async {
    final bridge = _PegBridge(orders: [_order(status: 'completed')]);
    await _pump(
      tester,
      bridge,
      state: _state(
        provider: null,
        reason:
            'PEG_UNAVAILABLE: Liquid testnet has no parent chain, so it has no '
            'native peg-in / peg-out.',
      ),
    );
    expect(find.text('No peg on this network'), findsOneWidget);
    expect(find.textContaining('has no parent chain'), findsOneWidget);
    expect(find.text('Start peg-in'), findsNothing);
    // With no peg here, every order is another network's: folded under
    // "Older orders", one tap away.
    expect(find.text('Completed'), findsNothing);
    await tester.tap(find.text('Older orders'));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
  });

  testWidgets('SideSwap: disclosed up front and before starting; its '
      'refusal is a calm warning', (tester) async {
    final bridge = _PegBridge(
      provider: 'sideswap',
      startError:
          'Peg chain access failed: SideSwap: the server refused: disabled on '
          'testnet',
    );
    await _pump(tester, bridge, state: _state(provider: 'sideswap'));

    expect(find.text('SideSwap swap — not a peg'), findsOneWidget);
    expect(find.textContaining('receive address'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, '0.001');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('SideSwap (custodial)'), findsOneWidget);
    await tester.tap(find.text('Start SideSwap swap'));
    await tester.pumpAndSettle();

    expect(find.text('Start a SideSwap swap?'), findsOneWidget);
    await _tapDialog(tester, 'Start swap');

    expect(bridge.calls, contains('start'));
    expect(find.text('Not started'), findsOneWidget);
    expect(find.textContaining('disabled on testnet'), findsOneWidget);
  });

  testWidgets('fund: cancelling the confirmation signs nothing', (
    tester,
  ) async {
    final bridge = _PegBridge(orders: [_order()]);
    await _pump(tester, bridge);
    await _expand(tester, 'Awaiting deposit');

    expect(find.text('2MwZFDfh4yR5ahSbq2mqgzhv77kPxPQELUY'), findsWidgets);
    expect(
      find.textContaining('valid through Liquid block 189'),
      findsOneWidget,
    );
    await tester.tap(find.text('Fund from this wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Pay the peg-in deposit?'), findsOneWidget);
    await _tapDialog(tester, 'Cancel');

    expect(bridge.calls.where((c) => c.startsWith('fund')), isEmpty);
  });

  testWidgets('fund: confirm, password gate, then the engine signs', (
    tester,
  ) async {
    final bridge = _PegBridge(orders: [_order()]);
    await _pump(tester, bridge);
    await _expand(tester, 'Awaiting deposit');

    await tester.tap(find.text('Fund from this wallet'));
    await tester.pumpAndSettle();
    await _tapDialog(tester, 'Continue');
    await _passGate(tester);

    expect(bridge.calls, contains('fund pg_00000001'));
    expect(find.text('Deposit seen'), findsWidgets);
    expect(find.text('Fund from this wallet'), findsNothing);
  });

  testWidgets('fund refused by the engine: shown on the order, calmly', (
    tester,
  ) async {
    final bridge = _PegBridge(
      orders: [_order()],
      fundError:
          'Transaction build failed: Insufficient funds: 0 sat available of '
          '100043 sat needed',
    );
    await _pump(tester, bridge);
    await _expand(tester, 'Awaiting deposit');
    await tester.tap(find.text('Fund from this wallet'));
    await tester.pumpAndSettle();
    await _tapDialog(tester, 'Continue');
    await _passGate(tester);

    expect(find.text('Not done'), findsOneWidget);
    expect(find.textContaining('Insufficient funds'), findsOneWidget);
    expect(find.text('Fund from this wallet'), findsOneWidget);
  });

  testWidgets('peg-out: nothing to pay by hand, fund makes the peg-out', (
    tester,
  ) async {
    final bridge = _PegBridge(orders: [_order(direction: 'out')]);
    await _pump(tester, bridge);
    await _expand(tester, 'Awaiting funding');

    expect(find.textContaining('no address to pay by hand'), findsOneWidget);
    await tester.tap(find.text('Fund from this wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Make the peg-out?'), findsOneWidget);
    expect(find.textContaining('federation pays'), findsOneWidget);
  });

  testWidgets('confirmations are counted, n of m', (tester) async {
    final bridge = _PegBridge(
      orders: [
        _order(status: 'confirming', confirmations: 1, txidDeposit: 'ab' * 32),
      ],
    );
    await _pump(tester, bridge);
    expect(find.text('Confirming 1/2'), findsOneWidget);
    await _expand(tester, 'Confirming 1/2');
    expect(find.text('1 of 2 Bitcoin confirmations'), findsOneWidget);
    expect(find.text('Claim'), findsNothing);
  });

  testWidgets('claim: confirm, password gate, then settling', (tester) async {
    final bridge = _PegBridge(
      orders: [
        _order(status: 'claimable', confirmations: 2, txidDeposit: 'ab' * 32),
      ],
    );
    await _pump(tester, bridge);
    await _expand(tester, 'Ready to claim');

    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();
    expect(find.text('Claim the peg-in?'), findsOneWidget);
    await _tapDialog(tester, 'Continue');
    await _passGate(tester);

    expect(bridge.calls, contains('claim pg_00000001'));
    expect(find.text('Settling'), findsWidgets);
  });

  testWidgets('claim too early: the engine says why, by its tag', (
    tester,
  ) async {
    final bridge = _PegBridge(
      orders: [
        _order(status: 'claimable', confirmations: 2, txidDeposit: 'ab' * 32),
      ],
      claimError:
          'PEG_NOT_READY: the deposit has 1 of the 2 Bitcoin confirmations a '
          'claim needs.',
    );
    await _pump(tester, bridge);
    await _expand(tester, 'Ready to claim');
    await tester.tap(find.text('Claim'));
    await tester.pumpAndSettle();
    await _tapDialog(tester, 'Continue');
    await _passGate(tester);

    expect(find.text('Not done'), findsOneWidget);
    expect(
      find.textContaining('Not yet: the deposit has 1 of the 2'),
      findsOneWidget,
    );
  });

  testWidgets('expired: never pay it, nothing offered', (tester) async {
    final bridge = _PegBridge(orders: [_order(status: 'expired')]);
    await _pump(tester, bridge);
    await _expand(tester, 'Expired');

    expect(find.text('Order expired'), findsOneWidget);
    expect(find.textContaining('never pay it'), findsOneWidget);
    expect(find.text('Fund from this wallet'), findsNothing);
    expect(find.text('Cancel order'), findsNothing);
    expect(find.text('2MwZFDfh4yR5ahSbq2mqgzhv77kPxPQELUY'), findsNothing);
  });

  testWidgets('a legacy simulated order is shown as such', (tester) async {
    final bridge = _PegBridge(
      orders: [
        _order(
          status: 'awaiting_deposit',
          provider: 'simulated',
          simulated: true,
        ),
      ],
    );
    await _pump(tester, bridge);
    // Folded under "Older orders", not mixed with the network's own.
    expect(find.text('Simulated'), findsNothing);
    await tester.tap(find.text('Older orders'));
    await tester.pumpAndSettle();
    expect(find.text('Simulated'), findsOneWidget);
    await _expand(tester, 'Simulated');

    expect(
      find.textContaining('An order of the retired simulated provider'),
      findsOneWidget,
    );
    expect(find.text('Fund from this wallet'), findsNothing);
    expect(find.text('Cancel order'), findsNothing);
  });

  testWidgets('a chain that cannot be read is reported on the order', (
    tester,
  ) async {
    final bridge = _PegBridge(
      orders: [
        _order(
          lastError:
              'PEG_UNAVAILABLE: this order belongs to the test server '
              'http://127.0.0.1:8096; join it, on Liquid regtest, to follow '
              'the order.',
        ),
      ],
    );
    await _pump(tester, bridge);
    await _expand(tester, 'Awaiting deposit');
    expect(find.text('Could not check this order'), findsOneWidget);
    expect(find.textContaining('belongs to the test server'), findsOneWidget);
  });

  testWidgets('fits a phone with an order open', (tester) async {
    final bridge = _PegBridge(
      orders: [
        _order(status: 'claimable', confirmations: 2, txidDeposit: 'ab' * 32),
      ],
    );
    await _pump(tester, bridge, size: const Size(390, 1600));
    await _expand(tester, 'Ready to claim');
    expect(find.text('Claim'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the form shows this wallet\'s BTC and L-BTC beside You send', (
    tester,
  ) async {
    final bridge = _PegBridge()
      ..btcSats = 2000000
      ..lbtcSats = 1000000;
    await _pump(tester, bridge);
    expect(
      find.text('In this wallet: 0.02000000 BTC · 0.01000000 L-BTC'),
      findsOneWidget,
    );
    await tester.tap(find.text('Peg out'));
    await tester.pumpAndSettle();
    expect(
      find.text('In this wallet: 0.01000000 L-BTC · 0.02000000 BTC'),
      findsOneWidget,
    );
  });

  testWidgets('older orders fold under the network\'s own', (tester) async {
    final bridge = _PegBridge(
      orders: [
        _order(id: 'pg_now00001', status: 'confirming', confirmations: 1),
        _order(id: 'pg_side0001', status: 'completed', provider: 'sideswap'),
        _order(
          id: 'pg_old00001',
          status: 'expired',
          provider: 'simulated',
          simulated: true,
        ),
      ],
    );
    await _pump(tester, bridge);
    expect(find.textContaining('Confirming'), findsWidgets);
    expect(find.text('Older orders'), findsOneWidget);
    expect(
      find.text('2 of another network or of the retired simulated provider'),
      findsOneWidget,
    );
    expect(find.text('Simulated'), findsNothing);
    await tester.tap(find.text('Older orders'));
    await tester.pumpAndSettle();
    expect(find.text('Simulated'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
  });

  testWidgets('not enough BTC: the refusal in words and the faucet beside it', (
    tester,
  ) async {
    final mock = MockWalletBridge();
    await tester.runAsync(() => mock.setTestServer('http://127.0.0.1:8196'));
    final server = (await tester.runAsync(mock.getTestServer))!;
    TestCoins.instance.reset();
    final bridge = _PegBridge(
      orders: [_order()],
      fundError:
          'PEG_INSUFFICIENT_FUNDS: this wallet has 0 sat of BTC on Bitcoin '
          'regtest; the deposit and its fee need 100043 sat.',
    )..btcSats = 0;
    final state = _state()..setTestServerInfo(server);
    await _pump(tester, bridge, state: state);
    await _expand(tester, 'Awaiting deposit');
    await tester.tap(find.text('Fund from this wallet'));
    await tester.pumpAndSettle();
    await _tapDialog(tester, 'Continue');
    await _passGate(tester);

    expect(find.text('Not enough BTC'), findsOneWidget);
    expect(
      find.text(
        'Not enough coins: This wallet has 0 sat of BTC on Bitcoin regtest; '
        'the deposit and its fee need 100043 sat. Nothing was signed.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Transaction build failed'), findsNothing);
    await tester.tap(find.text('Get test BTC'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(bridge.faucet, ['btc']);
    expect(find.textContaining('0.01000000 BTC on its way'), findsOneWidget);
    TestCoins.instance.reset();
  });

  testWidgets('no provider and no test server: where to join one', (
    tester,
  ) async {
    await _pump(tester, _PegBridge(), state: _state(provider: null));
    expect(
      find.textContaining('Settings › Network › Nodes and explorers'),
      findsOneWidget,
    );
    expect(find.textContaining('Network & Sync'), findsNothing);
  });
}
