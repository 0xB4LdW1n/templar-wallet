// Settings › Network & Sync › Test server. The card joins a lab with one URL,
// says whether the lab still runs the chain the wallet joined, re-joins after
// a reset and leaves — and every join or leave closes the open wallet, so it
// asks first and goes back to the wallet picker.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/settings/test_server_section.dart';
import 'package:templar_wallet/features/settings/test_server_switch.dart';
import 'package:templar_wallet/shared/widgets/app_dialog.dart';
import 'package:templar_wallet/theme/app_theme.dart';

const _labAsset =
    'b2e15d0d7a0c94e4e2ce0fe6e8691b9e451377f6e46e8045a86f7c4b5d4f0f23';

/// A bridge that answers the test-server methods from a script.
class _LabBridge implements WalletBridge {
  _LabBridge({
    this.joined = false,
    this.envLocked = false,
    this.reachable = true,
    this.stale = false,
    this.joinError,
  });

  bool joined;
  final bool envLocked;
  bool reachable;
  bool stale;
  final String? joinError;
  final calls = <String>[];

  bool get _onLab => joined && !envLocked;

  TestServerInfo _info({TestServerCheck? check, bool applied = false}) =>
      TestServerInfo(
        configured: joined,
        profile: joined
            ? const TestServerProfile(
                baseUrl: 'http://127.0.0.1:8096',
                name: 'Templar testlab',
                version: 1,
                fetchedAt: 1794000000,
                orderbookUrl: 'http://127.0.0.1:3210',
                regtest: TestServerRegtest(
                  instanceId: 'a1',
                  policyAsset: _labAsset,
                  genesisHash: '',
                  liquidElectrumUrl: 'tcp://127.0.0.1:19061',
                  bitcoinNetwork: 'regtest',
                  bitcoinElectrumUrl: 'tcp://127.0.0.1:19060',
                  bitcoinEsploraUrl: 'http://127.0.0.1:19070',
                  faucetUrl: 'http://127.0.0.1:8096/api/faucet',
                  peg: TestServerPeg(provider: 'native'),
                ),
              )
            : null,
        check: check,
        applied: applied
            ? TestServerApplied(
                liquidNetwork: _onLab ? 'liquid-regtest' : 'liquid-testnet',
                networkSwitched: !envLocked,
                walletClosed: true,
                regtestCacheReset: false,
              )
            : null,
        active: ActiveEndpoints(
          liquidNetwork: _onLab ? 'liquid-regtest' : 'liquid-testnet',
          envLocked: envLocked,
          orderbook: OrderbookEndpoints(
            origin: SourcedUrl(
              url: 'http://127.0.0.1:3210',
              source: joined ? 'profile' : 'default',
            ),
            book: const SourcedUrl(url: '', source: 'default'),
            markets: const SourcedUrl(url: '', source: 'default'),
            publish: const SourcedUrl(url: '', source: 'default'),
            atomicSwaps: const SourcedUrl(url: '', source: 'default'),
          ),
          liquid: LiquidEndpoint(
            network: _onLab ? 'liquid-regtest' : 'liquid-testnet',
            policyAsset: _labAsset,
            paramsSource: 'default',
            backend: 'electrum',
            backendDescription: 'electrum tcp://127.0.0.1:19061',
            backendSource: _onLab ? 'profile' : 'default',
          ),
          bitcoin: BitcoinEndpoint(
            network: _onLab ? 'bitcoin-regtest' : 'bitcoin-testnet',
            electrumUrl: 'tcp://127.0.0.1:19060',
            source: _onLab ? 'profile' : 'default',
          ),
        ),
      );

  @override
  Future<TestServerInfo> getTestServer({bool check = false}) async {
    calls.add('get(check: $check)');
    if (!check || !joined) return _info();
    return _info(
      check: reachable
          ? TestServerCheck(reachable: true, stale: stale)
          : const TestServerCheck(
              reachable: false,
              stale: false,
              error: 'Cannot reach the test server: connection refused',
            ),
    );
  }

