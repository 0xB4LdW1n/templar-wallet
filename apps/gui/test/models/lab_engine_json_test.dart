// Decoding of the lab engine's answers against REAL engine JSON.
//
// The fixtures in test/fixtures/lab/ were captured from templarlib (branch
// feat/lab-mode) on a throwaway data directory joined to a test lab
// (Liquid regtest + Bitcoin regtest): the faucet, registry-named assets, a
// regtest issuance, an unfunded peg and the swap legs. Long proposal
// strings were cut to "{}"; nothing else was edited. The testnet
// `atomic_swap_list` row at the end is written from templarlib docs/API.md
// (a lab cannot produce one: off testnet the list is `[]`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/bridge/ffi_wallet_bridge.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/liquid/models/issue_result.dart';
import 'package:templar_wallet/features/peg/models/peg_models.dart';
import 'package:templar_wallet/features/swap/models/swap_offer.dart';
import 'package:templar_wallet/features/test_coins/faucet_error.dart';
import 'package:templar_wallet/features/wallet_picker/models/wallet_summary.dart';

/// The `{"ok": …}` or `{"err": …}` envelope of a fixture.
Map<String, dynamic> _envelope(String name) =>
    jsonDecode(File('test/fixtures/lab/$name.json').readAsStringSync())
        as Map<String, dynamic>;

dynamic _ok(String name) => _envelope(name)['ok'];
String _err(String name) => _envelope(name)['err'] as String;

