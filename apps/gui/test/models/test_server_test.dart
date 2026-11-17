// Decoding of the engine's TestServer answer (templarlib docs/API.md,
// **TestServer**) and of the keys `get_liquid_network` gained with it.

import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';

Map<String, dynamic> _active({
  String liquid = 'liquid-regtest',
  String bitcoin = 'bitcoin-regtest',
  String source = 'profile',
  String origin = 'http://127.0.0.1:3210',
}) => {
  'liquid_network': liquid,
  'env_locked': false,
  'orderbook': {
    for (final (key, path) in [
      ('origin', ''),
      ('book', '/api/book'),
      ('markets', '/api/markets'),
      ('publish', '/api/offers'),
      ('atomic_swaps', '/api/atomic-swaps'),
    ])
      key: {'url': '$origin$path', 'source': source},
  },
  'liquid': {
    'network': liquid,
    'policy_asset': 'aa' * 32,
    'genesis_hash': 'bb' * 32,
    'params_source': source,
    'backend': 'electrum',
    'backend_description': 'electrum tcp://127.0.0.1:19061',
    'backend_source': source,
  },
  'bitcoin': {
    'network': bitcoin,
    'electrum_url': 'tcp://127.0.0.1:19060',
    'source': source,
  },
};

void main() {
  test('a joined server decodes whole: profile, check, applied, active', () {
    final info = TestServerInfo.fromJson({
      'configured': true,
      'profile': {
        'base_url': 'http://127.0.0.1:8096',
        'name': 'Templar testlab',
        'version': 1,
        'fetched_at': 1794000000,
        'orderbook_url': 'http://127.0.0.1:3210',
        'regtest': {
          'instance_id': '0f3a',
          'policy_asset': 'aa' * 32,
          'genesis_hash': 'bb' * 32,
          'liquid_electrum_url': 'tcp://127.0.0.1:19061',
          'bitcoin_network': 'regtest',
          'bitcoin_electrum_url': 'tcp://127.0.0.1:19060',
          'bitcoin_esplora_url': 'http://127.0.0.1:19070',
          'faucet_url': 'http://127.0.0.1:8096/api/faucet',
          'peg': {
            'provider': 'native',
            'pegin_confirmations': 102,
            'pegout_confirmations': 2,
            'pegout_max_sat': 100000000,
          },
        },
        'testnet': {
          'faucet_url': 'https://liquidtestnet.com/faucet',
          'peg': {'provider': 'sideswap'},
        },
      },
      'check': {
        'reachable': true,
        'error': null,
        'server_instance_id': '9c1d',
        'stale': true,
      },
      'applied': {
        'liquid_network': 'liquid-regtest',
        'network_switched': true,
        'wallet_closed': true,
        'regtest_cache_reset': false,
      },
      'active': _active(),
    });

    expect(info.configured, isTrue);
    final p = info.profile!;
    expect(p.name, 'Templar testlab');
    expect(p.version, 1);
    expect(p.fetchedAt, 1794000000);
    expect(p.regtest.instanceId, '0f3a');
    expect(p.regtest.bitcoinNetwork, 'regtest');
    expect(p.regtest.faucetUrl, endsWith('/api/faucet'));
    expect(p.regtest.peg.provider, 'native');
    expect(p.regtest.peg.peginConfirmations, 102);
    expect(p.regtest.peg.pegoutMaxSat, 100000000);
    expect(p.testnet!.peg!.provider, 'sideswap');
    expect(p.testnet!.peg!.pegoutConfirmations, isNull);

    expect(info.isStale, isTrue);
    expect(info.isUnreachable, isFalse);
    expect(info.check!.serverInstanceId, '9c1d');
    expect(info.applied!.walletClosed, isTrue);
    expect(info.applied!.networkSwitched, isTrue);

    final a = info.active;
    expect(a.bitcoin.isRegtest, isTrue);
    expect(a.bitcoin.shortName, 'regtest');
    expect(a.orderbook.origin.url, 'http://127.0.0.1:3210');
    expect(a.orderbook.publish.url, 'http://127.0.0.1:3210/api/offers');
    expect(a.orderbook.atomicSwaps.source, 'profile');
    expect(a.orderbook.origin.sourceLabel, 'test server');
    expect(a.orderbook.isLoopback, isTrue);
    expect(a.liquid.genesisHash, 'bb' * 32);
    expect(a.liquid.backendSource, 'profile');
  });

  test('no server joined: nulls stay null, testnet defaults', () {
    final info = TestServerInfo.fromJson({
      'configured': false,
      'profile': null,
      'check': null,
      'applied': null,
      'active': _active(
        liquid: 'liquid-testnet',
        bitcoin: 'bitcoin-testnet',
        source: 'default',
        origin: 'https://book.lab.example.org',
      ),
    });
    expect(info.configured, isFalse);
    expect(info.profile, isNull);
    expect(info.check, isNull);
    expect(info.applied, isNull);
    expect(info.isStale, isFalse);
    expect(info.active.bitcoin.isRegtest, isFalse);
    expect(info.active.orderbook.origin.sourceLabel, 'built-in default');
    expect(info.active.orderbook.isLoopback, isFalse);
  });

  test('an unreachable check is not stale', () {
    final info = TestServerInfo.fromJson({
      'configured': true,
      'check': {
        'reachable': false,
        'error': 'Cannot reach the test server: refused',
        'server_instance_id': null,
        'stale': false,
      },
      'active': _active(),
    });
    expect(info.isUnreachable, isTrue);
    expect(info.isStale, isFalse);
    expect(info.check!.error, contains('Cannot reach'));
  });

  test('missing keys fall back instead of throwing', () {
    final info = TestServerInfo.fromJson(const {});
    expect(info.configured, isFalse);
    expect(info.active.liquidNetwork, 'liquid-testnet');
    expect(info.active.bitcoin.network, 'bitcoin-testnet');
    expect(info.active.orderbook.origin.source, 'default');
  });

  test('every source has a reading', () {
    expect(endpointSourceLabel('env'), 'environment variable');
    expect(endpointSourceLabel('profile'), 'test server');
    expect(endpointSourceLabel('setting'), 'app setting');
    expect(endpointSourceLabel('default'), 'built-in default');
  });

  test('get_liquid_network: backend_source and test_server', () {
    final joined = LiquidNetworkInfo.fromJson({
      'network': 'liquid-regtest',
      'short_name': 'regtest',
      'policy_asset': 'aa' * 32,
      'backend': 'electrum',
      'backend_description': 'electrum tcp://127.0.0.1:19061',
      'env_locked': false,
      'regtest_default_policy_asset': 'cc' * 32,
      'backend_source': 'profile',
      'test_server': 'http://127.0.0.1:8096',
    });
    expect(joined.backendSource, 'profile');
    expect(joined.testServer, 'http://127.0.0.1:8096');

    // An older engine without the keys still decodes.
    final old = LiquidNetworkInfo.fromJson({
      'network': 'liquid-testnet',
      'short_name': 'testnet',
      'policy_asset': 'dd' * 32,
      'backend': 'electrum',
      'backend_description': 'electrum ssl://x:1',
      'env_locked': false,
      'regtest_default_policy_asset': 'cc' * 32,
    });
    expect(old.backendSource, 'default');
    expect(old.testServer, isNull);
  });
}
