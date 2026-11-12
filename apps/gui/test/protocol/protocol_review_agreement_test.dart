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
}
