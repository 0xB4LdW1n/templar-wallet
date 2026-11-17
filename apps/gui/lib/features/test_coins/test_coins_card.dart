/// The places a user asks the test server's faucet for coins: a card on the
/// Dashboard listing every coin it pays, and one action for one coin where
/// that coin is needed (Receive, Peg).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/list_rows.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'test_coins.dart';

/// The line under a coin: what one request pays, what is on its way, or why
/// the faucet said no. Null colour = the secondary ink.
(String, Color?) testCoinStatus(
  AppScheme s,
  FaucetAsset coin,
  TestCoinRequest? r,
) {
  final unit = faucetCoinLabel(coin);
  if (r?.busy ?? false) return ('Asking the faucet…', null);
  final paid = r?.payment;
  if (paid != null) {
    return (
      '${faucetAmountText(paid.amountSat, paid.precision, unit)} on its way: '
          'it shows after the test server\'s next block, in about 30 seconds',
      null,
    );
  }
  final err = r?.error;
  if (err != null) return (err.message, s.warning);
  final each = coin.defaultSat;
  return (
    each == null
        ? 'Free ${coin.isBitcoin ? 'regtest' : 'Liquid regtest'} coins'
        : '${faucetAmountText(each, coin.precision, unit)} per request',
    null,
  );
}

IconData _coinIcon(FaucetAsset coin) => coin.isBitcoin
    ? Icons.currency_bitcoin_outlined
    : coin.isNativeCoin
    ? Icons.water_drop_outlined
    : Icons.token_outlined;

/// Dashboard: every coin the faucet pays this wallet, one action each.
/// Draws nothing when no faucet can be asked.
class TestCoinsCard extends StatelessWidget {
  const TestCoinsCard({super.key, this.bridge});

  final WalletBridge? bridge;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final coins = testCoinsFor(st);
    if (coins.isEmpty) return const SizedBox.shrink();
    final s = AppScheme.of(context);
    final lab = st.testServerName ?? 'the test server';
    return ListenableBuilder(
      listenable: TestCoins.instance,
      builder: (context, _) => Column(
        key: const Key('test-coins-card'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ListSectionLabel(label: 'Test coins'),
          ListCard(
            children: [for (final coin in coins) _row(context, st, s, coin)],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Paid to this wallet by the faucet of $lab: coins of its regtest, '
            'with no value outside it',
            style: AppTypography.caption.copyWith(color: s.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, AppState st, AppScheme s, FaucetAsset c) {
    final r = TestCoins.instance.requestOf(st.activeWalletId, c);
    final (status, ink) = testCoinStatus(s, c, r);
    final unit = faucetCoinLabel(c);
    return ListRow(
      key: Key('test-coin-${c.asset.toLowerCase()}'),
      icon: _coinIcon(c),
      tint: c.isBitcoin ? s.bitcoin : (c.isNativeCoin ? s.liquid : null),
      title: c.name.isNotEmpty ? c.name : unit,
      subtitle: status,
      subtitleColor: ink,
      trailing: SecondaryButton(
        label: 'Get $unit',
        dense: true,
        isLoading: r?.busy ?? false,
        onPressed: (r?.busy ?? false)
            ? null
            : () => TestCoins.instance.request(st, bridge ?? walletBridge, c),
      ),
    );
  }
}

/// One coin's faucet action with its status under it — on Receive for the
/// coin being received, on Peg for the coin a deposit needs. Draws nothing
/// when the faucet does not pay that coin here.
class TestCoinAction extends StatelessWidget {
  const TestCoinAction({
    super.key,
    required this.bitcoin,
    this.bridge,
    this.label,
  });

  /// BTC when true, else L-BTC.
  final bool bitcoin;
  final WalletBridge? bridge;

  /// The button's words; default `Get test BTC` / `Get test L-BTC`.
  final String? label;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final coin = faucetCoin(st, bitcoin: bitcoin);
    if (coin == null) return const SizedBox.shrink();
    final s = AppScheme.of(context);
    return ListenableBuilder(
      listenable: TestCoins.instance,
      builder: (context, _) {
        final r = TestCoins.instance.requestOf(st.activeWalletId, coin);
        final (status, ink) = testCoinStatus(s, coin, r);
        final busy = r?.busy ?? false;
        return Column(
          key: Key('test-coin-action-${bitcoin ? 'btc' : 'lbtc'}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SecondaryButton(
              label: label ?? 'Get test ${faucetCoinLabel(coin)}',
              icon: Icons.water_drop_outlined,
              isLoading: busy,
              onPressed: busy
                  ? null
                  : () => TestCoins.instance.request(
                      st,
                      bridge ?? walletBridge,
                      coin,
                    ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              status,
              style: AppTypography.caption.copyWith(
                color: ink ?? s.inkSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}
