// The portfolio JSON of CONNECTOR.md §7, as the Loans screen reads
// it: every field of the contract's example, the nulls a loan may carry, and
// the words a newer site might send that this build does not know.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/features/protocol/models/protocol_portfolio.dart';

/// The §7 example, verbatim in shape.
const String _contract = '''
{
  "version": 1, "site": "Templar Protocol", "network": "liquid-regtest", "tip_height": 1234, "as_of": 1759480000,
  "wallet": { "label": "Templar — Alice", "escrow_fingerprint": "0bae4c8d" },
  "loans": [{
    "id": 1, "ref": "SQ-1", "role": "borrower", "state": "active",
    "principal":  { "asset": "2dcf5a88", "ticker": "rUSDt", "amount": "10000",  "sats": 1000000000000 },
    "collateral": { "asset": "5ac9f65c", "ticker": "rLBTC", "amount": "0.5",    "sats": 50000000 },
    "interest":   { "ticker": "rUSDt", "amount": "200", "sats": 20000000000, "rate_bps": 200 },
    "templar_fee": { "ticker": "rUSDt", "amount": "50", "sats": 5000000000, "payer": "borrower" },
    "opened_at": 1759470000, "start_height": 118, "term_height": 168, "blocks_left": 50,
    "due_at_estimate": 1759473000,
    "owed": { "ticker": "rUSDt", "amount": "10200", "sats": 1020000000000 },
    "next_action": { "kind": "repay", "label": "Repay 10,200 rUSDt before ≈ 50 min", "url": "https://host/loans/1" },
    "pending_request": { "id": "req_1", "action": "repayment", "link": "templar://sign?url=https%3A%2F%2Fhost%2Fwallet%2Frequests%2Freq_1&nonce=abc", "expires_at": 1759481000 },
    "txids": { "origination": "aa11", "repayment": null, "liquidation": null },
    "escrow_address": "el1qqescrow"
  }],
  "offers": [{ "id": 5, "side": "lend", "state": "open", "principal": { "ticker": "rUSDt", "amount": "5000", "sats": 500000000000 }, "collateral": { "ticker": "rLBTC", "amount": "0.25", "sats": 25000000 },
               "rate_bps": 250, "duration_blocks": 43200, "url": "https://host/offers/5" }]
}
''';

ProtocolPortfolio _parse(String json) =>
    ProtocolPortfolio.fromJson(jsonDecode(json) as Map<String, dynamic>);

