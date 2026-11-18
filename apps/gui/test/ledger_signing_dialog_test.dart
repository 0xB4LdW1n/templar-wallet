// The pre-sign address check is one step: the dialog shows the wallet's
// address for as long as the device shows it, the user confirms on the
// device, and signing follows. A device that reports another address is
// not this wallet's, and nothing is signed.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:templar_wallet/features/hardware/ledger_signing_dialog.dart';

const _address = 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjz05';

Future<void> _open(
  WidgetTester t, {
  required Completer<String> device,
  required Future<String> Function() task,
}) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LedgerSigningDialog(
          verifyAddress: () async => _address,
          verifyTask: () => device.future,
          task: task,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('the address is on screen while the device shows it', (t) async {
    final device = Completer<String>();
    final signing = Completer<String>();
    var signCalls = 0;
    await _open(
      t,
      device: device,
      task: () {
        signCalls++;
        return signing.future;
      },
    );

    // One step for the check, and the address to compare, before the device
    // has answered anything.
    expect(find.text('Check the address on the device'), findsOneWidget);
    expect(find.text('Show a wallet address on the device'), findsNothing);
    expect(find.text('Check it matches the device screen'), findsNothing);
    expect(find.text(_address), findsOneWidget);
    expect(signCalls, 0);

    // Confirmed on the device: signing starts, with no second question here.
    device.complete(_address);
    await t.pump();
    await t.pump();
    expect(signCalls, 1);
    expect(find.text('Confirm on your Ledger'), findsOneWidget);
    expect(find.text(_address), findsNothing);
  });

  testWidgets('another address from the device stops before signing', (
    t,
  ) async {
    final device = Completer<String>();
    var signCalls = 0;
    await _open(
      t,
      device: device,
      task: () async {
        signCalls++;
        return 'txid';
      },
    );

    device.complete('tb1qsomeoneelse000000000000000000000000000');
    await t.pump();
    await t.pump();
    expect(signCalls, 0);
    expect(find.text('Signing failed'), findsOneWidget);
    expect(find.textContaining('Nothing was signed'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}
