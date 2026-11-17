/// The Templar test server ("testlab") the engine may have joined, and the
/// servers it talks to right now — the answer of `get_test_server`,
/// `set_test_server` and `clear_test_server` (templarlib docs/API.md,
/// **TestServer**).
///
/// Display data only. Which servers are used, whether a profile is valid and
/// whether it is stale is decided by the engine; nothing here second-guesses
/// it.
library;

/// The whole answer.
class TestServerInfo {
  const TestServerInfo({
    required this.configured,
    required this.active,
    this.profile,
    this.check,
    this.applied,
  });

  /// A test server is joined (`profile` is then non-null).
  final bool configured;

  /// What the server's `/api/config` said when it was joined.
  final TestServerProfile? profile;

  /// A live look at the server: always on `set_test_server`, and on
  /// `get_test_server` when asked; null otherwise.
  final TestServerCheck? check;

  /// What `set_test_server` / `clear_test_server` changed; null on `get`.
  final TestServerApplied? applied;

  /// The servers in use after the call.
  final ActiveEndpoints active;

  /// The joined server answered with a different chain than the stored
  /// profile (its chains were reset): re-join to apply it.
  bool get isStale => check?.stale ?? false;

  /// The live check ran and the server did not answer.
  bool get isUnreachable => check != null && !check!.reachable;

