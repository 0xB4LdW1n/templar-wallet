// With a test server joined, Bitcoin runs on the lab's regtest. Screens that
// used to say "testnet" or link to a public explorer follow the network the
// engine reports (active.bitcoin.network): no explorer links on a regtest.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/send/models/tx_preview.dart';
import 'package:templar_wallet/features/utxos/models/utxo.dart';
import 'package:templar_wallet/shared/widgets/tx_confirm_view.dart';
import 'package:templar_wallet/shared/widgets/tx_success_view.dart';
import 'package:templar_wallet/shared/widgets/utxo_details.dart';
import 'package:templar_wallet/shared/widgets/utxo_views.dart';

const _addr = 'bcrt1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx';

TxPreview _preview() => TxPreview(
  chain: 'bitcoin',
  recipientAddress: _addr,
  amountDisplay: '0.00010000 BTC',
  feeSats: 141,
  feeDisplay: '141 sats',
  totalDisplay: '0.00010141 BTC',
  outputs: const [TxIo(address: _addr, amountSats: 10000, isChange: false)],
);

AppState _state({required bool lab}) => AppState()
  ..setLiquidNetworkInfo(
    LiquidNetworkInfo(
      network: lab ? 'liquid-regtest' : 'liquid-testnet',
      shortName: lab ? 'regtest' : 'testnet',
      policyAsset: 'aa' * 32,
      backend: 'electrum',
      backendDescription: 'test',
    ),
  )
  ..setTestServerInfo(
    TestServerInfo.fromJson({
      'configured': lab,
      'profile': lab
          ? {
              'base_url': 'http://127.0.0.1:8096',
              'name': 'Templar testlab',
              'regtest': <String, dynamic>{},
            }
          : null,
      'active': {
        'bitcoin': {
          'network': lab ? 'bitcoin-regtest' : 'bitcoin-testnet',
          'electrum_url': 'tcp://127.0.0.1:19060',
          'source': lab ? 'profile' : 'default',
        },
      },
    }),
  );

Future<void> _open(
  WidgetTester tester,
  AppState state,
  void Function(BuildContext) open,
) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the network and explorer bases follow the engine', () {
    final lab = _state(lab: true);
    expect(lab.isBitcoinRegtest, isTrue);
    expect(lab.bitcoinNetworkName, 'regtest');
    expect(lab.btcExplorerBase, isNull);
    expect(lab.liquidExplorerBase, isNull);
    expect(lab.liquidChainLabel, 'the Liquid regtest of Templar testlab');

    final testnet = _state(lab: false);
    expect(testnet.isBitcoinRegtest, isFalse);
    expect(testnet.btcExplorerBase, testnet.btcExplorerUrl);
    expect(testnet.liquidChainLabel, 'Liquid testnet');
  });

  testWidgets('a regtest send: no testnet wording, no explorer link', (
    tester,
  ) async {
    await _open(
      tester,
      _state(lab: true),
      (c) => showTxSuccessDialog(
        c,
        txid: 'ab' * 32,
        preview: _preview(),
        ticker: 'BTC',
      ),
    );
    expect(find.text('Broadcast to the Bitcoin regtest'), findsOneWidget);
    expect(find.text('View in explorer'), findsNothing);
  });

  testWidgets('a testnet send keeps its explorer link', (tester) async {
    await _open(
      tester,
      _state(lab: false),
      (c) => showTxSuccessDialog(
        c,
        txid: 'ab' * 32,
        preview: _preview(),
        ticker: 'BTC',
      ),
    );
    expect(find.text('Broadcast to the Bitcoin testnet'), findsOneWidget);
    expect(find.text('View in explorer'), findsOneWidget);
  });

  testWidgets('the confirmation names the regtest', (tester) async {
    await _open(
      tester,
      _state(lab: true),
      (c) => showTxConfirmDialog(
        c,
        preview: _preview(),
        ticker: 'BTC',
        signLabel: 'Sign',
        signHint: 'Signed with the vault key.',
      ),
    );
    expect(find.text('Bitcoin regtest'), findsOneWidget);
    expect(find.text('Bitcoin testnet'), findsNothing);
  });

  testWidgets('a regtest coin has no explorer link', (tester) async {
    await _open(
      tester,
      _state(lab: true),
      (c) => showUtxoDetails(
        c,
        utxo: Utxo(
          outpoint: '${'cd' * 32}:0',
          amount: 50000,
          displayAmount: '0.00050000 BTC',
          confirmations: 1,
          state: UtxoState.available,
          ticker: 'BTC',
        ),
        share: 1,
        tier: BanknoteTier.small,
      ),
    );
    expect(find.text('Open in explorer'), findsNothing);
  });
}
