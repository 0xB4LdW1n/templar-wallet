// The Liquid page's pieces: the split ring (ShareDonut); the asset detail,
// which opens as the app's dialog — not a bottom sheet — on desktop; and
// "Issued assets", which carries the three asset operations over the list
// of what this wallet issued, each asset kept apart from its reissuance
// token.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/features/dashboard/models/dashboard_data.dart';
import 'package:templar_wallet/app/routes.dart';
import 'package:templar_wallet/features/liquid/asset_detail_dialog.dart';
import 'package:templar_wallet/features/liquid/liquid_issued.dart';
import 'package:templar_wallet/services/issued_asset_store.dart';
import 'package:templar_wallet/shared/widgets/share_donut.dart';

Widget _host(Widget child) => MaterialApp(
  theme: ThemeData(brightness: Brightness.dark),
  home: Scaffold(body: Center(child: child)),
);

const _lbtc = ShareSlice(
  id: 'lbtc',
  label: 'Liquid Bitcoin',
  amount: '0.00500000 LBTC',
  color: Colors.teal,
  value: 750000,
);
const _gold = ShareSlice(
  id: 'gold',
  label: 'Gold note',
  amount: '2 GOLD',
  color: Colors.amber,
  value: 250000,
);
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('ShareDonut', () {
    Widget donut() => _host(
      const SizedBox(
        width: 360,
        child: ShareDonut(
          slices: [_lbtc, _gold],
          totalLabel: 'Valued',
          totalValue: '€500.00',
          footnote: '1 asset without a price',
          legendBeside: false,
        ),
      ),
    );

    testWidgets('states the whole with nothing selected', (t) async {
      await t.pumpWidget(donut());
      await t.pumpAndSettle();
      expect(find.text('Valued'), findsOneWidget);
      expect(find.text('€500.00'), findsOneWidget);
      // Shares come from the values handed in, one line per part: the
      // amounts stay out of the legend.
      expect(find.text('75%'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('0.00500000 LBTC'), findsNothing);
      // What has no price has no slice and no row: one line counts it.
      expect(find.text('1 asset without a price'), findsOneWidget);
    });

    testWidgets('a tapped legend row takes the middle; a second tap clears '
        'it', (t) async {
      await t.pumpWidget(donut());
      await t.pumpAndSettle();

      await t.tap(find.text('Gold note'));
      await t.pumpAndSettle();
      // The middle now names the part, its share and its amount.
      expect(find.text('Valued'), findsNothing);
      expect(find.text('Gold note'), findsNWidgets(2));
      expect(find.text('25%'), findsNWidgets(2));
      expect(find.text('2 GOLD'), findsOneWidget);

      await t.tap(find.text('Gold note').last);
      await t.pumpAndSettle();
      expect(find.text('Valued'), findsOneWidget);
      expect(find.text('2 GOLD'), findsNothing);
    });
  });

  testWidgets('the asset detail opens as a dialog on desktop', (t) async {
    SharedPreferences.setMockInitialValues({});
    final appState = AppState();
    const asset = AssetBalance(
      assetId:
          '7f3b2c41d5e6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3',
      ticker: 'TMPL',
      name: 'Templar test note',
      amount: 2500000000000,
      displayAmount: '25,000.00000000 TMPL',
      utxoCount: 2,
    );
    const token = AssetBalance(
      assetId: 'token',
      ticker: 'token',
      name: 'token',
      amount: 100000000,
      displayAmount: '1.00000000 RT',
      utxoCount: 1,
    );
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showAssetDetailDialog(
                    context,
                    asset: asset,
                    reissuanceToken: token,
                    issued: const IssuedAssetEntry(
                      assetId: 'x',
                      name: 'Templar test note',
                      ticker: 'TMPL',
                      tokenId: 'token',
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Templar test note'), findsOneWidget);
    expect(find.text('Asset ID'), findsOneWidget);
    // An issued asset with its token held offers both controls.
    expect(find.text('Reissue'), findsOneWidget);
    expect(find.text('Burn'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);

    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
  group('Issued assets', () {
    const assetId = 'asset';
    const tokenId = 'token';
    const held = AssetBalance(
      assetId: assetId,
      ticker: 'TMPL',
      name: 'Templar test note',
      amount: 2500000000000,
      displayAmount: '25,000.00000000 TMPL',
      utxoCount: 2,
    );
    const heldToken = AssetBalance(
      assetId: tokenId,
      ticker: 'RT',
      name: 'token',
      amount: 100000000,
      displayAmount: '1.00000000 RT',
      utxoCount: 1,
    );
    const entry = IssuedAssetEntry(
      assetId: assetId,
      name: 'Templar test note',
      ticker: 'TMPL',
      tokenId: tokenId,
      registered: true,
    );

    /// The card on a page of its own, with the three operation routes
    /// behind it so a tap has somewhere to land.
    Future<List<IssuedAssetEntry>> pump(
      WidgetTester t, {
      required List<IssuedAssetEntry> issued,
      required List<AssetBalance> holdings,
      String walletType = 'Software',
    }) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = const Size(1200, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final opened = <IssuedAssetEntry>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: SingleChildScrollView(
                child: IssuedAssetsCard(
                  issued: issued,
                  holdings: holdings,
                  onOpen: (e, _, _) => opened.add(e),
                ),
              ),
            ),
          ),
          for (final route in const [
            AppRoutes.issueAsset,
            AppRoutes.reissueAsset,
            AppRoutes.burnAsset,
          ])
            GoRoute(
              path: route,
              builder: (_, _) => Scaffold(body: Text('at $route')),
            ),
        ],
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        ChangeNotifierProvider<AppState>(
          create: (_) =>
              AppState()..setActiveWallet('w1', name: 'W', type: walletType),
          child: MaterialApp.router(
            theme: ThemeData(brightness: Brightness.dark),
            routerConfig: router,
          ),
        ),
      );
      await t.pumpAndSettle();
      return opened;
    }

    testWidgets('the three operations sit over the list, each a way in', (
      t,
    ) async {
      await pump(t, issued: const [entry], holdings: const [held, heldToken]);
      expect(find.text('Issue'), findsOneWidget);
      expect(find.text('Reissue'), findsOneWidget);
      expect(find.text('Burn'), findsOneWidget);
      // Above the first issued asset.
      expect(
        t.getTopLeft(find.text('Burn')).dy,
        lessThan(t.getTopLeft(find.text('Templar test note')).dy),
      );

      await t.tap(find.text('Reissue'));
      await t.pumpAndSettle();
      expect(find.text('at ${AppRoutes.reissueAsset}'), findsOneWidget);
    });

    testWidgets('an asset and its reissuance token are two lines, each with '
        'its own balance', (t) async {
      final opened = await pump(
        t,
        issued: const [entry],
        holdings: const [held, heldToken],
      );
      // The asset: its name and what is held of it.
      expect(find.text('Templar test note'), findsOneWidget);
      expect(find.text('25,000.00000000'), findsOneWidget);
      // Its token, under it: what holding it allows, and how much is held.
      expect(find.text('Reissuance token'), findsOneWidget);
      expect(
        find.text('Held here · lets this wallet mint more TMPL'),
        findsOneWidget,
      );
      expect(find.text('1.00000000'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Reissuance token')).dy,
        greaterThan(t.getTopLeft(find.text('Templar test note')).dy),
      );
      // Registered: nothing to say about the registry.
      expect(find.text('Register'), findsNothing);

      // The pair is one target: it opens the asset's detail.
      await t.tap(find.text('Reissuance token'));
      expect(opened.single.assetId, assetId);
    });

    testWidgets('the token line says why a reissue is not possible here', (
      t,
    ) async {
      // The token exists but another wallet holds it.
      await pump(t, issued: const [entry], holdings: const [held]);
      expect(
        find.text('Not in this wallet · reissue from the wallet that holds it'),
        findsOneWidget,
      );

      // Issued with no token at all: the supply is fixed.
      await pump(
        t,
        issued: const [
          IssuedAssetEntry(
            assetId: assetId,
            name: 'Templar test note',
            ticker: 'TMPL',
            registered: true,
          ),
        ],
        holdings: const [held],
      );
      expect(
        find.text('None was issued · the supply is fixed'),
        findsOneWidget,
      );
    });

    testWidgets('an asset not yet in the registry says so, with the way to '
        'register it', (t) async {
      await pump(
        t,
        issued: const [
          IssuedAssetEntry(
            assetId: assetId,
            name: 'Templar test note',
            ticker: 'TMPL',
            tokenId: tokenId,
            domain: 'templarwallet.dev',
          ),
        ],
        holdings: const [held, heldToken],
      );
      expect(find.text('Not in the asset registry yet'), findsOneWidget);
      expect(find.text('Register'), findsOneWidget);
    });

    testWidgets('a watch-only wallet is told why the three are off', (t) async {
      await pump(
        t,
        issued: const [],
        holdings: const [],
        walletType: 'Watch-only',
      );
      expect(find.textContaining('Watch-only'), findsOneWidget);
      expect(
        find.text('No assets issued from this wallet yet'),
        findsOneWidget,
      );
      // Off: a tap goes nowhere.
      await t.tap(find.text('Issue'));
      await t.pumpAndSettle();
      expect(find.text('at ${AppRoutes.issueAsset}'), findsNothing);
    });
  });
}
