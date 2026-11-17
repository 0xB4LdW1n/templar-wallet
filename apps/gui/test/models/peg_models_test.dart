// Peg models against the engine's real answers (captured from templarlib
// feat/native-peg with a throwaway wallet joined to a Templar testlab), the
// pre-native shape of a simulated order, and the peg error tags.

import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/bridge/wallet_bridge.dart';
import 'package:templar_wallet/features/peg/models/peg_models.dart';

// peg_start, native peg-in.
const Map<String, dynamic> _nativePegIn = {
  'confirmations': 0,
  'confirmations_required': 2,
  'created_at': 1794877403,
  'deposit_address': '2MwZFDfh4yR5ahSbq2mqgzhv77kPxPQELUY',
  'deposit_expected_sats': 100000,
  'deposit_received_sats': null,
  'direction': 'in',
  'eta_minutes': 21,
  'expires_at': null,
  'last_error': null,
  'order_id': 'pg_9a314474',
  'payout_address':
      'el1qqtcmkssvvujtewm895nz963ht02fhzjvtf8v25gc5lad5kjr6levtrxmw6q70xhwj9j65hm5v432svzsdk7mq3va922gxrx7v',
  'payout_expected_sats': 99965,
  'provider': 'native',
  'simulated': false,
  'status': 'awaiting_deposit',
  'status_history': [
    {'at': 1794877403, 'status': 'awaiting_deposit'},
  ],
  'txid_claim': null,
  'txid_deposit': null,
  'txid_payout': null,
  'updated_at': 1794877403,
  'valid_until_liquid_height': 189,
  'wallet_id': 'bc8aa95d',
};

// peg_start, native peg-out: nothing to pay by hand.
const Map<String, dynamic> _nativePegOut = {
  'confirmations': 0,
  'confirmations_required': 2,
  'created_at': 1794877405,
  'deposit_address': '',
  'deposit_expected_sats': 50000,
  'deposit_received_sats': null,
  'direction': 'out',
  'eta_minutes': 12,
  'expires_at': null,
  'last_error': null,
  'order_id': 'pg_d5525fbf',
  'payout_address': 'bcrt1q3ndhdq08nthfzed2ta6x2c4gxpgxm0dstk2dfc',
  'payout_expected_sats': 50000,
  'provider': 'native',
  'simulated': false,
  'status': 'awaiting_deposit',
  'status_history': [
    {'at': 1794877405, 'status': 'awaiting_deposit'},
  ],
  'txid_claim': null,
  'txid_deposit': null,
  'txid_payout': null,
  'updated_at': 1794877405,
  'valid_until_liquid_height': null,
  'wallet_id': 'bc8aa95d',
};

