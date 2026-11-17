// The loaded-PSBT panel.
//
// Its signer list is the same block the multisig hand-off sheets draw, so it
// is asserted here against the counts a real inspection would carry: a met
// quorum must never stamp a key that has not signed, and the header must
// report what the inspection said.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/psbt/cosign_view.dart';
import 'package:templar_wallet/features/psbt/models/psbt_inspection.dart';
import 'package:templar_wallet/shared/widgets/seal_mark.dart';
import 'package:templar_wallet/shared/widgets/signer_donut.dart';

/// A 2-of-3 with [signed] of the three signatures already collected.
PsbtInspection inspection({required int signed, int? required_ = 2}) =>
    PsbtInspection(
      inputs: const [
        PsbtInput(
          outpoint: 'aa11:0',
          amountSats: 1234567,
          displayAmount: '0.01234567 BTC',
        ),
      ],
      outputs: const [
        PsbtOutput(
          address: 'tb1qrecipient',
          amountSats: 100000,
          displayAmount: '100000 sats',
        ),
      ],
      feeSats: 1560,
      feeDisplay: '1560 sats',
      sigsPresent: signed,
      sigsRequired: required_,
      signers: [
        for (var i = 0; i < 3; i++)
          PsbtSigner(fingerprint: 'fp0000$i', hasSigned: i < signed),
      ],
      policyHint: '2-of-3 multisig',
      rawPsbt: 'cHNidP8BAH0=',
    );

Widget host(
  PsbtInspection i, {
  String? signedPsbt,
  bool allowBroadcast = true,
}) => MaterialApp(
  home: ChangeNotifierProvider<AppState>(
    create: (_) => AppState(),
    child: Scaffold(
      body: SingleChildScrollView(
        child: PsbtInspectionPanel(
          inspection: i,
          chain: CosignChain.bitcoin,
          signedInspection: null,
          signing: false,
          signedPsbt: signedPsbt,
          broadcasting: false,
          txid: null,
          copied: false,
          allowBroadcast: allowBroadcast,
          onSign: () {},
          onSignWithDevice: () {},
          onBroadcast: () {},
          onCopy: () {},
          onDecline: () {},
        ),
      ),
    ),
  ),
);

Future<void> pumpPanel(
  WidgetTester t,
  PsbtInspection i, {
  String? signedPsbt,
  bool allowBroadcast = true,
}) async {
  t.view.physicalSize = const Size(1400, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    host(i, signedPsbt: signedPsbt, allowBroadcast: allowBroadcast),
  );
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('lists the signers and counts them in the header', (t) async {
    await pumpPanel(t, inspection(signed: 1));

    expect(find.byType(SignerList), findsOneWidget);
    expect(find.text('Needs 1 more signature'), findsOneWidget);
    expect(find.text('1 of 2 signatures'), findsOneWidget);
    // One row per signer; a seal per row, and one per required signature
    // in the tally beside the header.
    expect(find.text('Signed'), findsOneWidget);
    expect(find.text('Not signed'), findsNWidgets(2));
    expect(find.byType(SealMark), findsNWidgets(3 + 2));
  });

  testWidgets('an unsigned PSBT lists every signer as not signed', (t) async {
    await pumpPanel(t, inspection(signed: 0));
    expect(find.text('Needs 2 more signatures'), findsOneWidget);
    expect(find.text('0 of 2 signatures'), findsOneWidget);
    expect(find.text('Signed'), findsNothing);
    expect(find.text('Not signed'), findsNWidgets(3));
  });

  testWidgets('a met quorum still shows the third signer as not signed', (
    t,
  ) async {
    // 2-of-3 with two signatures: complete, but the third key has not
    // signed — the list must not round that up.
    await pumpPanel(t, inspection(signed: 2));
    expect(find.text('Fully signed, ready to broadcast'), findsOneWidget);
    expect(find.text('2 of 2 signatures'), findsOneWidget);
    expect(find.text('Not signed'), findsOneWidget);
  });

  testWidgets('no threshold in the policy still reports what was collected', (
    t,
  ) async {
    await pumpPanel(t, inspection(signed: 1, required_: null));
    expect(find.text('1 signature collected'), findsOneWidget);
    // No quorum stated: no row of seals for it either.
    expect(find.byType(SealTally), findsNothing);
  });

  testWidgets('a loaded PSBT keeps its signing actions', (t) async {
    await pumpPanel(t, inspection(signed: 1));

    expect(find.byType(SignerList), findsOneWidget);
    expect(find.text('Sign'), findsOneWidget);
    expect(find.text('Sign with device'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });

  testWidgets('a complete quorum offers broadcast', (t) async {
    await pumpPanel(t, inspection(signed: 2));
    expect(find.text('Finalize and broadcast'), findsOneWidget);
  });

  testWidgets(
    'where broadcasting is not this surface\'s job, it is not offered',
    (t) async {
      // A co-signer on a phone: the session that started the transaction
      // broadcasts; this one signs and hands the copy back.
      await pumpPanel(t, inspection(signed: 2), allowBroadcast: false);
      expect(find.text('Finalize and broadcast'), findsNothing);
      expect(find.text('Sign'), findsOneWidget);
      await pumpPanel(
        t,
        inspection(signed: 2),
        signedPsbt: 'cHNidP8BAH0=',
        allowBroadcast: false,
      );
      expect(find.text('Finalize and broadcast'), findsNothing);
      expect(find.textContaining('broadcast from there'), findsOneWidget);
    },
  );

  testWidgets('the panel shows the transaction once, not twice', (t) async {
    // The loaded PSBT used to have a second copy of itself behind a "Raw
    // PSBT" expander at the foot of the panel, under the section that already
    // prints it. One transaction, one code box.
    await pumpPanel(t, inspection(signed: 1), signedPsbt: 'cHNidP8BAH0=');
    expect(find.text('Raw PSBT'), findsNothing);
    expect(find.text('Raw PSET'), findsNothing);
  });

  testWidgets('a signed PSBT can leave as a QR, a file or text', (t) async {
    // Copy alone is the one route that goes nowhere on a phone: no second
    // window to paste into, and no way to hand base64 to a coordinator.
    await pumpPanel(t, inspection(signed: 1), signedPsbt: 'cHNidP8BAH0=');
    expect(find.text('Signed PSBT'), findsOneWidget);
    expect(find.text('Show QR'), findsOneWidget);
    expect(find.text('Copy PSBT'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'Save .psbt file' || w.data == 'Share .psbt'),
      ),
      findsOneWidget,
    );
  });
}