void main() {
  group('get_test_server on a joined lab', () {
    final info = TestServerInfo.fromJson(
      _ok('get_test_server') as Map<String, dynamic>,
    );

    test('decodes the faucet and what it pays', () {
      expect(info.faucetAvailable, isTrue);
      final faucet = info.faucet!;
      expect(faucet.assetsSource, 'profile');
      expect(faucet.url, endsWith('/api/faucet'));
      expect(faucet.assets.map((a) => a.asset), ['btc', 'lbtc', 'USDt']);
      final btc = faucet.assets[0];
      expect(btc.isBitcoin, isTrue);
      expect(btc.isNativeCoin, isTrue);
      expect(btc.assetId, isNull);
      expect(btc.defaultSat, 1000000);
      final usdt = faucet.assets[2];
      expect(usdt.isLiquid, isTrue);
      expect(usdt.isNativeCoin, isFalse);
      expect(usdt.ticker, 'USDt');
      expect(usdt.precision, 8);
      expect(usdt.assetId, hasLength(64));
    });

    test('decodes the lending site and the book registry', () {
      expect(info.protocolUrl, startsWith('http://127.0.0.1:'));
      expect(info.active.protocol!.source, 'profile');
      expect(info.profile!.protocolUrl, info.protocolUrl);
      expect(info.active.orderbook.assets!.url, endsWith('/api/assets'));
      expect(info.profile!.regtest.faucet, hasLength(3));
      expect(info.profile!.regtest.peg.pegoutMinSat, 100000);
    });

    test('an older engine without the new keys still decodes', () {
      final old = TestServerInfo.fromJson({'configured': false});
      expect(old.faucet, isNull);
      expect(old.faucetAvailable, isFalse);
      expect(old.protocolUrl, isNull);
      expect(old.active.orderbook.assets, isNull);
    });
  });

  group('test_server_faucet', () {
    test('decodes a BTC payment', () {
      final p = FaucetPayment.fromJson(
        _ok('test_server_faucet_btc') as Map<String, dynamic>,
      );
      expect(p.isBitcoin, isTrue);
      expect(p.amountSat, 1000000);
      expect(p.address, startsWith('bcrt1'));
      expect(p.txid, hasLength(64));
      expect(p.assetId, isNull);
    });

    test('decodes a lab token payment', () {
      final p = FaucetPayment.fromJson(
        _ok('test_server_faucet_usdt') as Map<String, dynamic>,
      );
      expect(p.isBitcoin, isFalse);
      expect(p.ticker, 'USDt');
      expect(p.amountSat, 10000000000);
      expect(p.address, startsWith('el1'));
    });

    test('maps the real FAUCET_UNAVAILABLE refusal', () {
      final e = FaucetError.from(
        Exception('wallet-ffi: ${_err('test_server_faucet_unknown')}'),
      );
      expect(e.kind, FaucetErrorKind.unavailable);
      expect(e.message, startsWith('The faucet cannot pay this here: '));
      expect(e.message, contains('it pays BTC, LBTC, USDt'));
      expect(e.message, isNot(endsWith('.')));
    });
  });

  group('asset names', () {
    test('the wallet summary carries precision and who named each asset', () {
      final d = FfiWalletBridge.decodeWalletSummary(
        _ok('get_wallet_summary') as Map<String, dynamic>,
      );
      expect(d.isLiquidRegtest, isTrue);
      expect(d.isBitcoinRegtest, isTrue);
      final btc = d.assets.firstWhere((a) => a.assetId == 'BTC');
      expect(btc.metadataSource, 'wallet');
      expect(btc.precision, 8);
      final usdt = d.assets.firstWhere((a) => a.ticker == 'USDT');
      expect(usdt.metadataSource, 'book');
      expect(usdt.bookSource, 'admin');
      expect(usdt.name, 'Tether USD (test)');
    });

    test('a market leg named by the book shows its short id beside it', () {
      final rows = _ok('list_markets') as List<dynamic>;
      final m = MarketOffer.fromJson(rows.first as Map<String, dynamic>);
      expect(m.makerGives.metadataSource, 'book');
      expect(m.makerGives.precision, 2);
      expect(m.makerGives.displayAmount, '100.00');
      expect(m.makerGives.showsIdBeside, isTrue);
      expect(m.makerGives.shortId, hasLength(8));
      expect(m.makerWants.metadataSource, 'wallet');
      expect(m.makerWants.showsIdBeside, isFalse);
    });

    test('swap_verify legs carry name, precision and source', () {
      final a = SwapAnalysis.fromJson(
        _ok('swap_verify_book_named') as Map<String, dynamic>,
      );
      expect(a.network, 'regtest');
      expect(a.makerOffers.name, 'Registry Token');
      expect(a.makerOffers.precision, 2);
      expect(a.makerOffers.bookSource, 'contract');
      expect(a.makerOffers.showsIdBeside, isTrue);
      expect(a.makerWants.ticker, 'LBTC');
      expect(a.makerWants.showsIdBeside, isFalse);
    });

    test('my offers name their legs now', () {
      final o = MyOffer.fromJson(
        (_ok('list_my_offers') as List<dynamic>).first as Map<String, dynamic>,
      );
      expect(o.offers.name, 'Tether USD (test)');
      expect(o.offers.metadataSource, 'book');
      expect(o.wants.precision, 8);
    });
  });

  group('issuance on a lab', () {
    test(
      'issue_asset reports the book registration and the default domain',
      () {
        final r = IssueResult.fromJson(
          _ok('issue_asset_regtest') as Map<String, dynamic>,
        );
        expect(r.bookRegistered, isTrue);
        expect(r.bookError, isNull);
        expect(r.registryRegistered, isFalse);
        expect(r.proofUrl, isEmpty);
        expect(r.domain, 'regtest.templar.test');
        expect(r.tokenId, isNotNull);
      },
    );

    test('reregister_asset carries the book refusal in words', () {
      final r = ReregisterResult.fromJson(
        _ok('reregister_asset_not_issued') as Map<String, dynamic>,
      );
      expect(r.registered, isFalse);
      expect(r.bookRegistered, isFalse);
      expect(r.bookError, contains('not in this wallet\'s history'));
    });
  });

  group('pegs on a lab', () {
    test('an unfunded peg-in is PEG_INSUFFICIENT_FUNDS, in plain words', () {
      final raw = Exception('wallet-ffi: ${_err('peg_fund_insufficient')}');
      expect(isPegInsufficientFunds(raw), isTrue);
      final text = pegErrorText(raw);
      expect(
        text,
        startsWith('Not enough coins: This wallet has 0 sat of BTC'),
      );
      expect(text, contains('Bitcoin regtest'));
      expect(text, endsWith('Nothing was signed.'));
    });

    test('a peg-in order decodes', () {
      final o = PegOrder.fromJson(_ok('peg_start_in') as Map<String, dynamic>);
      expect(o.provider, 'native');
      expect(o.isLegacySimulated, isFalse);
      expect(o.depositAddress, isNotEmpty);
    });
  });

  group('wallets on a lab', () {
    test('a wallet summary says regtest', () {
      final w = WalletSummary.fromJson(
        _ok('create_wallet_regtest') as Map<String, dynamic>,
      );
      expect(w.network, WalletNetwork.regtest);
    });
  });

  group('atomic_swap_list', () {
    test('is empty on a lab', () {
      expect(_ok('atomic_swap_list_regtest'), isEmpty);
    });

    test('a testnet row that is not live carries its availability', () {
      final s = AtomicSwap.fromJson({
        'offer_id': 1,
        'wallet_id': 'w',
        'role': 'maker',
        'key_index': 3,
        'row': {
          'id': 1,
          'network': 'testnet',
          'status': 'unavailable',
          'state': <String, dynamic>{},
          'created_at': 0,
          'updated_at': 0,
        },
        'next_action': 'wait',
        'can_fund': false,
        'can_claim': false,
        'can_refund': false,
        'availability': 'not_on_this_book',
        'availability_note': 'The order book does not know swap 1.',
        'coordinator': 'http://127.0.0.1:3210/api/atomic-swaps',
      });
      expect(s.isLive, isFalse);
      expect(s.availability, 'not_on_this_book');
      expect(s.availabilityNote, contains('swap 1'));
      expect(s.coordinator, contains('atomic-swaps'));
    });

    test('a row from an older engine is live', () {
      final s = AtomicSwap.fromJson({'offer_id': 2, 'row': <String, dynamic>{}});
      expect(s.isLive, isTrue);
    });
  });
}
