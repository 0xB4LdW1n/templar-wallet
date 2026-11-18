import 'package:flutter_test/flutter_test.dart';
import 'package:templar_wallet/features/protocol/models/protocol_link.dart';
import 'package:templar_wallet/features/protocol/models/protocol_review_agreement.dart';
import 'package:templar_wallet/features/psbt/models/pset_inspection.dart';

ProtocolRequest _request(List<ProtocolSummaryLine> lines) => ProtocolRequest(
  version: 1,
  kind: 'sign',
  site: 'Templar Protocol',
  network: 'liquid-regtest',
  nonce: 'n',
  callback: Uri.parse('http://127.0.0.1/signed'),
  expiresAt: 2000000000,
  id: 'req-1',
  action: 'installment',
  loanRef: 'SQ-42',
  summary: ProtocolSummary(role: 'borrower', lines: lines),
  pset: 'cHNldP8B',
);

PsetInspection _inspection({
  bool unverified = false,
  String received = '+1,100.00 rUSDt',
}) => PsetInspection(
  feeSats: 24,
  feeDisplay: '0.00000024 LBTC',
  recipients: const [],
  sigsHave: 0,
  sigsNeeded: 1,
  signersPresent: const [],
  signersMissing: const [],
  canFinalize: false,
  rawPset: 'cHNldP8B',
  netChangeLines: [
    PsetNetChange(
      assetId: 'principal',
      ticker: 'rUSDt',
      amountSats: 11000000000,
      displayAmount: received,
    ),
    const PsetNetChange(
      assetId: 'lbtc',
      ticker: 'LBTC',
      amountSats: -24,
      displayAmount: '-0.00000024 LBTC',
    ),
  ],
  outputs: const [
    PsetOutput(
      index: 0,
      kind: 'escrow',
      scriptType: 'p2wsh',
      ticker: 'LBTC',
      amountSats: 50000000,
      displayAmount: '0.50000000 LBTC',
    ),
  ],
  hasUnverifiedOutputs: unverified,
);

void main() {
  test('matching human summary permits the signing gate', () {
    final result = ProtocolReviewAgreement.compare(
      _request(const [
        ProtocolSummaryLine(label: 'You receive', amount: '1100 rUSDt'),
        ProtocolSummaryLine(
          label: 'Collateral remains locked',
          amount: '0.5 LBTC',
        ),
        ProtocolSummaryLine(label: 'Network fee', amount: '0.00000024 LBTC'),
      ]),
      _inspection(),
    );

    expect(result.checked, 3);
    expect(result.mismatches, isEmpty);
    expect(result.canSign, isTrue);
  });

  test('an amount mismatch blocks signing and names the site line', () {
    final result = ProtocolReviewAgreement.compare(
      _request(const [
        ProtocolSummaryLine(label: 'You receive', amount: '1200 rUSDt'),
      ]),
      _inspection(),
    );

    expect(result.canSign, isFalse);
    expect(result.mismatches.single, contains('site says 1200 rUSDt'));
  });

  test('unverified PSET output blocks signing even if copy matches', () {
    final result = ProtocolReviewAgreement.compare(
      _request(const [
        ProtocolSummaryLine(label: 'You receive', amount: '1100 rUSDt'),
      ]),
      _inspection(unverified: true),
    );

    expect(result.hasUnverifiedOutputs, isTrue);
    expect(result.canSign, isFalse);
  });

  test('unknown prose is not guessed into an amount comparison', () {
    final result = ProtocolReviewAgreement.compare(
      _request(const [
        ProtocolSummaryLine(label: 'Future installment', amount: '1100 rUSDt'),
      ]),
      _inspection(),
    );

    expect(result.checked, 0);
    expect(result.couldCompare, isFalse);
    expect(result.canSign, isTrue);
  });

  group('lines that name asset id and base units', () {
    // The lab case: the engine knows no ticker for the lab's USDt, so it
    // prints a bare figure; the site calls L-BTC rLBTC. The loan's 1-sat
    // control token arrives too.
    const usdt = 'AA11';
    const lbtc = 'bb22';
    PsetInspection lab({int principal = 1200000000000}) => PsetInspection(
      feeSats: 30,
      feeDisplay: '0.00000030 LBTC',
      recipients: const [],
      sigsHave: 0,
      sigsNeeded: 1,
      signersPresent: const [],
      signersMissing: const [],
      canFinalize: false,
      rawPset: 'cHNldP8B',
      netChangeLines: [
        PsetNetChange(
          assetId: 'aa11',
          ticker: '',
          amountSats: principal,
          displayAmount: '+12000.00000000',
        ),
        const PsetNetChange(
          assetId: 'cc33',
          ticker: '',
          amountSats: 1,
          displayAmount: '+0.00000001',
        ),
        const PsetNetChange(
          assetId: lbtc,
          ticker: 'LBTC',
          amountSats: -28125030,
          displayAmount: '-0.28125030 LBTC',
        ),
      ],
      outputs: const [
        PsetOutput(
          index: 0,
          kind: 'escrow',
          scriptType: 'p2wsh',
          assetId: lbtc,
          ticker: 'LBTC',
          amountSats: 28125000,
          displayAmount: '0.28125000 LBTC',
        ),
      ],
      hasUnverifiedOutputs: false,
    );
    const lines = [
      ProtocolSummaryLine(
        label: 'You receive',
        amount: '12,000 USDt',
        assetId: usdt,
        sats: 1200000000000,
      ),
      ProtocolSummaryLine(
        label: 'Collateral locked in the covenant',
        amount: '0.28125 rLBTC',
        assetId: lbtc,
        sats: 28125000,
      ),
    ];

    test('agree although the tickers differ', () {
      final result = ProtocolReviewAgreement.compare(_request(lines), lab());
      expect(result.checked, 2);
      expect(result.mismatches, isEmpty);
      expect(result.canSign, isTrue);
    });

    test('a different amount still blocks', () {
      final result = ProtocolReviewAgreement.compare(
        _request(lines),
        lab(principal: 1100000000000),
      );
      expect(result.canSign, isFalse);
      expect(result.mismatches.single, contains('You receive'));
    });

    test('the same amount of another asset still blocks', () {
      final result = ProtocolReviewAgreement.compare(
        _request(const [
          ProtocolSummaryLine(
            label: 'You receive',
            amount: '12,000 USDt',
            assetId: 'dd44',
            sats: 1200000000000,
          ),
        ]),
        lab(),
      );
      expect(result.canSign, isFalse);
    });

    test('are read from the request JSON', () {
      final r = ProtocolRequest.fromJson({
        'version': 1,
        'kind': 'sign',
        'site': 'Templar Protocol',
        'network': 'liquid-regtest',
        'nonce': 'n',
        'callback': 'http://127.0.0.1/signed',
        'expires_at': 2000000000,
        'id': 'req-1',
        'action': 'origination',
        'loan_ref': 'SQ-1',
        'pset': 'cHNldP8B',
        'summary': {
          'role': 'borrower',
          'lines': [
            {
              'label': 'You receive',
              'amount': '1 USDt',
              'asset': usdt,
              'sats': 100000000,
            },
            {'label': 'Term', 'amount': '4,320 blocks'},
          ],
        },
      });
      final l = r.summary!.lines;
      expect(l[0].isExact, isTrue);
      expect(l[0].assetId, usdt);
      expect(l[0].sats, 100000000);
      expect(l[1].isExact, isFalse);
    });
  });
}
