/// Joining and leaving a Templar test server, in one place.
///
/// Settings › Network › Nodes and explorers joins and leaves deliberately; the swap market
/// re-joins when the lab's chains were reset. Either way the engine closes
/// the open wallet, so — as with [switchLiquidNetwork] — the confirmation,
/// the wording and the clean-up live here and the callers only decide where
/// to go afterwards (back to the wallet picker when a wallet was closed).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/app_state.dart';
import '../../bridge/bridge_provider.dart';
import '../../bridge/wallet_bridge.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../theme/app_scheme.dart';
import '../../theme/app_typography.dart';
import 'liquid_network_switch.dart';

/// Where the Test server card lives, as the user finds it.
const String kTestServerSettingsPath =
    'Settings › Network › Nodes and explorers';

/// A refusal from the engine, already stripped of its FFI prefix.
class TestServerError implements Exception {
  const TestServerError(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Why [input] cannot be a test server's base URL, or null when its shape is
/// plausible. User feedback only: the engine validates the URL and the
/// server's config, and its answer is the one that counts.
String? testServerUrlProblem(String input) {
  final text = input.trim();
  if (text.isEmpty) return 'Enter the test server URL.';
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) {
    return 'Start with http:// or https://, e.g. http://127.0.0.1:8096';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'Only http:// and https:// URLs are accepted.';
  }
  if (uri.host.isEmpty) return 'The URL needs a host.';
  if (uri.userInfo.isNotEmpty) return 'Leave user names and passwords out.';
  if (uri.hasQuery || uri.hasFragment) {
    return 'Use the server\'s base URL, without ? or #.';
  }
  return null;
}

/// The outcome a caller acts on.
typedef TestServerSwitch = ({TestServerInfo info, bool walletClosed});

/// Asks to join (or, with [rejoin], to re-apply) the test server at [url],
/// then does it; [onConfirmed] runs once the user said yes (a busy flag). Returns null when the user cancels. Throws
/// [TestServerError] when the engine refuses; nothing is applied then.
Future<TestServerSwitch?> joinTestServer(
  BuildContext context,
  String url, {
  bool rejoin = false,
  WalletBridge? bridge,
  VoidCallback? onConfirmed,
}) async {
  final api = bridge ?? walletBridge;
  final appState = context.read<AppState>();
  final hasWallet = appState.activeWalletId != null;
  final envLocked = appState.testServer?.active.envLocked ?? false;
  final current = appState.liquidNetworkName;

  final what = rejoin
      ? 'The test server runs a new chain. Re-joining applies it: regtest '
            'balances and history are synced again from scratch. Keys and the '
            'wallet list are not touched.'
      : 'Liquid and Bitcoin then run on the test server\'s regtest chains '
            '(el1… and bcrt1… addresses), and the swap market uses its order '
            'book.';
  final lock = envLocked
      ? ' TEMPLAR_LIQUID_NETWORK fixes Liquid to $current for this session, '
            'so the regtest chains apply only once the variable is unset.'
      : '';
  final close = hasWallet
      ? ' The open wallet will be closed: open it again and sync.'
      : '';

  final confirmed = await _confirm(
    context,
    title: rejoin ? 'Re-join the test server?' : 'Join this test server?',
    icon: Icons.dns_outlined,
    body: '$what$lock$close',
    action: rejoin ? 'Re-join' : 'Join',
  );
  if (confirmed != true) return null;
  onConfirmed?.call();

  final TestServerInfo next;
  try {
    next = await api.setTestServer(url);
  } catch (e) {
    throw TestServerError(liquidNetworkErrorText(e));
  }
  await _applied(appState, next, hasWallet, api);

  if (context.mounted) {
    final name = appState.testServerName ?? 'the test server';
    final onLab = next.active.liquid.network == 'liquid-regtest';
    final where = onLab
        ? 'Liquid and Bitcoin now run on its regtest.'
        : 'Liquid stays on ${next.active.liquid.network.replaceFirst('liquid-', '')}: '
              'TEMPLAR_LIQUID_NETWORK fixes it.';
    _tell(
      context,
      '${rejoin ? 'Re-joined' : 'Joined'} $name. $where'
      '${hasWallet ? ' Open your wallet and sync.' : ''}',
    );
  }
  return (info: next, walletClosed: hasWallet);
}

/// Asks to leave the joined test server, then does it. Returns null when the
/// user cancels. Throws [TestServerError] when the engine refuses.
Future<TestServerSwitch?> leaveTestServer(
  BuildContext context, {
  WalletBridge? bridge,
  VoidCallback? onConfirmed,
}) async {
  final api = bridge ?? walletBridge;
  final appState = context.read<AppState>();
  final hasWallet = appState.activeWalletId != null;
  final name = appState.testServerName ?? 'the test server';

  final confirmed = await _confirm(
    context,
    title: 'Leave $name?',
    icon: Icons.logout_rounded,
    body:
        'Liquid and Bitcoin return to the public testnet, and the order book '
        'and servers to their defaults. The '
        'test server\'s regtest data is dropped from this device; keys and '
        'the wallet list are not touched.'
        '${hasWallet ? ' The open wallet will be closed: open it again and sync.' : ''}',
    action: 'Leave',
  );
  if (confirmed != true) return null;
  onConfirmed?.call();

  final TestServerInfo next;
  try {
    next = await api.clearTestServer();
  } catch (e) {
    throw TestServerError(liquidNetworkErrorText(e));
  }
  await _applied(appState, next, hasWallet, api);

  if (context.mounted) {
    _tell(
      context,
      'Left $name. Liquid is on ${appState.liquidNetworkName}.'
      '${hasWallet ? ' Open your wallet and sync.' : ''}',
    );
  }
  return (info: next, walletClosed: hasWallet);
}

/// The engine's answer, into the app: the servers in use, the Liquid
/// network, and no open wallet (the engine always closed it).
Future<void> _applied(
  AppState appState,
  TestServerInfo next,
  bool hadWallet,
  WalletBridge api,
) async {
  appState.setTestServerInfo(next);
  appState.setTestServerStale(false);
  appState.testServerChecked = true;
  try {
    appState.setLiquidNetworkInfo(await api.getLiquidNetwork());
  } catch (_) {
    // The shell strip and wording then wait for the next read.
  }
  if (hadWallet) appState.setActiveWallet(null);
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required IconData icon,
  required String body,
  required String action,
}) => showAppDialog<bool>(
  context,
  barrierDismissible: false,
  builder: (ctx) => PromptDialog(
    title: title,
    icon: icon,
    actions: [
      GhostButton(label: 'Cancel', onPressed: () => Navigator.pop(ctx, false)),
      PrimaryButton(label: action, onPressed: () => Navigator.pop(ctx, true)),
    ],
    child: Text(
      body,
      style: AppTypography.body.copyWith(color: AppScheme.of(ctx).inkSecondary),
    ),
  ),
);

void _tell(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
  );
}

/// The light stale check: once per session, on first use of a screen that
/// needs the lab (the swap market), ask the joined server whether its chains
/// were reset. No loop, no retry; Settings has a "Check now" for more.
Future<void> checkTestServerOnce(
  AppState appState, {
  WalletBridge? bridge,
}) async {
  if (appState.testServerChecked) return;
  if (!(appState.testServer?.configured ?? false)) return;
  appState.testServerChecked = true;
  try {
    final info = await (bridge ?? walletBridge).getTestServer(check: true);
    appState.setTestServerInfo(info);
    appState.setTestServerStale(info.isStale);
  } catch (_) {
    // An unreachable lab is not an error (check.reachable); a failed call
    // leaves the stored state as it was.
  }
}