void main() {
  group('the contract example', () {
    final p = _parse(_contract);

    test('top level and wallet', () {
      expect(p.version, 1);
      expect(p.site, 'Templar Protocol');
      expect(p.network, 'liquid-regtest');
      expect(p.tipHeight, 1234);
      expect(p.asOf, DateTime.utc(2025, 10, 3, 8, 26, 40));
      expect(p.wallet.label, 'Templar — Alice');
      expect(p.wallet.escrowFingerprint, '0bae4c8d');
    });

    test('every field of a loan', () {
      final l = p.loans.single;
      expect(l.id, 1);
      expect(l.ref, 'SQ-1');
      expect(l.role, 'borrower');
      expect(l.state, ProtocolLoanState.active);
      expect(l.stateLabel, 'active');

      expect(l.principal!.asset, '2dcf5a88');
      expect(l.principal!.ticker, 'rUSDt');
      expect(l.principal!.amount, '10000');
      expect(l.principal!.sats, 1000000000000);
      expect(l.principal!.display, '10,000 rUSDt');
      expect(l.collateral!.display, '0.5 rLBTC');
      expect(l.interest!.rateBps, 200);
      expect(l.interest!.sats, 20000000000);
      expect(l.templarFee!.payer, 'borrower');
      expect(l.templarFee!.display, '50 rUSDt');
      expect(l.owed!.display, '10,200 rUSDt');

      expect(l.openedAt, DateTime.utc(2025, 10, 3, 5, 40));
      expect(l.startHeight, 118);
      expect(l.termHeight, 168);
      expect(l.blocksLeft, 50);
      expect(l.dueAtEstimate, DateTime.utc(2025, 10, 3, 6, 30));

      expect(l.nextAction!.kind, ProtocolNextKind.repay);
      expect(l.nextAction!.label, 'Repay 10,200 rUSDt before ≈ 50 min');
      expect(l.nextAction!.url.toString(), 'https://host/loans/1');

      final r = l.pendingRequest!;
      expect(r.id, 'req_1');
      expect(r.action, 'repayment');
      expect(r.link.scheme, 'templar');
      expect(r.link.host, 'sign');
      expect(r.link.queryParameters['nonce'], 'abc');
      expect(r.expiresAt, DateTime.utc(2025, 10, 3, 8, 43, 20));
      expect(r.isExpired(now: DateTime.utc(2025, 10, 3, 8, 40)), isFalse);
      expect(r.isExpired(now: DateTime.utc(2025, 10, 3, 8, 44)), isTrue);

      expect(l.txids.origination, 'aa11');
      expect(l.txids.repayment, isNull);
      expect(l.txids.liquidation, isNull);
      expect(l.escrowAddress, 'el1qqescrow');
    });

    test('every field of an offer', () {
      final o = p.offers.single;
      expect(o.id, 5);
      expect(o.side, 'lend');
      expect(o.state, 'open');
      expect(o.principal!.display, '5,000 rUSDt');
      expect(o.collateral!.display, '0.25 rLBTC');
      expect(o.rateBps, 250);
      expect(o.durationBlocks, 43200);
      expect(o.url.toString(), 'https://host/offers/5');
    });

    test('the loan is open, counts as pending, and has a term bar', () {
      expect(p.openLoans.map((l) => l.id), [1]);
      expect(p.closedLoans, isEmpty);
      expect(p.pendingCount, 1);
      // (1234 − 118) / (168 − 118) is past the end: clamped to 1.
      expect(p.loans.single.termProgress(1234), 1.0);
      expect(p.loans.single.termProgress(143), 0.5);
      expect(p.loans.single.termProgress(100), 0.0);
    });
  });

  group('nulls and gaps', () {
    test('a loan with nothing but an id still renders', () {
      final p = _parse('{"loans":[{"id": 7}]}');
      final l = p.loans.single;
      expect(l.ref, 'SQ-7');
      expect(l.role, '');
      expect(l.state, ProtocolLoanState.unknown);
      expect(l.stateLabel, 'unknown');
      expect(l.principal, isNull);
      expect(l.owed, isNull);
      expect(l.nextAction, isNull);
      expect(l.pendingRequest, isNull);
      expect(l.blocksLeft, isNull);
      expect(l.dueAtEstimate, isNull);
      expect(l.termProgress(10), isNull);
      expect(l.txids.origination, isNull);
      expect(p.offers, isEmpty);
      expect(p.wallet.label, '');
      expect(p.site, '');
    });

    test('pending_request null, due_at_estimate null, txids nulls', () {
      final p = _parse(
        '''
        {"loans":[{"id": 2, "state": "repaid", "pending_request": null,
          "due_at_estimate": null, "blocks_left": 0,
          "txids": {"origination": "aa", "repayment": "bb", "liquidation": null},
          "next_action": {"kind": "none", "label": "Repaid", "url": null}}]}''',
      );
      final l = p.loans.single;
      expect(l.pendingRequest, isNull);
      expect(l.dueAtEstimate, isNull);
      expect(l.blocksLeft, 0);
      expect(l.state, ProtocolLoanState.repaid);
      expect(l.state.isOpen, isFalse);
      expect(l.nextAction!.kind, ProtocolNextKind.none);
      expect(l.nextAction!.url, isNull);
      expect(l.txids.repayment, 'bb');
      expect(p.openLoans, isEmpty);
      expect(p.closedLoans.single.id, 2);
      expect(p.pendingCount, 0);
    });

    test('a loan without an id is dropped, the rest kept', () {
      final p = _parse('{"loans":[{"ref":"SQ-x"},{"id":3}]}');
      expect(p.loans.map((l) => l.id), [3]);
    });

    test('a pending request whose link is not templar:// is ignored', () {
      final p = _parse(
        '{"loans":[{"id":1,"pending_request":{"id":"r","action":"x","link":"https://evil.example/"}}]}',
      );
      expect(p.loans.single.pendingRequest, isNull);
    });

    test('an answer with no loans list is not a portfolio', () {
      expect(() => _parse('{"version":1}'), throwsFormatException);
      expect(() => _parse('{"loans":"nope"}'), throwsFormatException);
    });

    test('numbers may arrive as strings or doubles', () {
      final p = _parse(
        '{"tip_height":"99","loans":[{"id":"4","start_height":1.0,"term_height":11}]}',
      );
      expect(p.tipHeight, 99);
      expect(p.loans.single.id, 4);
      expect(p.loans.single.termProgress(6), 0.5);
    });
  });

  group('words this build does not know', () {
    test('an unknown state is kept, shown as sent, and treated as open', () {
      final p = _parse('{"loans":[{"id":1,"state":"renegotiating"}]}');
      final l = p.loans.single;
      expect(l.state, ProtocolLoanState.unknown);
      expect(l.rawState, 'renegotiating');
      expect(l.stateLabel, 'renegotiating');
      expect(l.state.isOpen, isTrue);
      expect(p.openLoans.single.id, 1);
      expect(p.closedLoans, isEmpty);
    });

    test('an unknown next_action kind keeps its label and word', () {
      final p = _parse(
        '{"loans":[{"id":1,"next_action":{"kind":"renegotiate","label":"Agree new terms"}}]}',
      );
      final n = p.loans.single.nextAction!;
      expect(n.kind, ProtocolNextKind.unknown);
      expect(n.rawKind, 'renegotiate');
      expect(n.label, 'Agree new terms');
    });

    test('every known state and kind parses', () {
      for (final s in [
        'originating',
        'active',
        'repaid',
        'defaulted',
        'liquidated',
      ]) {
        expect(ProtocolLoanState.parse(s).name, s);
      }
      for (final k in ['sign', 'repay', 'claim', 'wait', 'none']) {
        expect(ProtocolNextKind.parse(k).name, k);
      }
    });
  });

  group('ordering', () {
    test('open loans: pending signature first, then the soonest due', () {
      final p = _parse('''
        {"loans":[
          {"id":1,"state":"active","blocks_left":10},
          {"id":2,"state":"active","blocks_left":500,
           "pending_request":{"id":"r","action":"repayment","link":"templar://sign?url=https://h/x&nonce=n"}},
          {"id":3,"state":"originating","blocks_left":5},
          {"id":4,"state":"repaid"}
        ]}''');
      expect(p.openLoans.map((l) => l.id), [2, 3, 1]);
      expect(p.closedLoans.map((l) => l.id), [4]);
    });
  });

  group('helpers', () {
    test('term progress', () {
      expect(protocolTermProgress(150, 100, 200), 0.5);
      expect(protocolTermProgress(50, 100, 200), 0.0);
      expect(protocolTermProgress(999, 100, 200), 1.0);
      expect(protocolTermProgress(150, null, 200), isNull);
      expect(protocolTermProgress(150, 100, null), isNull);
      expect(protocolTermProgress(150, 200, 200), isNull);
      expect(protocolTermProgress(150, 300, 200), isNull);
    });

    test('blocks left as time, one block being a minute', () {
      expect(protocolBlocksLeftLabel(null), '');
      expect(protocolBlocksLeftLabel(0), 'term reached');
      expect(protocolBlocksLeftLabel(1), '≈ 1 min left');
      expect(protocolBlocksLeftLabel(50), '≈ 50 min left');
      expect(protocolBlocksLeftLabel(60), '≈ 1 h left');
      expect(protocolBlocksLeftLabel(47 * 60), '≈ 47 h left');
      expect(protocolBlocksLeftLabel(48 * 60), '≈ 2 d left');
      expect(protocolBlocksLeftLabel(43200), '≈ 30 d left');
    });

    test('deadlines distinguish future from already reached', () {
      final now = DateTime.utc(2026, 11, 6, 12);
      expect(
        protocolDeadlineLabel(DateTime.utc(2026, 11, 6, 12, 45), now: now),
        'in 45 min',
      );
      expect(
        protocolDeadlineLabel(DateTime.utc(2026, 11, 6, 15), now: now),
        'in 3 h',
      );
      expect(
        protocolDeadlineLabel(DateTime.utc(2026, 11, 6, 10), now: now),
        'reached 2h ago',
      );
    });

    test('digit grouping leaves decimals and odd strings alone', () {
      expect(protocolGroupDigits('10000'), '10,000');
      expect(protocolGroupDigits('999'), '999');
      expect(protocolGroupDigits('1000'), '1,000');
      expect(protocolGroupDigits('1234567.89'), '1,234,567.89');
      expect(protocolGroupDigits('0.5'), '0.5');
      expect(protocolGroupDigits('-2500'), '-2,500');
      expect(protocolGroupDigits('10,000'), '10,000');
      expect(protocolGroupDigits(''), '');
    });

    test('basis points', () {
      expect(protocolBpsLabel(200), '2%');
      expect(protocolBpsLabel(250), '2.5%');
      expect(protocolBpsLabel(33), '0.33%');
      expect(protocolBpsLabel(5), '0.05%');
      expect(protocolBpsLabel(0), '0%');
    });

    test('action labels are human in English and Italian', () {
      expect(protocolActionLabel('origination'), 'Loan origination');
      expect(protocolActionLabel('payment_preparation'), 'Payment preparation');
      expect(protocolActionLabel('installment'), 'Installment payment');
      expect(protocolActionLabel('repayment'), 'Full repayment');
      expect(
        protocolActionLabel('payment_claim'),
        'Claim installment payments',
      );
      expect(protocolActionLabel('renewal'), 'Covenant renewal');
      expect(protocolActionLabel('default'), 'Default settlement');
      expect(
        protocolActionLabel('collateral_claim'),
        'Claim collateral remainder',
      );
      expect(protocolActionLabel('liquidation'), 'Collateral liquidation');
      expect(protocolActionLabel('proof'), 'Proof of key');
      expect(protocolActionLabel('swap'), 'Atomic swap');
      expect(protocolActionLabel(''), 'Signing request');
      expect(protocolActionLabel('custom_action'), 'Custom action');
      expect(
        protocolActionLabel('installment', languageCode: 'it'),
        'Pagamento della rata',
      );
      expect(
        protocolActionLabel('collateral_claim', languageCode: 'it'),
        'Ritiro del collaterale residuo',
      );
    });
  });

  group('extended repayment and covenant data', () {
    final p = _parse('''
      {"loans":[{
        "id":42,"ref":"SQ-42","role":"borrower","state":"active",
        "collateral":{"ticker":"LBTC","amount":"0.50000000","sats":50000000},
        "repayment_plan":{
          "kind":"installments","n_total":6,"n_paid":2,"m_missed":1,
          "m_max":3,"step":2,"s_max":6,"deadline_height":1600,
          "deadline_estimate":1793966400,
          "balance":{"ticker":"rUSDt","amount":"6500","sats":650000000000},
          "regular_due":{"ticker":"rUSDt","amount":"1100","sats":110000000000},
          "early_due":{"ticker":"rUSDt","amount":"6550","sats":655000000000},
          "penalty_due":{"ticker":"rUSDt","amount":"1200","sats":120000000000}
        },
        "covenant":{"status":"active","current_txid":"cc33","nodes":[
          {"index":0,"status":"replaced","txid":"aa11","spent_by":"installment","successor_txid":"bb22","balance":{"ticker":"rUSDt","amount":"8000"},"n":1,"m":0,"s":1},
          {"index":1,"status":"replaced","txid":"bb22","spent_by":"renewal","successor_txid":"cc33","balance":{"ticker":"rUSDt","amount":"6500"},"n":2,"m":0,"s":2},
          {"index":2,"status":"active","txid":"cc33","created_by":"renewal","balance":{"ticker":"rUSDt","amount":"6500"},"n":2,"m":1,"s":2}
        ]},
        "collateral_outcome":{"locked":{"ticker":"LBTC","amount":"0.50000000","sats":50000000},"forfeit":{"ticker":"LBTC","amount":"0.35"},"return":{"ticker":"LBTC","amount":"0.15"},"return_claimed":false},
        "next_action":{"kind":"renewal","label":"Review covenant renewal"}
      }]}
    ''');

    test('partial repayment lowers B and keeps all collateral locked', () {
      final l = p.loans.single;
      final plan = l.repaymentPlan!;
      expect(plan.balance!.display, '6,500 rUSDt');
      expect(plan.nPaid, 2);
      expect(plan.mMissed, 1);
      expect(plan.periodsBeforeDefault, 3);
      expect(l.collateral!.sats, 50000000);
      expect(l.collateralOutcome!.locked!.sats, 50000000);
      expect(l.actionRequired(), isTrue);
    });

    test('renewal replaces the covenant without changing B', () {
      final nodes = p.loans.single.covenant!.nodes;
      expect(nodes[1].spentBy, 'renewal');
      expect(nodes[1].balance!.amount, '6500');
      expect(nodes[2].createdBy, 'renewal');
      expect(nodes[2].balance!.amount, '6500');
      expect(nodes[2].m, 1);
      expect(p.loans.single.covenant!.current!.txid, 'cc33');
    });

    test('default allocations and unclaimed borrower remainder stay exact', () {
      final outcome = p.loans.single.collateralOutcome!;
      expect(outcome.forfeit!.display, '0.35 LBTC');
      expect(outcome.returnAmount!.display, '0.15 LBTC');
      expect(outcome.hasRemainderToClaim, isTrue);
    });

    test('terminal covenant has no successor', () {
      final terminal = ProtocolCovenantNode.fromJson({
        'index': 3,
        'status': 'defaulted',
        'txid': 'dd44',
      })!;
      expect(terminal.isTerminal, isTrue);
      expect(terminal.successorTxid, isNull);
    });

    test('portfolio v1 remains backward compatible', () {
      final loan = _parse(_contract).loans.single;
      expect(loan.repaymentPlan, isNull);
      expect(loan.covenant, isNull);
      expect(loan.collateralOutcome, isNull);
    });
  });
}
