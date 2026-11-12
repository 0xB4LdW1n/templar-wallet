import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/features/swap/models/swap_offer.dart';

void main() {
  final assetA = List.filled(64, 'a').join();
  final assetB = List.filled(64, 'b').join();

  test('normalizes legacy Liquid Bitcoin tickers to LBTC', () {
    for (final ticker in ['L-BTC', 'tL-BTC', 'rL-BTC', 'LBTC']) {
      final leg = SwapLeg.fromJson({
        'asset_id': assetA,
        'ticker': ticker,
        'amount_sats': 100000000,
        'display_amount': '1.00000000',
      });
      expect(leg.ticker, 'LBTC');
    }
  });

  test('formats local order-book Unix timestamps for display', () {
    final offer = SwapOffer.fromJson({
      'id': 7,
      'available': true,
      'receive': {
        'asset_id': assetA,
        'ticker': 'LBTC',
        'amount_sats': 1,
        'display_amount': '0.00000001',
      },
      'pay': {
        'asset_id': assetB,
        'ticker': 'USDt',
        'amount_sats': 2,
        'display_amount': '0.00000002',
      },
      'created': '0',
    });

    expect(offer.created, '1970-01-01 00:00 UTC');
  });

  test('cross-chain demo market stays visible but cannot be taken', () {
    final offer = MarketOffer.fromJson({
      'id': 'demo:9',
      'source_id': 9,
      'status': 'open',
      'settlement': 'htlc-demo',
      'demo': true,
      'available': true,
      'maker_gives': {
        'chain': 'bitcoin',
        'network': 'bitcoin-testnet',
        'asset_id': 'btc',
        'ticker': 'BTC',
        'name': 'Bitcoin',
        'precision': 8,
        'amount_sats': 100000,
        'display_amount': '0.00100000',
      },
      'maker_wants': {
        'chain': 'liquid',
        'network': 'liquid-testnet',
        'asset_id': assetA,
        'ticker': 'tL-BTC',
        'name': 'Liquid Bitcoin',
        'precision': 8,
        'amount_sats': 99000,
        'display_amount': '0.00099000',
      },
      'price_display': '0.99 LBTC/BTC',
      'note': 'demo',
      'created_at': 1,
      'proposal_json': '',
      'verified': false,
      'takeable': false,
      'block_reason': 'HTLC settlement disabled',
    });

    expect(offer.isCrossChain, isTrue);
    expect(offer.involvesBitcoin, isTrue);
    expect(offer.isLiquidex, isFalse);
    expect(offer.makerWants.ticker, 'LBTC');
    expect(offer.takeable, isFalse);
    expect(offer.blockReason, contains('disabled'));
  });

  test('real Liquid market preserves LiquiDEX capability', () {
    final offer = MarketOffer.fromJson({
      'id': 'liquid:3',
      'source_id': 3,
      'status': 'open',
      'settlement': 'liquidex-v0',
      'demo': false,
      'available': true,
      'maker_gives': {
        'chain': 'liquid',
        'network': 'liquid-testnet',
        'asset_id': assetA,
        'ticker': 'USDt',
        'name': 'Test USD',
        'precision': 8,
        'amount_sats': 100000000,
        'display_amount': '1.00',
      },
      'maker_wants': {
        'chain': 'liquid',
        'network': 'liquid-testnet',
        'asset_id': assetB,
        'ticker': 'LBTC',
        'name': 'Liquid Bitcoin',
        'precision': 8,
        'amount_sats': 1000,
        'display_amount': '0.00001000',
      },
      'price_display': '0.00001 LBTC/USDt',
      'note': '',
      'created_at': 1,
      'proposal_json': '{}',
      'verified': true,
      'takeable': true,
      'block_reason': null,
    });

    expect(offer.isCrossChain, isFalse);
    expect(offer.isLiquidex, isTrue);
    expect(offer.takeable, isTrue);
    expect(offer.demo, isFalse);
  });

  test('real HTLC row and owned action decode without demo semantics', () {
    final market = MarketOffer.fromJson({
      'id': 'atomic:12', 'source_id': 12, 'status': 'open',
      'settlement': 'htlc-v1', 'demo': false, 'available': true,
      'maker_gives': {'chain': 'bitcoin', 'network': 'bitcoin-testnet', 'asset_id': 'btc-testnet', 'ticker': 'BTC', 'name': 'Bitcoin', 'precision': 8, 'amount_sats': 100000, 'display_amount': '0.00100000'},
      'maker_wants': {'chain': 'liquid', 'network': 'liquid-testnet', 'asset_id': assetA, 'ticker': 'LBTC', 'name': 'Liquid Bitcoin', 'precision': 8, 'amount_sats': 90000, 'display_amount': '0.00090000'},
      'price_display': '0.001 → 0.0009', 'note': '', 'created_at': 1,
      'proposal_json': '{}', 'verified': true, 'takeable': true,
    });
    expect(market.isAtomic, isTrue);
    expect(market.demo, isFalse);
    expect(market.takeable, isTrue);

    final owned = AtomicSwap.fromJson({
      'offer_id': 12, 'role': 'maker', 'next_action': 'fund',
      'can_fund': true, 'can_claim': false, 'can_refund': false,
      'row': {
        'status': 'reserved',
        'state': {
          'offered_chain': 'bitcoin', 'offered_asset_id': 'btc-testnet',
          'offered_ticker': 'BTC', 'offered_name': 'Bitcoin',
          'offered_precision': 8, 'offered_amount_sats': 100000,
          'wanted_chain': 'liquid', 'wanted_asset_id': assetA,
          'wanted_ticker': 'LBTC', 'wanted_name': 'Liquid Bitcoin',
          'wanted_precision': 8, 'wanted_amount_sats': 90000,
          'maker_timeout': 2000000000, 'taker_timeout': 1999990000,
        },
      },
    });
    expect(owned.canFund, isTrue);
    expect(owned.offered.displayAmount, '0.00100000');
    expect(owned.wanted.ticker, 'LBTC');
  });
}
