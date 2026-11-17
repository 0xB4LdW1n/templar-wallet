// Wording that names the chain follows the active networks once a test
// server is joined: the new-wallet network, the dashboard badge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/mock_wallet_bridge.dart';
import 'package:templar_wallet/features/create_wallet/create_wallet_screen.dart';
import 'package:templar_wallet/features/dashboard/dashboard_screen.dart';

Future<String> _labels(WidgetTester tester, {required bool lab}) async {
  final bridge = MockWalletBridge();
  final state = (await tester.runAsync(() async {
    if (lab) await bridge.setTestServer('http://127.0.0.1:8196');
    return AppState()
      ..setLiquidNetworkInfo(await bridge.getLiquidNetwork())
      ..setTestServerInfo(await bridge.getTestServer());
  }))!;
  late String out;
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            out =
                '${activeNetworkLabel(context)} ${networkBadgeLabel(context)}';
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return out;
}

void main() {
  testWidgets('a new wallet and the badge say regtest on a lab', (
    tester,
  ) async {
    expect(await _labels(tester, lab: true), 'Regtest REGTEST');
  });

  testWidgets('and testnet off it', (tester) async {
    expect(await _labels(tester, lab: false), 'Testnet TESTNET');
  });
}
