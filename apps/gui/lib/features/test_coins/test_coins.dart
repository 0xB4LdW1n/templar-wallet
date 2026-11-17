/// Test coins from the joined test server's faucet, asked for from inside
/// the wallet (`test_server_faucet`).
///
/// Offered only when a test server with a faucet is joined and the engine
/// runs on its regtest (`TestServerInfo.faucetAvailable`), and only for the
/// chains the open wallet has: a Bitcoin-only wallet gets no L-BTC action.
/// Nothing is signed: the engine derives a fresh address of the wallet and
/// the faucet pays it. The lab confirms faucet payments in its next block
/// (about 30 seconds), so one sync is scheduled a little after that and the
/// coins show without the user going looking for them.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../app/app_state.dart';
import '../../app/shell.dart' show syncActiveWallet;
import '../../bridge/wallet_bridge.dart';
import '../../shared/asset_amount.dart';
import 'faucet_error.dart';

export 'faucet_error.dart';

/// The faucet's coins this wallet can receive now; empty when no faucet can
/// be asked (no lab, or the engine is on testnet).
List<FaucetAsset> testCoinsFor(AppState state) {
  final server = state.testServer;
  if (server == null || !server.faucetAvailable) return const [];
  return [
    for (final a in server.faucet!.assets)
      if (a.isBitcoin ? state.activeWalletBitcoin : state.activeWalletLiquid) a,
  ];
}

/// The faucet's entry for a coin of this wallet: `btc`, or L-BTC on Liquid.
FaucetAsset? faucetCoin(AppState state, {required bool bitcoin}) {
  for (final a in testCoinsFor(state)) {
    if (bitcoin ? a.isBitcoin : (a.isLiquid && a.isNativeCoin)) return a;
  }
  return null;
}

/// How a faucet coin is named on a button: `BTC`, `L-BTC`, `USDt`.
String faucetCoinLabel(FaucetAsset a) {
  if (a.isBitcoin) return 'BTC';
  if (a.isNativeCoin) return 'L-BTC';
  return a.ticker.isNotEmpty ? a.ticker : a.asset;
}

/// An amount of a faucet coin in its own unit: `0.01000000 BTC`.
String faucetAmountText(int baseUnits, int precision, String unit) =>
    '${AssetAmount.format(baseUnits, precision, group: true)} $unit';

/// Where one request for one coin stands.
class TestCoinRequest {
  const TestCoinRequest({this.busy = false, this.payment, this.error});

  final bool busy;
  final FaucetPayment? payment;
  final FaucetError? error;
}

/// The requests of this session, per wallet and coin, so the Dashboard card
/// and the action on Receive or Peg show the same state.
class TestCoins extends ChangeNotifier {
  TestCoins._();

  static final TestCoins instance = TestCoins._();

  /// How long after a payment the wallet is synced: past the lab's next
  /// block, which confirms faucet payments within about 30 seconds.
  static Duration syncDelay = const Duration(seconds: 35);

  final Map<String, TestCoinRequest> _requests = {};
  final Map<String, Timer> _syncs = {};

  static String _key(String walletId, FaucetAsset a) =>
      '$walletId|${a.asset.toLowerCase()}';

  TestCoinRequest? requestOf(String? walletId, FaucetAsset a) =>
      walletId == null ? null : _requests[_key(walletId, a)];

  /// Ask the faucet for [asset] for the active wallet. Returns the payment,
  /// or null when it was refused (the reason is in [requestOf]).
  Future<FaucetPayment?> request(
    AppState state,
    WalletBridge bridge,
    FaucetAsset asset,
  ) async {
    final walletId = state.activeWalletId;
    if (walletId == null) return null;
    final key = _key(walletId, asset);
    if (_requests[key]?.busy ?? false) return null;
    _requests[key] = const TestCoinRequest(busy: true);
    notifyListeners();
    try {
      final payment = await bridge.testServerFaucet(walletId, asset.asset);
      _requests[key] = TestCoinRequest(payment: payment);
      notifyListeners();
      _scheduleSync(state, bridge, walletId);
      return payment;
    } catch (e) {
      _requests[key] = TestCoinRequest(error: FaucetError.from(e));
      notifyListeners();
      return null;
    }
  }

  /// One sync of [walletId] after [syncDelay], if it is still the open
  /// wallet. Several requests in a row share one sync.
  void _scheduleSync(AppState state, WalletBridge bridge, String walletId) {
    _syncs[walletId]?.cancel();
    _syncs[walletId] = Timer(syncDelay, () {
      _syncs.remove(walletId);
      if (state.activeWalletId != walletId) return;
      if (state.syncState == SyncState.syncing) return;
      unawaited(syncActiveWallet(state, bridge));
    });
  }

  /// Forget every request and cancel the pending syncs (tests).
  @visibleForTesting
  void reset() {
    for (final t in _syncs.values) {
      t.cancel();
    }
    _syncs.clear();
    _requests.clear();
    notifyListeners();
  }
}