  @override
  Future<TestServerInfo> setTestServer(String url) async {
    calls.add('set($url)');
    if (joinError != null) throw Exception('wallet-ffi: $joinError');
    joined = true;
    stale = false;
    return _info(
      check: const TestServerCheck(reachable: true, stale: false),
      applied: true,
    );
  }

  @override
  Future<TestServerInfo> clearTestServer() async {
    calls.add('clear');
    joined = false;
    return _info(applied: true);
  }

  @override
  Future<LiquidNetworkInfo> getLiquidNetwork() async => LiquidNetworkInfo(
    network: _onLab ? 'liquid-regtest' : 'liquid-testnet',
    shortName: _onLab ? 'regtest' : 'testnet',
    policyAsset: _labAsset,
    backend: 'electrum',
    backendDescription: 'electrum tcp://127.0.0.1:19061',
    envLocked: envLocked,
    testServer: joined ? 'http://127.0.0.1:8096' : null,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The card under a router, so a closed wallet can go back to the picker.
Widget _host(_LabBridge bridge, AppState state) => ChangeNotifierProvider.value(
  value: state,
  child: MaterialApp.router(
    theme: AppTheme.dark(),
    routerConfig: GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('WALLET PICKER')),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(child: TestServerCard(bridge: bridge)),
          ),
        ),
      ],
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester,
  _LabBridge bridge,
  AppState state,
) async {
  tester.view.physicalSize = const Size(1280, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(bridge, state));
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, String action) async {
  // The dialog's button, not the card's.
  await tester.tap(
    find.descendant(of: find.byType(PromptDialog), matching: find.text(action)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a malformed URL is refused before the engine is asked', (
    tester,
  ) async {
    final bridge = _LabBridge();
    await _pump(tester, bridge, AppState());

    await tester.enterText(
      find.byKey(const Key('test-server-url')),
      '127.0.0.1:8096',
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Start with http:// or https://'),
      findsOneWidget,
    );
    expect(bridge.calls.where((c) => c.startsWith('set')), isEmpty);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'join asks first, closes the open wallet, returns to the picker',
    (tester) async {
      final bridge = _LabBridge();
      final state = AppState()
        ..setActiveWallet('w1', name: 'Primary', type: 'Software');
      await _pump(tester, bridge, state);

      await tester.enterText(
        find.byKey(const Key('test-server-url')),
        'http://127.0.0.1:8096/',
      );
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(find.text('Join this test server?'), findsOneWidget);
      expect(
        find.textContaining('The open wallet will be closed'),
        findsOneWidget,
      );
      expect(find.textContaining('bcrt1'), findsOneWidget);
      await _confirm(tester, 'Join');

      expect(bridge.calls, contains('set(http://127.0.0.1:8096/)'));
      expect(state.activeWalletId, isNull);
      expect(state.isBitcoinRegtest, isTrue);
      expect(state.liquidNetwork?.shortName, 'regtest');
      expect(state.testServerName, 'Templar testlab');
      expect(find.text('WALLET PICKER'), findsOneWidget);
    },
  );

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final bridge = _LabBridge();
    await _pump(tester, bridge, AppState());

    await tester.enterText(
      find.byKey(const Key('test-server-url')),
      'http://127.0.0.1:8096',
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(bridge.calls.where((c) => c.startsWith('set')), isEmpty);
    expect(find.text('Join'), findsOneWidget);
  });

  testWidgets('an unreachable server at join time shows the engine refusal', (
    tester,
  ) async {
    final bridge = _LabBridge(
      joinError: 'Cannot reach the test server: connection refused',
    );
    final state = AppState();
    await _pump(tester, bridge, state);

    await tester.enterText(
      find.byKey(const Key('test-server-url')),
      'http://10.255.255.1:8096',
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    await _confirm(tester, 'Join');

    expect(
      find.text('Cannot reach the test server: connection refused'),
      findsOneWidget,
    );
    expect(state.testServer?.configured, isFalse);
  });

  testWidgets('a joined server that stops answering is reported, not fatal', (
    tester,
  ) async {
    final bridge = _LabBridge(joined: true, reachable: false);
    await _pump(tester, bridge, AppState());

    expect(find.text('Templar testlab'), findsOneWidget);
    expect(find.text('Not checked this session'), findsOneWidget);

    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();

    expect(bridge.calls, contains('get(check: true)'));
    expect(find.text('Test server unreachable'), findsOneWidget);
    expect(find.textContaining('connection refused'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
  });

  testWidgets('a reset chain says so and re-joins the same server', (
    tester,
  ) async {
    final bridge = _LabBridge(joined: true, stale: true);
    final state = AppState();
    await _pump(tester, bridge, state);

    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();
    expect(find.text('The test chain was reset'), findsOneWidget);
    expect(state.testServerStale, isTrue);

    await tester.tap(find.text('Re-join'));
    await tester.pumpAndSettle();
    expect(find.text('Re-join the test server?'), findsOneWidget);
    await _confirm(tester, 'Re-join');

    expect(bridge.calls, contains('set(http://127.0.0.1:8096)'));
    expect(state.testServerStale, isFalse);
    expect(find.text('The test chain was reset'), findsNothing);
  });

  testWidgets('leave asks first and goes back to testnet', (tester) async {
    final bridge = _LabBridge(joined: true);
    final state = AppState();
    await _pump(tester, bridge, state);

    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Leave Templar testlab?'), findsOneWidget);
    await _confirm(tester, 'Leave');

    expect(bridge.calls, contains('clear'));
    expect(state.testServer?.configured, isFalse);
    expect(state.isBitcoinRegtest, isFalse);
    expect(state.liquidNetwork?.shortName, 'testnet');
    expect(find.byKey(const Key('test-server-url')), findsOneWidget);
  });

  testWidgets('a network fixed by the environment is stated up front', (
    tester,
  ) async {
    final bridge = _LabBridge(envLocked: true);
    final state = AppState();
    await _pump(tester, bridge, state);

    expect(
      find.textContaining('TEMPLAR_LIQUID_NETWORK fixes Liquid'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('test-server-url')),
      'http://127.0.0.1:8096',
    );
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PromptDialog),
        matching: find.textContaining(
          'regtest chains apply only once the variable is unset',
        ),
      ),
      findsOneWidget,
    );
    await _confirm(tester, 'Join');

    // Joined, but Liquid stayed where the variable holds it.
    expect(state.testServer?.configured, isTrue);
    expect(state.liquidNetwork?.shortName, 'testnet');
    expect(state.isBitcoinRegtest, isFalse);
    expect(
      find.textContaining('TEMPLAR_LIQUID_NETWORK fixes it'),
      findsOneWidget,
    );
  });

  testWidgets('fits a phone column, joined and reset', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bridge = _LabBridge(joined: true, stale: true);
    await tester.pumpWidget(_host(bridge, AppState()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Check now'));
    await tester.pumpAndSettle();

    expect(find.text('The test chain was reset'), findsOneWidget);
    expect(find.text('Re-join'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('the first-use check runs once and flags a reset lab', () async {
    final bridge = _LabBridge(joined: true, stale: true);
    final state = AppState()..setTestServerInfo(await bridge.getTestServer());
    bridge.calls.clear();

    await checkTestServerOnce(state, bridge: bridge);
    await checkTestServerOnce(state, bridge: bridge);

    expect(bridge.calls, ['get(check: true)']);
    expect(state.testServerStale, isTrue);
  });

  test('no server joined: the first-use check asks nothing', () async {
    final bridge = _LabBridge();
    final state = AppState()..setTestServerInfo(await bridge.getTestServer());
    bridge.calls.clear();

    await checkTestServerOnce(state, bridge: bridge);

    expect(bridge.calls, isEmpty);
  });

  test('URL shape feedback', () {
    expect(testServerUrlProblem(''), isNotNull);
    expect(testServerUrlProblem('ftp://lab.example.org'), isNotNull);
    expect(testServerUrlProblem('http://user:pw@lab.example.org'), isNotNull);
    expect(testServerUrlProblem('https://lab.example.org/?x=1'), isNotNull);
    expect(testServerUrlProblem('http://127.0.0.1:8096'), isNull);
    expect(testServerUrlProblem(' https://lab.example.org/base/ '), isNull);
  });
}
