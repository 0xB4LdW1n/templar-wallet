// Receive lists the newest eight previous addresses and hands the rest to
// the All addresses page; Liquid, with its one reused address, lists none.
// Desktop arm only: AppLayout.isPhone needs a mobile platform, which a host
// test cannot be (see docs/decisions/0005-mobile-shell.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/receive/models/address_info.dart';
import 'package:templar_wallet/features/receive/receive_addresses_screen.dart';
import 'package:templar_wallet/features/receive/receive_screen.dart';
import 'package:templar_wallet/services/address_label_store.dart';

class _StubBridge implements WalletBridge {
  _StubBridge({this.previousCount = 12});
  final int previousCount;

  @override
  Future<AddressInfo> generateReceiveAddress(
    String walletId,
    String asset, {
    bool fresh = false,
  }) async => AddressInfo(
    address: asset == 'BTC'
        ? 'tb1qcurrent000000000000000000000000000000ab'
        : 'tlq1qqcurrentliquidaddress00000000000000000000000000000000000000000000000000000000000000ab',
    index: previousCount,
    asset: asset,
    derivationPath: "m/84'/1'/0'/0/$previousCount",
  );

  @override
  Future<List<AddressInfo>> listPreviousAddresses(
    String walletId,
    String asset,
  ) async => [
    for (var i = 0; i < previousCount; i++)
      AddressInfo(
        address:
            'tb1qprev${i.toString().padLeft(2, '0')}'
            '0000000000000000000000000000000ab',
        index: i,
        asset: asset,
        receivedSats: i.isEven ? 1000 * (i + 1) : 0,
        label: i == 3 ? 'Faucet' : null,
      ),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(Widget child) => MaterialApp(
  home: ChangeNotifierProvider<AppState>(
    create: (_) => AppState(),
    child: child,
  ),
);

void _desktopWindow(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AddressLabelStore.instance.debugReset();
  });

  testWidgets('Receive shows the newest eight and offers the rest', (t) async {
    _desktopWindow(t);
    await t.pumpWidget(_host(ReceiveScreen(bridge: _StubBridge())));
    await t.pumpAndSettle();

    expect(find.text('Previous addresses'), findsOneWidget);
    // Newest first: #11 down to #4 are rows, #3 and below are not.
    expect(find.text('#11'), findsOneWidget);
    expect(find.text('#4'), findsOneWidget);
    expect(find.text('#3'), findsNothing);
    expect(find.text('#0'), findsNothing);
    expect(find.text('Show all'), findsOneWidget);
  });

  testWidgets('a short list has no hidden count', (t) async {
    _desktopWindow(t);
    await t.pumpWidget(
      _host(ReceiveScreen(bridge: _StubBridge(previousCount: 3))),
    );
    await t.pumpAndSettle();

    expect(find.text('#2'), findsOneWidget);
    expect(find.text('#0'), findsOneWidget);
    expect(find.text('Show all'), findsOneWidget);
    expect(find.textContaining('more)'), findsNothing);
  });

  testWidgets('the All addresses page lists every one with amounts', (t) async {
    _desktopWindow(t);
    await t.pumpWidget(
      _host(ReceiveAddressesScreen(asset: 'BTC', bridge: _StubBridge())),
    );
    await t.pumpAndSettle();

    expect(find.text('All addresses'), findsOneWidget);
    expect(find.textContaining('13 addresses'), findsOneWidget);
    // The current unused address leads, marked as such.
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    // Every previous one, oldest included, with its label where it has one.
    expect(find.text('#0'), findsOneWidget);
    expect(find.text('#3'), findsOneWidget);
    expect(find.text('Faucet'), findsOneWidget);
    // Amounts, in the unit the app is set to (coins by default): #0
    // received 1,000 sats, #2 3,000 — each figure drawn once.
    expect(find.text('0.00001000'), findsOneWidget);
    expect(find.text('0.00003000'), findsOneWidget);
    expect(find.text('Back to Receive'), findsOneWidget);
  });

  testWidgets('an address takes a label from its row and keeps it', (t) async {
    _desktopWindow(t);
    await t.pumpWidget(
      _host(ReceiveAddressesScreen(asset: 'BTC', bridge: _StubBridge())),
    );
    await t.pumpAndSettle();

    // Every row carries the three controls: label, QR, copy.
    expect(find.byTooltip('Show QR'), findsNWidgets(13));
    expect(find.byTooltip('Copy address'), findsNWidgets(13));

    // The newest previous address (#11) is the second row.
    await t.tap(find.byIcon(Icons.label_outlined).at(1));
    await t.pumpAndSettle();
    expect(find.text('Label address'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Rent');
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();

    // On the row at once, and on disk for the next launch.
    expect(find.text('Rent'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('address_labels_v1'), contains('Rent'));

    // The user's label replaces nothing it does not own: the engine's
    // label on #3 is still there.
    expect(find.text('Faucet'), findsOneWidget);
  });

  testWidgets('the QR control opens the address with its code', (t) async {
    _desktopWindow(t);
    await t.pumpWidget(
      _host(ReceiveAddressesScreen(asset: 'BTC', bridge: _StubBridge())),
    );
    await t.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);

    await t.tap(find.byTooltip('Show QR').at(1));
    await t.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('Address #11'), findsOneWidget);
    expect(find.text('Used'), findsWidgets);
    expect(find.text('Copy address'), findsOneWidget);
  });
}
