// Wallet info is the public face of the wallet: descriptors and keys, each
// with a copy AND a QR way out.
//
// A singlesig wallet has to spell out BOTH keys it hands to a multisig
// coordinator — BIP48 for Bitcoin, BIP87 for Liquid — and must not offer its
// singlesig account key as a thing to copy beside them: pasting the wrong
// key builds a multisig nobody can spend, and the wizard cannot tell. So the
// Bitcoin card is the receive descriptor alone. A multisig (or a policy
// wallet) has no such keys to give, so the cosigner card is not there.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:templar_wallet/app/app_state.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/wallet_info/models/wallet_info.dart';
import 'package:templar_wallet/features/wallet_info/wallet_info_screen.dart';
import 'package:templar_wallet/shared/widgets/asset_logo.dart';
import 'package:templar_wallet/shared/widgets/code_box.dart';
import 'package:templar_wallet/shared/widgets/cosigner_ring.dart';

const _bip48 = "[cafebabe/48'/1'/0'/2']tpubDBip48Example";
const _bip87 = "[cafebabe/87'/1'/0']tpubDBip87Example";
const _accountXpub = 'tpubDSinglesigAccountKey';
const _receiveDescriptor = 'wpkh([cafebabe/84h/1h/0h]$_accountXpub/0/*)';

class _StubBridge implements WalletBridge {
  _StubBridge({
    this.liquid = true,
    this.failLiquid = false,
    this.multisig = false,
    this.software = true,
  });

  final bool liquid;
  final bool failLiquid;
  final bool multisig;

  /// False for a hardware, air-gap or watch-only wallet: no seed here.
  final bool software;

  int cosignerCalls = 0;

  @override
  Future<WalletInfo> getWalletInfo(String walletId) async => multisig
      ? WalletInfo(
          id: walletId,
          name: 'Vault 2-of-3',
          network: 'testnet',
          masterFingerprint: 'cafebabe',
          derivationPath: "m/48'/1'/0'/2'",
          scriptType: 'P2WSH 2-of-3 Multisig',
          xpub: '',
          receiveDescriptor: 'wsh(sortedmulti(2,a,b,c))',
          changeDescriptor: '',
          hasSeed: false,
          cosignerKeys: const [
            "[cafebabe/48'/1'/0'/2']tpubDKeyOne",
            "[deadbeef/48'/1'/0'/2']tpubDKeyTwo",
            "[0badf00d/48'/1'/0'/2']tpubDKeyThree",
          ],
          requiredSigs: 2,
        )
      : WalletInfo(
          id: walletId,
          name: 'Primary',
          network: 'testnet',
          masterFingerprint: 'cafebabe',
          derivationPath: "m/84'/1'/0'",
          scriptType: 'P2WPKH (Native SegWit)',
          xpub: software ? _accountXpub : '',
          receiveDescriptor: _receiveDescriptor,
          changeDescriptor: '',
          hasSeed: software,
          liquidDescriptor: liquid ? 'ct(slip77(aa),elwpkh(x))' : null,
        );

  @override
  Future<String> getCosignerXpub(String walletId) async {
    cosignerCalls++;
    return _bip48;
  }