  factory TestServerInfo.fromJson(Map<String, dynamic> j) => TestServerInfo(
    configured: j['configured'] as bool? ?? false,
    profile: _map(j['profile'], TestServerProfile.fromJson),
    check: _map(j['check'], TestServerCheck.fromJson),
    applied: _map(j['applied'], TestServerApplied.fromJson),
    active: ActiveEndpoints.fromJson(
      j['active'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

/// The validated, normalised `/api/config` of the joined server.
class TestServerProfile {
  const TestServerProfile({
    required this.baseUrl,
    required this.name,
    required this.version,
    required this.fetchedAt,
    required this.orderbookUrl,
    required this.regtest,
    this.testnet,
  });

  final String baseUrl;

  /// The lab's display name.
  final String name;

  /// The config contract version.
  final int version;

  /// Unix seconds of the fetch this profile came from.
  final int fetchedAt;

  /// Origin of the lab's LiquiDEX order book.
  final String orderbookUrl;

  /// The lab's own chains — the only block the engine applies.
  final TestServerRegtest regtest;

  /// Liquid testnet links, display only.
  final TestServerTestnet? testnet;

  factory TestServerProfile.fromJson(Map<String, dynamic> j) =>
      TestServerProfile(
        baseUrl: j['base_url'] as String? ?? '',
        name: j['name'] as String? ?? '',
        version: (j['version'] as num?)?.toInt() ?? 0,
        fetchedAt: (j['fetched_at'] as num?)?.toInt() ?? 0,
        orderbookUrl: j['orderbook_url'] as String? ?? '',
        regtest: TestServerRegtest.fromJson(
          j['regtest'] as Map<String, dynamic>? ?? const {},
        ),
        testnet: _map(j['testnet'], TestServerTestnet.fromJson),
      );
}

/// `regtest` of a profile: the lab's Bitcoin + Liquid regtest pair.
class TestServerRegtest {
  const TestServerRegtest({
    required this.instanceId,
    required this.policyAsset,
    required this.genesisHash,
    required this.liquidElectrumUrl,
    required this.bitcoinNetwork,
    required this.bitcoinElectrumUrl,
    required this.bitcoinEsploraUrl,
    required this.faucetUrl,
    required this.peg,
  });

  /// Changes on every chain reset.
  final String instanceId;
  final String policyAsset;
  final String genesisHash;
  final String liquidElectrumUrl;

  /// Always `regtest`.
  final String bitcoinNetwork;
  final String bitcoinElectrumUrl;
  final String bitcoinEsploraUrl;
  final String faucetUrl;
  final TestServerPeg peg;

  factory TestServerRegtest.fromJson(Map<String, dynamic> j) =>
      TestServerRegtest(
        instanceId: j['instance_id'] as String? ?? '',
        policyAsset: j['policy_asset'] as String? ?? '',
        genesisHash: j['genesis_hash'] as String? ?? '',
        liquidElectrumUrl: j['liquid_electrum_url'] as String? ?? '',
        bitcoinNetwork: j['bitcoin_network'] as String? ?? 'regtest',
        bitcoinElectrumUrl: j['bitcoin_electrum_url'] as String? ?? '',
        bitcoinEsploraUrl: j['bitcoin_esplora_url'] as String? ?? '',
        faucetUrl: j['faucet_url'] as String? ?? '',
        peg: TestServerPeg.fromJson(
          j['peg'] as Map<String, dynamic>? ?? const {},
        ),
      );
}

/// A profile's `peg` block. Only [provider] is always present.
class TestServerPeg {
  const TestServerPeg({
    required this.provider,
    this.peginConfirmations,
    this.pegoutConfirmations,
    this.pegoutMaxSat,
  });

  /// `native` (the lab's own Elements peg) or `sideswap`.
  final String provider;
  final int? peginConfirmations;
  final int? pegoutConfirmations;
  final int? pegoutMaxSat;

  factory TestServerPeg.fromJson(Map<String, dynamic> j) => TestServerPeg(
    provider: j['provider'] as String? ?? '',
    peginConfirmations: (j['pegin_confirmations'] as num?)?.toInt(),
    pegoutConfirmations: (j['pegout_confirmations'] as num?)?.toInt(),
    pegoutMaxSat: (j['pegout_max_sat'] as num?)?.toInt(),
  );
}

/// A profile's `testnet` block: links for display, never chain settings.
class TestServerTestnet {
  const TestServerTestnet({this.faucetUrl, this.peg});

  final String? faucetUrl;
  final TestServerPeg? peg;

  factory TestServerTestnet.fromJson(Map<String, dynamic> j) =>
      TestServerTestnet(
        faucetUrl: j['faucet_url'] as String?,
        peg: _map(j['peg'], TestServerPeg.fromJson),
      );
}

/// `check`: a live look at the joined server.
class TestServerCheck {
  const TestServerCheck({
    required this.reachable,
    required this.stale,
    this.error,
    this.serverInstanceId,
  });

  final bool reachable;

  /// Why not, when [reachable] is false.
  final String? error;

  /// The server's current chain instance, when it answered.
  final String? serverInstanceId;

  /// The server now says something else than the stored profile.
  final bool stale;

  factory TestServerCheck.fromJson(Map<String, dynamic> j) => TestServerCheck(
    reachable: j['reachable'] as bool? ?? false,
    error: j['error'] as String?,
    serverInstanceId: j['server_instance_id'] as String?,
    stale: j['stale'] as bool? ?? false,
  );
}

/// `applied`: what joining or leaving changed.
class TestServerApplied {
  const TestServerApplied({
    required this.liquidNetwork,
    required this.networkSwitched,
    required this.walletClosed,
    required this.regtestCacheReset,
  });

  /// `liquid-testnet` | `liquid-regtest` after the call.
  final String liquidNetwork;
  final bool networkSwitched;

  /// The engine closed the open wallet; the host reopens it.
  final bool walletClosed;

  /// The regtest chain caches were dropped; the next sync rescans.
  final bool regtestCacheReset;

  factory TestServerApplied.fromJson(Map<String, dynamic> j) =>
      TestServerApplied(
        liquidNetwork: j['liquid_network'] as String? ?? 'liquid-testnet',
        networkSwitched: j['network_switched'] as bool? ?? false,
        walletClosed: j['wallet_closed'] as bool? ?? false,
        regtestCacheReset: j['regtest_cache_reset'] as bool? ?? false,
      );
}

/// `active`: the servers in use now, each with where it came from.
class ActiveEndpoints {
  const ActiveEndpoints({
    required this.liquidNetwork,
    required this.envLocked,
    required this.orderbook,
    required this.liquid,
    required this.bitcoin,
  });

  /// `liquid-testnet` | `liquid-regtest`.
  final String liquidNetwork;

  /// `TEMPLAR_LIQUID_NETWORK` fixes the Liquid network for this run.
  final bool envLocked;
  final OrderbookEndpoints orderbook;
  final LiquidEndpoint liquid;
  final BitcoinEndpoint bitcoin;

  factory ActiveEndpoints.fromJson(Map<String, dynamic> j) => ActiveEndpoints(
    liquidNetwork: j['liquid_network'] as String? ?? 'liquid-testnet',
    envLocked: j['env_locked'] as bool? ?? false,
    orderbook: OrderbookEndpoints.fromJson(
      j['orderbook'] as Map<String, dynamic>? ?? const {},
    ),
    liquid: LiquidEndpoint.fromJson(
      j['liquid'] as Map<String, dynamic>? ?? const {},
    ),
    bitcoin: BitcoinEndpoint.fromJson(
      j['bitcoin'] as Map<String, dynamic>? ?? const {},
    ),
  );
}

/// A URL and where it came from: `env` | `profile` | `setting` | `default`.
class SourcedUrl {
  const SourcedUrl({required this.url, required this.source});

  final String url;
  final String source;

  /// How a person reads [source].
  String get sourceLabel => endpointSourceLabel(source);

  factory SourcedUrl.fromJson(Map<String, dynamic> j) => SourcedUrl(
    url: j['url'] as String? ?? '',
    source: j['source'] as String? ?? 'default',
  );
}

/// The order book's routes.
class OrderbookEndpoints {
  const OrderbookEndpoints({
    required this.origin,
    required this.book,
    required this.markets,
    required this.publish,
    required this.atomicSwaps,
  });

  final SourcedUrl origin;
  final SourcedUrl book;
  final SourcedUrl markets;

  /// Where `swap_publish` posts.
  final SourcedUrl publish;

  /// The HTLC v1 coordinator.
  final SourcedUrl atomicSwaps;

  /// The origin's host is this machine. Only then does the app offer the
  /// order book's admin page: anywhere else it is someone else's server.
  bool get isLoopback {
    final host = Uri.tryParse(origin.url)?.host.toLowerCase() ?? '';
    return host == '127.0.0.1' ||
        host == 'localhost' ||
        host == '::1' ||
        host == '[::1]';
  }

  factory OrderbookEndpoints.fromJson(Map<String, dynamic> j) {
    SourcedUrl at(String key) =>
        SourcedUrl.fromJson(j[key] as Map<String, dynamic>? ?? const {});
    return OrderbookEndpoints(
      origin: at('origin'),
      book: at('book'),
      markets: at('markets'),
      publish: at('publish'),
      atomicSwaps: at('atomic_swaps'),
    );
  }
}

/// The Liquid chain in use.
class LiquidEndpoint {
  const LiquidEndpoint({
    required this.network,
    required this.policyAsset,
    required this.paramsSource,
    required this.backend,
    required this.backendDescription,
    required this.backendSource,
    this.genesisHash,
  });

  /// `liquid-testnet` | `liquid-regtest`.
  final String network;
  final String policyAsset;

  /// A custom regtest's genesis hash; null for the stock ones.
  final String? genesisHash;
  final String paramsSource;

  /// `electrum` | `elements_rpc`.
  final String backend;

  /// Without credentials.
  final String backendDescription;
  final String backendSource;

  factory LiquidEndpoint.fromJson(Map<String, dynamic> j) => LiquidEndpoint(
    network: j['network'] as String? ?? 'liquid-testnet',
    policyAsset: j['policy_asset'] as String? ?? '',
    genesisHash: j['genesis_hash'] as String?,
    paramsSource: j['params_source'] as String? ?? 'default',
    backend: j['backend'] as String? ?? 'electrum',
    backendDescription: j['backend_description'] as String? ?? '',
    backendSource: j['backend_source'] as String? ?? 'default',
  );
}

/// The Bitcoin chain in use.
class BitcoinEndpoint {
  const BitcoinEndpoint({
    required this.network,
    required this.electrumUrl,
    required this.source,
  });

  /// `bitcoin-testnet` | `bitcoin-regtest`.
  final String network;
  final String electrumUrl;
  final String source;

  bool get isRegtest => network == 'bitcoin-regtest';

  /// `testnet` | `regtest`.
  String get shortName => isRegtest ? 'regtest' : 'testnet';

  factory BitcoinEndpoint.fromJson(Map<String, dynamic> j) => BitcoinEndpoint(
    network: j['network'] as String? ?? 'bitcoin-testnet',
    electrumUrl: j['electrum_url'] as String? ?? '',
    source: j['source'] as String? ?? 'default',
  );
}

/// How a person reads an endpoint source.
String endpointSourceLabel(String source) => switch (source) {
  'env' => 'environment variable',
  'profile' => 'test server',
  'setting' => 'app setting',
  _ => 'built-in default',
};

T? _map<T>(Object? raw, T Function(Map<String, dynamic>) decode) =>
    raw is Map<String, dynamic> ? decode(raw) : null;