void main() {
  test('a native peg-in from peg_start', () {
    final o = PegOrder.fromJson(_nativePegIn);
    expect(o.orderId, 'pg_9a314474');
    expect(o.provider, 'native');
    expect(o.simulated, isFalse);
    expect(o.isLegacySimulated, isFalse);
    expect(o.isPegIn, isTrue);
    expect(o.depositAddress, '2MwZFDfh4yR5ahSbq2mqgzhv77kPxPQELUY');
    expect(o.payoutExpectedSats, 99965);
    expect(o.confirmations, 0);
    expect(o.confirmationsRequired, 2);
    expect(o.validUntilLiquidHeight, 189);
    expect(o.depositReceivedSats, isNull);
    expect(o.txidClaim, isNull);
    expect(o.lastError, isNull);
    expect(o.expiresAt, isNull);
    expect(o.canOfferFund, isTrue);
    expect(o.canOfferClaim, isFalse);
    expect(o.showsDepositAddress, isTrue);
    expect(o.isTerminal, isFalse);
  });

  test('a native peg-out has no deposit address to show', () {
    final o = PegOrder.fromJson(_nativePegOut);
    expect(o.isPegIn, isFalse);
    expect(o.depositAddress, isEmpty);
    expect(o.showsDepositAddress, isFalse);
    expect(o.canOfferFund, isTrue);
    expect(o.validUntilLiquidHeight, isNull);
  });

  test('claimable, final and SideSwap states', () {
    final claimable = PegOrder.fromJson({
      ..._nativePegIn,
      'status': 'claimable',
      'confirmations': 2,
      'deposit_received_sats': 100000,
      'txid_deposit': 'aa' * 32,
    });
    expect(claimable.canOfferClaim, isTrue);
    expect(claimable.canOfferFund, isFalse);
    for (final s in ['completed', 'cancelled', 'expired', 'failed']) {
      expect(
        PegOrder.fromJson({..._nativePegIn, 'status': s}).isTerminal,
        isTrue,
      );
    }
    final swap = PegOrder.fromJson({
      ..._nativePegIn,
      'provider': 'sideswap',
      'status': 'claimable',
      'expires_at': 1794880000,
    });
    expect(swap.isSideSwap, isTrue);
    expect(swap.canOfferClaim, isFalse);
    expect(swap.expiresAt, 1794880000);
  });

  test('an order stored before the native peg is a simulated one', () {
    final o = PegOrder.fromJson({
      'order_id': 'pg_0000abcd',
      'wallet_id': 'w',
      'direction': 'in',
      'status': 'completed',
      'deposit_address': 'tb1qsimulatedpegdeposit0demo0nly00000000000',
      'deposit_expected_sats': 50000,
      'payout_address': 'tlq1q…',
      'payout_expected_sats': 49650,
      'created_at': 1790000000,
      'updated_at': 1790000110,
      'eta_minutes': 2,
      'simulated': true,
      'status_history': [
        {'status': 'awaiting_deposit', 'at': 1790000000},
      ],
    });
    expect(o.provider, 'simulated');
    expect(o.isLegacySimulated, isTrue);
    expect(o.canOfferFund, isFalse);
    expect(o.showsDepositAddress, isFalse);
  });

  test('peg_quote, both directions (real answers)', () {
    final pegIn = PegQuote.fromJson({
      'amount_sats': 1000000,
      'confirmations_required': 2,
      'direction': 'in',
      'eta_minutes': 21,
      'max_sats': 2100000000000000,
      'min_sats': 10000,
      'network_fee_included': true,
      'network_fee_sats': 35,
      'provider': 'native',
      'rate': 1.0,
      'receive_sats': 999965,
      'service_fee_sats': 0,
      'simulated': false,
    });
    expect(pegIn.provider, 'native');
    expect(pegIn.networkFeeIncluded, isTrue);
    expect(pegIn.confirmationsRequired, 2);
    expect(pegIn.receiveSats, 999965);
    expect(pegIn.maxSats, 2100000000000000);

    final pegOut = PegQuote.fromJson({
      'amount_sats': 500000,
      'confirmations_required': 2,
      'direction': 'out',
      'eta_minutes': 12,
      'max_sats': 100000000,
      'min_sats': 10000,
      'network_fee_included': false,
      'network_fee_sats': 35,
      'provider': 'native',
      'rate': 1.0,
      'receive_sats': 500000,
      'service_fee_sats': 0,
      'simulated': false,
    });
    expect(pegOut.networkFeeIncluded, isFalse);
    expect(pegOut.receiveSats, pegOut.amountSats);
  });

  test('get_liquid_network: the peg provider and why there is none', () {
    final native = LiquidNetworkInfo.fromJson({
      'backend': 'electrum',
      'backend_description': 'electrum tcp://127.0.0.1:19061',
      'backend_source': 'profile',
      'env_locked': false,
      'network': 'liquid-regtest',
      'peg_provider': 'native',
      'peg_unavailable_reason': null,
      'policy_asset': 'b0' * 32,
      'regtest_default_policy_asset': '5a' * 32,
      'short_name': 'regtest',
      'test_server': 'http://127.0.0.1:8096',
    });
    expect(native.pegProvider, 'native');
    expect(native.pegUnavailableReason, isNull);

    final none = LiquidNetworkInfo.fromJson({
      'network': 'liquid-testnet',
      'short_name': 'testnet',
      'peg_provider': null,
      'peg_unavailable_reason':
          'PEG_UNAVAILABLE: Liquid testnet has no parent chain, so it has no '
          'native peg-in / peg-out (a test server whose config names SideSwap '
          'for testnet enables its swap service).',
    });
    expect(none.pegProvider, isNull);
    expect(none.pegUnavailableReason, startsWith('PEG_UNAVAILABLE:'));
  });

  test('peg errors by tag (real engine texts)', () {
    String text(String e) => pegErrorText(Exception('wallet-ffi: $e'));
    expect(
      text('PEG_NOT_READY: no deposit has arrived yet.'),
      'Not yet: no deposit has arrived yet.',
    );
    expect(
      text(
        'PEG_NOT_READY: the deposit has 1 of the 2 Bitcoin confirmations a '
        'claim needs.',
      ),
      contains('1 of the 2'),
    );
    expect(
      text('PEG_EXPIRED: the federation changed.'),
      startsWith('This deposit address has expired: never pay it.'),
    );
    expect(
      text('PEG_PROOF_REJECTED: block hash mismatch'),
      contains('nothing was signed'),
    );
    expect(
      text('PEG_UNAVAILABLE: Liquid testnet has no parent chain'),
      startsWith('No peg here.'),
    );
    expect(
      text(
        'Transaction build failed: Insufficient funds: 0 sat available of '
        '100043 sat needed',
      ),
      startsWith('Transaction build failed'),
    );
    expect(
      text('Vault is locked — unlock with your passphrase first'),
      startsWith('Vault is locked'),
    );
  });
}
