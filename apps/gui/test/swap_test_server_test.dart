// The swap market against a test server: which book the header names, when
// the order book's admin is offered, a reset lab, the order book's publish
// refusals as people read them, and the take flow naming the chain it uses.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/swap/publish_error.dart';
import 'package:templar_wallet/features/swap/swap_screen.dart';
import 'package:templar_wallet/features/swap/take_flow.dart';

const _testnetAsset =
    '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';

LiquidNetworkInfo _liquid({required bool regtest}) => LiquidNetworkInfo(
  network: regtest ? 'liquid-regtest' : 'liquid-testnet',
  shortName: regtest ? 'regtest' : 'testnet',
  policyAsset: _testnetAsset,
  backend: 'electrum',
  backendDescription: 'test',
  testServer: regtest ? 'http://127.0.0.1:8096' : null,
);

TestServerInfo _server({
  bool joined = true,
  String origin = 'http://127.0.0.1:3210',
}) => TestServerInfo.fromJson({
  'configured': joined,
  'profile': joined
      ? {
          'base_url': 'http://127.0.0.1:8096',
          'name': 'Templar testlab',
          'version': 1,
          'fetched_at': 0,
          'orderbook_url': origin,
          'regtest': {
            'peg': {'provider': 'native'},
          },
        }
      : null,
  'active': {
    'liquid_network': joined ? 'liquid-regtest' : 'liquid-testnet',
    'env_locked': false,
    'orderbook': {
      'origin': {'url': origin, 'source': joined ? 'profile' : 'env'},
    },
    'liquid': {'network': joined ? 'liquid-regtest' : 'liquid-testnet'},
    'bitcoin': {
      'network': joined ? 'bitcoin-regtest' : 'bitcoin-testnet',
      'electrum_url': 'tcp://127.0.0.1:19060',
      'source': joined ? 'profile' : 'default',
    },
  },
});

// `testServerChecked`: the market's first-use check would otherwise ask the
// mock bridge, which has joined nothing, and replace the state set here.
AppState _state({TestServerInfo? server, bool regtest = false}) => AppState()
  ..setActiveWallet('wallet-1', name: 'Primary', type: 'Software')
  ..setLiquidNetworkInfo(_liquid(regtest: regtest))
  ..setTestServerInfo(server)
  ..testServerChecked = true;

Widget _market(AppState state) => ChangeNotifierProvider<AppState>.value(
  value: state,
  child: const MaterialApp(home: SwapScreen()),
);

Future<void> _desktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('publish refusals', () {
    String text(String err) =>
        swapPublishErrorText(Exception('wallet-ffi: $err'));

    test('rate limited says when to retry', () {
      expect(
        text(
          'BOOK_RATE_LIMITED: Too many offers published from here. '
          'Try again in 42 seconds.',
        ),
        allOf(contains('limiting publishes'), endsWith('in 42 seconds.')),
      );
      expect(
        text('BOOK_RATE_LIMITED: Too many. Try again in 600 seconds.'),
        endsWith('in 10 minutes.'),
      );
      expect(
        text('BOOK_RATE_LIMITED: Too many offers. Try again later.'),
        endsWith('in a few minutes.'),
      );
    });

    test('chain unreachable: nothing stored, try later', () {
      expect(
        text(
          'BOOK_CHAIN_UNREACHABLE: The order book cannot verify offers on '
          'liquid-regtest right now, so nothing was stored. Try again later. '
          '(electrs down)',
        ),
        allOf(contains('was not stored'), endsWith('Try again later.')),
      );
    });

    test('duplicate is already published', () {
      expect(
        text('BOOK_DUPLICATE: This offer is already in the order book'),
        startsWith('Already published'),
      );
    });

    test('publishing disabled', () {
      expect(
        text(
          'BOOK_PUBLISH_DISABLED: This order book does not take public '
          'offers for liquid-testnet: closed',
        ),
        contains('does not take public offers on this network'),
      );
    });

    test('rejected shows the reason', () {
      expect(
        text(
          'BOOK_REJECTED: The order book refused the offer: input already '
          'spent',
        ),
        'The order book refused the offer: input already spent',
      );
    });

    test('unreachable points at the test server setting', () {
      expect(
        text(
          'BOOK_UNREACHABLE: Cannot reach the order book at '
          'http://127.0.0.1:3210/api/offers: refused',
        ),
        allOf(contains('Cannot reach the order book'), contains('Settings')),
      );
    });

    test('untagged errors pass through', () {
      expect(
        text('Liquid mainnet proposals cannot be published'),
        'Liquid mainnet proposals cannot be published',
      );
    });
  });

  group('market header', () {
    testWidgets('names the joined test server and its network', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(
        _market(_state(server: _server(), regtest: true)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Regtest'), findsOneWidget);
      expect(find.text('Templar testlab'), findsOneWidget);
      // A lab on this machine: its book's admin (a login page) is offered.
      expect(find.byTooltip('Order book admin'), findsOneWidget);
    });

    testWidgets('a remote book offers no admin link', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(
        _market(
          _state(
            server: _server(
              joined: false,
              origin: 'https://book.lab.example.org',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Testnet'), findsOneWidget);
      expect(find.text('book.lab.example.org'), findsOneWidget);
      expect(find.byTooltip('Order book admin'), findsNothing);
      expect(find.text('Book admin'), findsNothing);
    });

    testWidgets('a reset lab offers to re-join', (tester) async {
      await _desktop(tester);
      final state = _state(server: _server(), regtest: true)
        ..setTestServerStale(true);
      await tester.pumpWidget(_market(state));
      await tester.pumpAndSettle();

      expect(find.text('The test chain was reset'), findsOneWidget);
      expect(find.text('Re-join'), findsOneWidget);
    });
  });

  group('take flow wording', () {
    Future<void> openImport(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showImportProposalDialog(context),
                child: const Text('import'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('import'));
      await tester.pumpAndSettle();
    }

    testWidgets('names the test server regtest', (tester) async {
      await _desktop(tester);
      await openImport(tester, _state(server: _server(), regtest: true));
      expect(
        find.textContaining(
          'against the Liquid regtest of Templar testlab — nothing is signed yet',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Liquid testnet'), findsNothing);
    });

    testWidgets('names testnet on testnet', (tester) async {
      await _desktop(tester);
      await openImport(tester, _state());
      expect(
        find.textContaining('against Liquid testnet — nothing is signed yet'),
        findsOneWidget,
      );
    });

    testWidgets('verifying step names the chain', (tester) async {
      await _desktop(tester);
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: _state(server: _server(), regtest: true),
          child: const MaterialApp(home: TakeFlowScreen(proposalJson: '{}')),
        ),
      );
      await tester.pump();
      expect(
        find.text(
          'Checking the proposal against the Liquid regtest of Templar testlab…',
        ),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
    });
  });
}
