/// Switching the Liquid network, in one place.
///
/// Two screens move the wallet between the public testnet and a local
/// regtest: Settings › Network & Sync (deliberately) and the Templar Protocol request
/// screen (because a site asked for a chain the wallet is not on). The
/// consequence is the same either way — the engine closes the open wallet —
/// so the confirmation, the wording and the clean-up live here and neither
/// caller can drift from the other.
///
/// What is left to the caller: its own busy flag, where to go afterwards
/// (Settings returns to the picker, the request screen stays and retries) and
/// how to show [LiquidNetworkSwitchError].
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/glass_dialog.dart';
import '../../theme/app_typography.dart';

/// A refusal from the engine, already stripped of its FFI prefix.
class LiquidNetworkSwitchError implements Exception {
  const LiquidNetworkSwitchError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Engine errors as a user reads them.
String liquidNetworkErrorText(Object e) =>
    e.toString().replaceFirst('Exception: wallet-ffi: ', '');

/// Re-reads the joined test server and the servers in use into [appState].
/// Best-effort: on failure the last answer stays.
Future<void> refreshTestServerInfo(
  AppState appState, {
  WalletBridge? bridge,
}) async {
  try {
    appState.setTestServerInfo(await (bridge ?? walletBridge).getTestServer());
  } catch (_) {
    // Wording falls back to the last known state; Settings shows the error.
  }
}

/// Asks to move Liquid to [target] (`testnet` | `regtest`), then does it.
///
/// [policyAsset] is the regtest LBTC asset id and is ignored on testnet.
/// Returns null when the user cancels; otherwise the engine's new state and
/// whether an open wallet was closed by the switch — the caller navigates on
/// that, since a shell screen cannot keep showing another chain's balances.
/// Throws [LiquidNetworkSwitchError] when the engine refuses.
Future<({LiquidNetworkInfo info, bool walletClosed})?> switchLiquidNetwork(
  BuildContext context, {
  required String target,
  String? policyAsset,
}) async {
  final appState = context.read<AppState>();
  final hasWallet = appState.activeWalletId != null;
  // With a test server joined, Bitcoin runs on the lab's regtest beside its
  // Liquid regtest and on the public testnet otherwise: it moves too.
  final bitcoinNote = appState.testServer?.configured ?? false
      ? 'Bitcoin moves with it: ${target == 'regtest' ? 'the test server\'s regtest' : 'the public testnet'}.'
      : 'Bitcoin is not affected.';

  final confirmed = await showAppDialog<bool>(
    context,
    barrierDismissible: false,
    builder: (ctx) => GlassDialog(
      title: 'Switch Liquid network to $target?',
      icon: Icons.swap_horiz,
      actions: [
        SecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.pop(ctx, false),
        ),
        PrimaryButton(
          label: 'Switch',
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
      child: Text(
        hasWallet
            ? 'The open wallet will be closed. Open it again and sync: its '
                  'Liquid balance and addresses belong to the $target chain from '
                  'then on. $bitcoinNote'
            : 'Every wallet you open will use the $target chain for Liquid '
                  'until you switch back. $bitcoinNote',
        style: AppTypography.body,
      ),
    ),
  );
  if (confirmed != true) return null;

  final LiquidNetworkInfo next;
  try {
    next = await walletBridge.setLiquidNetwork(
      target,
      policyAsset: target == 'regtest' ? policyAsset : null,
    );
  } catch (e) {
    throw LiquidNetworkSwitchError(liquidNetworkErrorText(e));
  }

  appState.setLiquidNetworkInfo(next);
  // Bitcoin follows: beside a joined test server's regtest it is the lab's
  // Bitcoin regtest, on testnet the public testnet.
  await refreshTestServerInfo(appState);
  // The engine closed the wallet: nothing may keep showing it as open.
  if (hasWallet) appState.setActiveWallet(null);

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          hasWallet
              ? 'Liquid network is now ${next.shortName}. Open your wallet and sync.'
              : 'Liquid network is now ${next.shortName}.',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
  return (info: next, walletClosed: hasWallet);
}