  @override
  Future<String> getLiquidCosignerXpub(String walletId) async {
    cosignerCalls++;
    if (failLiquid) {
      throw Exception('wallet-ffi: no Liquid side on this wallet');
    }
    return _bip87;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [type] is the registry's type label ("Software", "Multisig",
/// "Hardware (…)", "Watch-only", "Policy (…)"); null leaves no wallet active.
Widget host(WalletBridge bridge, {String? type}) => MaterialApp(
  home: ChangeNotifierProvider<AppState>(
    create: (_) {
      final st = AppState();
      if (type != null) st.setActiveWallet('w1', name: 'W', type: type);
      return st;
    },
    child: WalletInfoScreen(bridge: bridge),
  ),
);

void _desktopWindow(WidgetTester t) {
  t.view.physicalSize = const Size(1400, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('singlesig wallet', () {
    testWidgets('both cosigner keys are shown, each named by its BIP', (
      t,
    ) async {
      _desktopWindow(t);
      await t.pumpWidget(host(_StubBridge(), type: 'Software'));
      await t.pumpAndSettle();

      expect(find.text('Use this wallet as a cosigner'), findsOneWidget);
      // A CodeBox label is drawn verbatim, in sentence case.
      expect(find.text('Cosigner xpub — Bitcoin (BIP48)'), findsOneWidget);
      expect(find.text('Cosigner Liquid key (BIP87)'), findsOneWidget);
      expect(find.textContaining(_bip48), findsWidgets);
      expect(find.textContaining(_bip87), findsWidgets);
    });

    testWidgets('the Liquid descriptor comes before the cosigner card, which '
        'wears the multisig mark', (t) async {
      _desktopWindow(t);
      await t.pumpWidget(host(_StubBridge(), type: 'Software'));
      await t.pumpAndSettle();

      final liquid = t.getTopLeft(find.text('Liquid descriptor')).dy;
      final bitcoin = t.getTopLeft(find.text('Bitcoin descriptor')).dy;
      final cosigner = t
          .getTopLeft(find.text('Use this wallet as a cosigner'))
          .dy;
      expect(bitcoin, lessThan(liquid));
      expect(liquid, lessThan(cosigner));
      // The key ring and the word: the card is about a multisig.
      expect(find.byType(KeyRingMark), findsOneWidget);
      expect(find.text('Multisig'), findsOneWidget);
    });

    testWidgets('each key names the wizard field it belongs in', (t) async {
      _desktopWindow(t);
      await t.pumpWidget(host(_StubBridge()));
      await t.pumpAndSettle();

      expect(find.textContaining('"Cosigner xpub" field'), findsOneWidget);
      expect(
        find.textContaining('"Cosigner Liquid key (BIP87)" field'),
        findsOneWidget,
      );
    });

    testWidgets('the Bitcoin card is the receive descriptor alone, under '
        "its chain's glyph", (t) async {
      _desktopWindow(t);
      await t.pumpWidget(host(_StubBridge()));
      await t.pumpAndSettle();

      // The singlesig account key is not a cosigner key and is not offered
      // as a thing to copy: only the descriptor is.
      expect(find.textContaining('Account key'), findsNothing);
      expect(find.text('Receive descriptor'), findsOneWidget);
      expect(find.text('Multipath descriptor'), findsNothing);
      // Each chain's card leads with that chain's logo.
      final logos = t.widgetList<AssetLogo>(find.byType(AssetLogo)).toList();
      expect(logos.map((l) => l.ticker), containsAll(['BTC', 'LIQUID']));
    });

    testWidgets('a missing Liquid key still leaves the Bitcoin one usable', (
      t,
    ) async {
      _desktopWindow(t);
      await t.pumpWidget(host(_StubBridge(liquid: false, failLiquid: true)));
      await t.pumpAndSettle();

      expect(find.textContaining(_bip48), findsWidgets);
      expect(find.text('Cosigner Liquid key (BIP87)'), findsNothing);
      expect(find.textContaining('Bitcoin-only multisig'), findsOneWidget);
    });

    testWidgets('the cosigner keys copy to the clipboard AND show as a QR', (
      t,
    ) async {
      _desktopWindow(t);
      await t.pumpWidget(host(_StubBridge()));
      await t.pumpAndSettle();

      final box = find.widgetWithText(
        CodeBox,
        'Cosigner xpub — Bitcoin (BIP48)',
      );
      expect(box, findsOneWidget);
      expect(
        find.descendant(of: box, matching: find.byIcon(Icons.copy_outlined)),
        findsOneWidget,
      );
      await t.tap(
        find.descendant(
          of: box,
          matching: find.byIcon(Icons.qr_code_2_outlined),
        ),
      );
      await t.pumpAndSettle();

      final qr = t.widget<QrImageView>(find.byType(QrImageView));
      expect((qr.key as ValueKey<String>).value, _bip48);
    });

    testWidgets('a hardware wallet says where its keys are, without asking', (
      t,
    ) async {
      _desktopWindow(t);
      final bridge = _StubBridge(software: false);
      await t.pumpWidget(host(bridge, type: 'Hardware (a1b2c3d4)'));
      await t.pumpAndSettle();

      expect(find.text('Use this wallet as a cosigner'), findsOneWidget);
      expect(find.textContaining('Read xpub from device'), findsOneWidget);
      expect(bridge.cosignerCalls, 0);
    });

    testWidgets('a watch-only wallet says it has no keys to give', (t) async {
      _desktopWindow(t);
      final bridge = _StubBridge(software: false);
      await t.pumpWidget(host(bridge, type: 'Watch-only'));
      await t.pumpAndSettle();

      expect(find.text('Use this wallet as a cosigner'), findsOneWidget);
      expect(find.textContaining('holds no keys'), findsOneWidget);
      expect(find.textContaining('keeps its keys on a device'), findsNothing);
      expect(bridge.cosignerCalls, 0);
    });
  });

  group('multisig and policy wallets', () {
    testWidgets('a multisig has no cosigner card and never fetches its keys', (
      t,
    ) async {
      _desktopWindow(t);
      final bridge = _StubBridge(multisig: true);
      await t.pumpWidget(host(bridge, type: 'Multisig'));
      await t.pumpAndSettle();

      expect(find.text('Use this wallet as a cosigner'), findsNothing);
      expect(find.textContaining('BIP48'), findsNothing);
      expect(find.textContaining('BIP87'), findsNothing);
      expect(bridge.cosignerCalls, 0);
      // The keys it is built from are still listed.
      expect(find.text('Cosigner keys in this wallet'), findsOneWidget);
    });

    testWidgets('a multisig is recognised from its keys alone', (t) async {
      _desktopWindow(t);
      final bridge = _StubBridge(multisig: true);
      await t.pumpWidget(host(bridge));
      await t.pumpAndSettle();

      expect(find.text('Use this wallet as a cosigner'), findsNothing);
      expect(bridge.cosignerCalls, 0);
    });

    testWidgets('a policy wallet has no cosigner card either', (t) async {
      _desktopWindow(t);
      final bridge = _StubBridge(software: false);
      await t.pumpWidget(host(bridge, type: 'Policy (Vault with recovery)'));
      await t.pumpAndSettle();

      expect(find.text('Use this wallet as a cosigner'), findsNothing);
      expect(bridge.cosignerCalls, 0);
    });
  });

  testWidgets('every copyable value has a QR button beside its copy button', (
    t,
  ) async {
    _desktopWindow(t);
    await t.pumpWidget(host(_StubBridge()));
    await t.pumpAndSettle();

    // Fingerprint + derivation path (the identity rows worth copying) +
    // receive descriptor + the two cosigner keys + CT descriptor each carry
    // a QR glyph, plus the Export card's "Show QR". Names and networks do
    // not.
    final qrGlyphs = find.byIcon(Icons.qr_code_2_outlined);
    expect(qrGlyphs, findsNWidgets(7));
  });

  testWidgets('the QR button opens a code carrying exactly that value', (
    t,
  ) async {
    _desktopWindow(t);
    await t.pumpWidget(host(_StubBridge()));
    await t.pumpAndSettle();

    // The receive descriptor's CodeBox is the Bitcoin card's only one.
    final box = find.widgetWithText(CodeBox, 'Receive descriptor');
    expect(box, findsOneWidget);
    await t.tap(
      find.descendant(of: box, matching: find.byIcon(Icons.qr_code_2_outlined)),
    );
    await t.pumpAndSettle();

    expect(find.byType(ValueQrDialog), findsOneWidget);
    final qr = t.widget<QrImageView>(find.byType(QrImageView));
    expect((qr.key as ValueKey<String>).value, _receiveDescriptor);
  });
}
