import 'dart:convert';
import 'dart:math' as math;

import 'wallet_bridge.dart';
import '../features/create_wallet/models/hw_device.dart';
import '../features/create_wallet/models/hw_import_result.dart';
import '../features/create_wallet/models/native_device.dart';
import '../features/protocol/models/protocol_proof.dart';
import '../features/psbt/models/psbt_inspection.dart';
import '../features/psbt/models/pset_inspection.dart';
import '../features/wallet_picker/models/wallet_summary.dart';
import '../features/dashboard/models/balance_history.dart';
import '../features/dashboard/models/dashboard_data.dart';
import '../features/receive/models/address_info.dart';
import '../features/history/models/transaction.dart';
import '../features/history/models/fee_bump_preview.dart';
import '../features/utxos/models/utxo.dart';
import '../features/wallet_info/models/wallet_info.dart';
import '../features/send/models/tx_preview.dart';
import '../features/liquid/models/issue_result.dart';
import '../features/swap/models/swap_offer.dart';
import '../features/peg/models/peg_models.dart';

class MockWalletBridge implements WalletBridge {
  /// The token the mock "Primary" wallet issued, and its reissuance token
  /// (both in [getWalletSummary]). Tests and the tour record the issuance in
  /// `IssuedAssetStore` with these ids to see the Issued assets block.
  static const String mockIssuedAssetId =
      '7f3b2c41d5e6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3';
  static const String mockIssuedTokenId =
      'c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b37f3b';

  @override
  Future<List<String>> generateMnemonic(int wordCount) async {
    await Future.delayed(const Duration(milliseconds: 200));
    const words = [
      'abandon',
      'ability',
      'able',
      'about',
      'above',
      'absent',
      'absorb',
      'abstract',
      'absurd',
      'abuse',
      'access',
      'accident',
      'account',
      'accuse',
      'achieve',
      'acid',
      'acoustic',
      'acquire',
      'across',
      'act',
      'action',
      'actor',
      'actress',
      'actual',
    ];
    return words.sublist(0, wordCount);
  }

  @override
  Future<String> createWallet(
    String name,
    List<String> mnemonic, {
    bool liquid = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 'mock-wallet-${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<List<WalletSummary>> listWallets() async {
    await Future.delayed(const Duration(milliseconds: 400));
    return [
      WalletSummary(
        id: 'wallet-1',
        name: 'Primary',
        type: WalletType.singlesig,
        network: WalletNetwork.testnet,
        liquidEnabled: true,
        balanceSats: 1234567,
        txCount: 42,
        lastSyncAt: DateTime.now().subtract(const Duration(minutes: 3)),
        masterFingerprint: 'deadbeef',
      ),
      WalletSummary(
        id: 'wallet-2',
        name: 'Treasury 2-of-3',
        type: WalletType.multisig,
        network: WalletNetwork.testnet,
        balanceSats: 50000000,
        txCount: 8,
        lastSyncAt: DateTime.now().subtract(const Duration(hours: 1)),
        masterFingerprint: '73c5da0a',
        requiredSigs: 2,
        totalSigners: 3,
      ),
      WalletSummary(
        id: 'wallet-3',
        name: 'Cold Storage',
        type: WalletType.watchOnly,
        network: WalletNetwork.testnet,
        balanceSats: 250000000,
        txCount: 5,
        lastSyncAt: DateTime.now().subtract(const Duration(days: 1)),
        isWatchOnly: true,
        masterFingerprint: 'a1b2c3d4',
      ),
    ];
  }

  @override
  Future<void> openWallet(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<DashboardData> getWalletSummary(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return DashboardData(
      walletId: walletId,
      walletName: 'Primary',
      totalBalanceDisplay: '0.01234567 BTC',
      syncState: 'synced',
      assets: const [
        AssetBalance(
          assetId: 'BTC',
          ticker: 'BTC',
          name: 'Bitcoin',
          amount: 1234567,
          displayAmount: '0.01234567 BTC',
          fiatEstimate: '\$1,200.00',
          status: 'synced',
          utxoCount: 3,
          isNative: true,
        ),
        AssetBalance(
          assetId:
              '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49',
          ticker: 'LBTC',
          name: 'Liquid Bitcoin',
          amount: 500000,
          displayAmount: '0.00500000 LBTC',
          fiatEstimate: '\$485.00',
          status: 'synced',
          utxoCount: 1,
          isNative: false,
        ),
        AssetBalance(
          assetId:
              'b612eb46313a2cd6ebabd8b7a8eed5696e29898b87a43bff41c94f51acef9d73',
          ticker: 'USDT',
          name: 'Tether USD (Liquid)',
          amount: 100000000,
          displayAmount: '100.00 USDT',
          fiatEstimate: '\$100.00',
          status: 'third-party',
          utxoCount: 1,
          isNative: false,
        ),
        // A token this wallet issued, and its reissuance token. The engine
        // knows neither by name (no registry entry): the Liquid page names
        // them from the issued-asset record when one exists on this device.
        AssetBalance(
          assetId: mockIssuedAssetId,
          ticker: mockIssuedAssetId,
          name: mockIssuedAssetId,
          amount: 2500000000000,
          displayAmount: '25,000.00000000 TMPL',
          status: 'synced',
          utxoCount: 2,
          isNative: false,
        ),
        AssetBalance(
          assetId: mockIssuedTokenId,
          ticker: mockIssuedTokenId,
          name: mockIssuedTokenId,
          amount: 100000000,
          displayAmount: '1.00000000 RT',
          status: 'synced',
          utxoCount: 1,
          isNative: false,
        ),
      ],
      recentActivity: [
        RecentActivityItem(
          txid:
              'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
          direction: 'incoming',
          chain: 'bitcoin',
          amount: '+0.005 BTC',
          ticker: 'BTC',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
          confirmations: 6,
          counterparty: 'tb1q…4x2p',
        ),
        RecentActivityItem(
          txid:
              '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
          direction: 'outgoing',
          chain: 'bitcoin',
          amount: '-0.001 BTC',
          ticker: 'BTC',
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
          confirmations: 144,
          note: 'Coffee',
        ),
        RecentActivityItem(
          txid:
              'fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321',
          direction: 'incoming',
          chain: 'liquid',
          amount: '+100 USDT',
          ticker: 'USDT',
          timestamp: DateTime.now().subtract(const Duration(days: 3)),
          confirmations: 500,
        ),
      ],
    );
  }

  /// Mock index advances with [fresh], mirroring the real derivation.
  int _mockAddressIndex = 5;

  @override
  Future<AddressInfo> generateReceiveAddress(
    String walletId,
    String asset, {
    bool fresh = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final isLiquid = asset == 'LBTC' || asset == 'L-BTC' || asset == 'liquid';
    if (isLiquid) {
      // Confidential Liquid testnet address (blech32, tlq1 HRP).
      return const AddressInfo(
        address:
            'tlq1qqw3z9v9y6qd4t0h3z8m6a4v9k2p5r8s7c6x4d2f9g0h1j3k5l7m9n1p3q5r7t9v2x4z6b8d0f',
        index: 5,
        asset: 'LBTC',
        derivationPath: "m/84'/1'/0'/0/5",
      );
    }
    if (fresh) _mockAddressIndex++;
    final i = _mockAddressIndex;
    return AddressInfo(
      address:
          'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjz${i.toString().padLeft(2, '0')}',
      index: i,
      asset: 'BTC',
      derivationPath: "m/84'/1'/0'/0/$i",
    );
  }

  @override
  Future<List<AddressInfo>> listPreviousAddresses(
    String walletId,
    String asset,
  ) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      AddressInfo(
        address: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
        index: 4,
        asset: asset,
        label: 'Payment from Alice',
        receivedSats: 500000,
      ),
      AddressInfo(
        address: 'tb1qrp33g0q5c5txsp9arfj2k5eer7t5d5uu9r6zx3',
        index: 3,
        asset: asset,
        receivedSats: 0,
      ),
      AddressInfo(
        address: 'tb1q6rfmyvrl56kkxsmfkm2y4z4rkxkqgz4k3j5x7',
        index: 2,
        asset: asset,
        label: 'Faucet',
        receivedSats: 1234567,
      ),
    ];
  }

  @override
  Future<List<Transaction>> listActivity(
    String walletId, {
    String? chain,
    String? asset,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return [
      Transaction(
        txid:
            '9999999999999999999999999999999999999999999999999999999999999999',
        direction: TxDirection.outgoing,
        chain: TxChain.bitcoin,
        // As the engine reports an outgoing payment: its net outflow, the
        // 40,000 sats paid plus the 141 of fee.
        amount: '-0.00040141 BTC',
        ticker: 'BTC',
        timestamp: DateTime.now(),
        confirmations: 0,
        fee: '141 sats',
        feeSats: 141,
        feeRate: 1,
        vsize: 141,
        isReplaceable: true,
        canRbf: true,
        canCpfp: true,
        canCancel: true,
      ),
      Transaction(
        txid:
            'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        direction: TxDirection.incoming,
        chain: TxChain.bitcoin,
        amount: '+0.005 BTC',
        ticker: 'BTC',
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        confirmations: 6,
        counterparty: 'tb1q…4x2p',
        fee: '280 sats',
        fiatEstimate: '+\$485.00',
      ),
      Transaction(
        txid:
            '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef',
        direction: TxDirection.outgoing,
        chain: TxChain.bitcoin,
        amount: '-0.001 BTC',
        ticker: 'BTC',
        timestamp: DateTime.now().subtract(const Duration(days: 1)),
        confirmations: 144,
        note: 'Coffee',
        fee: '192 sats',
        fiatEstimate: '-\$97.00',
      ),
      Transaction(
        txid:
            'fedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321',
        direction: TxDirection.incoming,
        chain: TxChain.liquid,
        amount: '+100 USDT',
        ticker: 'USDT',
        timestamp: DateTime.now().subtract(const Duration(days: 3)),
        confirmations: 500,
        fee: '100 sats',
      ),
    ];
  }

  @override
  Future<FeeBumpPreview> previewFeeBump({
    required String walletId,
    required String txid,
    required String action,
    required String method,
    required double feeRate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final resolved = action == 'cancel'
        ? 'cancel'
        : method == 'cpfp'
        ? 'cpfp'
        : 'rbf';
    final cpfp = resolved == 'cpfp';
    return FeeBumpPreview(
      method: resolved,
      originalTxid: txid,
      // Tagged with the method, so [inspectPsbt] reads the blob back as the
      // bump it is (the fee-bump dialog draws the transaction from it).
      psbtBase64: 'cHNidP8BAAoCAAAAAQ==$_mockBumpMarker$resolved',
      oldFeeSats: 141,
      oldFeeRate: 1,
      oldVsize: 141,
      newFeeSats: cpfp ? 1000 : 1128,
      newFeeRate: 8,
      newVsize: cpfp ? 125 : 141,
      extraFeeSats: cpfp ? 1000 : 987,
      effectiveFeeRate: 8,
      totalFeeSats: cpfp ? 1141 : 1128,
    );
  }

  static const _mockBumpMarker = '~bump-';

  /// What [inspectPsbt] answers for a PSBT from [previewFeeBump]: the pending
  /// 40,000 sat payment, re-priced. Figures agree with that preview — the RBF
  /// replacement keeps its coin and its recipient and gives 987 sats of
  /// change to the fee.
  PsbtInspection _mockBumpInspection(String psbtBase64, int signed) {
    const coin = PsbtInput(
      outpoint:
          '5f3c9a1e7b2d4c6f8a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f:0',
      amountSats: 50000,
      displayAmount: '0.00050000 BTC',
      isMine: true,
    );
    const parentChange = PsbtInput(
      outpoint:
          '9999999999999999999999999999999999999999999999999999999999999999:1',
      amountSats: 9859,
      displayAmount: '0.00009859 BTC',
      isMine: true,
    );
    PsbtOutput mine(int sats) => PsbtOutput(
      address: 'tb1qmockchangeaddr9999',
      amountSats: sats,
      displayAmount: '$sats sats',
      isMine: true,
    );
    const recipient = PsbtOutput(
      address: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      amountSats: 40000,
      displayAmount: '0.00040000 BTC',
      isMine: false,
    );
    final cpfp = psbtBase64.contains('${_mockBumpMarker}cpfp');
    final cancel = psbtBase64.contains('${_mockBumpMarker}cancel');
    final fee = cpfp ? 1000 : 1128;
    return PsbtInspection(
      inputs: [cpfp ? parentChange : coin],
      outputs: cpfp
          ? [mine(8859)]
          : cancel
          ? [mine(48872)]
          : [recipient, mine(8872)],
      feeSats: fee,
      feeDisplay: '$fee sats',
      sigsPresent: signed.clamp(0, 1),
      sigsRequired: 1,
      signers: [PsbtSigner(fingerprint: 'deadbeef', hasSigned: signed > 0)],
      policyHint: '',
      rawPsbt: psbtBase64,
      ownershipKnown: true,
    );
  }

  /// Coins frozen in this session — the engine keeps them on the registry
  /// entry; the mock only needs them to survive a reload of the screen.
  final Set<String> _frozen = {};

  @override
  Future<void> setUtxosFrozen({
    required String walletId,
    required String chain,
    required List<String> outpoints,
    required bool frozen,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    frozen ? _frozen.addAll(outpoints) : _frozen.removeAll(outpoints);
  }

  @override
  Future<List<Utxo>> listUtxos(String walletId, String chain) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      for (final u in _mockUtxos)
        _frozen.contains(u.outpoint) ? u.copyWith(state: UtxoState.frozen) : u,
    ];
  }

  // Six settled coins on four addresses — one address was paid three times,
  // so the wall has a tray with several notes in it — and a payment still in
  // the mempool. The settled ones add up to the summary's 0.01234567 BTC.
  static const List<Utxo> _mockUtxos = [
    Utxo(
      outpoint:
          'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890:0',
      amount: 600000,
      displayAmount: '0.00600000 BTC',
      confirmations: 6,
      state: UtxoState.available,
      address: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
    ),
    Utxo(
      outpoint:
          '1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef:1',
      amount: 334567,
      displayAmount: '0.00334567 BTC',
      confirmations: 144,
      state: UtxoState.available,
      label: 'Change',
      address: 'tb1qrp33g0q5c5txsp9arfj2k5eer7t5d5uu9r6zx3',
    ),
    Utxo(
      outpoint:
          '5e2f9a7c1b3d4e6f8091a2b3c4d5e6f708192a3b4c5d6e7f8091a2b3c4d5e6f7:0',
      amount: 200000,
      displayAmount: '0.00200000 BTC',
      confirmations: 310,
      state: UtxoState.available,
      label: 'October',
      address: 'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a',
    ),
    Utxo(
      outpoint:
          '7c41d09e5ab26f38c7d1e4f5a6b7c8d9e0f1a2b3c4d5e6f708192a3b4c5d6e7f:2',
      amount: 80000,
      displayAmount: '0.00080000 BTC',
      confirmations: 1021,
      state: UtxoState.available,
      address: 'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a',
    ),
    Utxo(
      outpoint:
          '0f6b3e8d2a4c5e7f9b1d3f5a7c9e1b3d5f7a9c1e3b5d7f9a1c3e5b7d9f1a3c5e:0',
      amount: 19454,
      displayAmount: '0.00019454 BTC',
      confirmations: 2260,
      state: UtxoState.available,
      address: 'tb1q9d4ywgfnd8h43da5tpcxcn6ajv590cg6d3tg6a',
    ),
    Utxo(
      outpoint:
          'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef:0',
      amount: 546,
      displayAmount: '546 sats',
      confirmations: 12,
      state: UtxoState.dusty,
      address: 'tb1q6rfmyvrl56kkxsmfkm2y4z4rkxkqgz4k3j5x7',
    ),
    // A payment still in the mempool, to an address that already holds a
    // coin: the dashed provisional note, beside the settled one.
    Utxo(
      outpoint:
          'cafebabecafebabecafebabecafebabecafebabecafebabecafebabecafebabe:1',
      amount: 150000,
      displayAmount: '0.00150000 BTC',
      confirmations: 0,
      state: UtxoState.unconfirmed,
      address: 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
    ),
  ];

  @override
  Future<WalletInfo> getWalletInfo(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    // "Treasury 2-of-3" is the mock's multisig, and the only wallet here with
    // co-signers to draw. Without them the key ring has nothing to show in
    // mock mode, which is where the phone layouts are checked.
    if (walletId == 'wallet-2') {
      const keys = [
        "[73c5da0a/48'/1'/0'/2']tpubDErWN5qfdLwYE1DbaXTdCsD3fnRDpMkgYPFTa5RmwDNXhtcH2GDsyzhF1JzMxCq2ceZ4qniA9r4qCcHXnPtQKvKk3jUYSxUwiUJHqvvJcW6",
        "[f0b68896/48'/1'/0'/2']tpubDCVwWj4hEpeWNFcWe3Eo1DrkLnPC4c2iitjw5wAuTkSZgofJbRMD4KESh1uhsqLCCjcjR36JooEFwfWf1ezwmAfjcPCxc7KNtnfBCrMPdtT",
        "[a1b2c3d4/48'/1'/0'/2']tpubDDsVS9pMxpJcpFR7WhWpKrML6UyuMqZjKZMdUYYPnJPPTNVmuBKvHzHfCMDzcBWmQVLBGZWaLNqYYYUYrDaLbUJPTGdVWKKqnnEXrDJKcJc",
      ];
      return WalletInfo(
        id: walletId,
        name: 'Treasury 2-of-3',
        network: 'Testnet',
        masterFingerprint: '73c5da0a',
        derivationPath: "m/48'/1'/0'/2'",
        scriptType: 'P2WSH 2-of-3 Multisig',
        xpub: '',
        receiveDescriptor: 'wsh(sortedmulti(2,${keys.join('/0/*,')}/0/*))',
        changeDescriptor: 'wsh(sortedmulti(2,${keys.join('/1/*,')}/1/*))',
        cosignerKeys: keys,
        requiredSigs: 2,
        localFingerprints: const ['73c5da0a'],
        hasSeed: false,
      );
    }
    return WalletInfo(
      id: walletId,
      name: 'Primary',
      network: 'Testnet',
      masterFingerprint: 'deadbeef',
      derivationPath: "m/84'/1'/0'",
      scriptType: 'P2WPKH (Native SegWit)',
      xpub:
          'tpubDC7KMhGhFE2MhAJXrWMxumRnpFDqgtQQiQSFLGCaAk5CW8BQBuNr7PKRqNGV1ZB6qKP3zERkHV7DGUzPMDQc2y4kF7K8UrHeRfFXWkHPPjE',
      receiveDescriptor:
          'wpkh([deadbeef/84h/1h/0h]tpubDC7KMhGhFE2MhAJXrWMxumRnpFDqgtQQiQSFLGCaAk5CW8BQBuNr7PKRqNGV1ZB6qKP3zERkHV7DGUzPMDQc2y4kF7K8UrHeRfFXWkHPPjE/0/*)',
      changeDescriptor:
          'wpkh([deadbeef/84h/1h/0h]tpubDC7KMhGhFE2MhAJXrWMxumRnpFDqgtQQiQSFLGCaAk5CW8BQBuNr7PKRqNGV1ZB6qKP3zERkHV7DGUzPMDQc2y4kF7K8UrHeRfFXWkHPPjE/1/*)',
      multipathDescriptor:
          'wpkh([deadbeef/84h/1h/0h]tpubDC7KMhGhFE2MhAJXrWMxumRnpFDqgtQQiQSFLGCaAk5CW8BQBuNr7PKRqNGV1ZB6qKP3zERkHV7DGUzPMDQc2y4kF7K8UrHeRfFXWkHPPjE/<0;1>/*)',
      // "Primary" is the mock wallet with a Liquid side, so it is the one
      // that has a confidential descriptor to show.
      liquidDescriptor: walletId == 'wallet-1'
          ? 'ct(slip77(9c8e4f05c7711a98c838be228bcb84924d4570ca53f35fa1c793e58841d47023),'
                'elwpkh([deadbeef/84h/1h/0h]tpubDC7KMhGhFE2MhAJXrWMxumRnpFDqgtQQiQSFLGCaAk5CW8BQBuNr7PKRqNGV1ZB6qKP3zERkHV7DGUzPMDQc2y4kF7K8UrHeRfFXWkHPPjE/<0;1>/*))'
          : null,
      masterBlindingKey: walletId == 'wallet-1'
          ? '9c8e4f05c7711a98c838be228bcb84924d4570ca53f35fa1c793e58841d47023'
          : null,
      hasSeed: true,
      hasPassphrase: false,
      lastBackupAt: DateTime.now().subtract(const Duration(days: 5)),
    );
  }

  @override
  Future<BalanceHistory> getBalanceHistory(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 250));
    // 60 days of daily points: a gently rising random walk with a few step
    // deposits, scaled so the last point lands exactly on the mock balances
    // reported by getWalletSummary.
    const days = 60;
    const btcNow = 1234567;
    const lbtcNow = 500000;
    final btcWalk = _mockWalk(walletId.hashCode ^ 0xB7C, days + 1, const [
      11,
      29,
      47,
    ]);
    final lbtcWalk = _mockWalk(walletId.hashCode ^ 0x1B7C, days + 1, const [
      19,
      44,
    ]);
    final now = DateTime.now();
    return BalanceHistory(
      points: [
        for (var i = 0; i <= days; i++)
          BalanceHistoryPoint(
            time: now.subtract(Duration(hours: (days - i) * 24 + (i % 7) * 2)),
            btcSats: (btcNow * btcWalk[i] / btcWalk.last).round(),
            lbtcSats: (lbtcNow * lbtcWalk[i] / lbtcWalk.last).round(),
          ),
      ],
      btcSats: btcNow,
      lbtcSats: lbtcNow,
      hasBitcoin: true,
      hasLiquid: true,
    );
  }

  /// Multiplicative random walk with a slight upward bias, jumped at [steps]
  /// to mimic deposits. Seeded so a wallet's chart is stable across reloads.
  static List<double> _mockWalk(int seed, int n, List<int> steps) {
    final rng = math.Random(seed);
    final out = <double>[];
    var v = 1.0;
    for (var i = 0; i < n; i++) {
      v *= 1 + (rng.nextDouble() - 0.42) * 0.06;
      if (steps.contains(i)) v *= 1.22;
      out.add(v);
    }
    return out;
  }

  @override
  Future<Map<String, String>> syncWallet(String walletId) async {
    await Future.delayed(const Duration(seconds: 2));
    return {'btc': 'ok', 'liquid': 'ok'};
  }

  @override
  Future<TxPreview> previewTransaction({
    required String walletId,
    required List<TxOutputSpec> outputs,
    required String assetId,
    required double feeRate,
    List<String>? utxos,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final amountSats = outputs.fold(0, (s, o) => s + o.amountSats);
    final address = outputs.isNotEmpty ? outputs.first.address : '';
    final fee = (feeRate * 150).round();
    final inputs = utxos != null && utxos.isNotEmpty
        ? [
            for (final op in utxos)
              TxIo(
                outpoint: op,
                address: 'tb1qmockinput${op.hashCode.abs() % 10000}',
                amountSats: amountSats + fee,
                isChange: false,
              ),
          ]
        : [
            TxIo(
              outpoint:
                  'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888:0',
              address: 'tb1qmockautoselected0000',
              amountSats: amountSats + fee + 25000,
              isChange: false,
            ),
          ];
    final inTotal = inputs.fold(0, (s, i) => s + i.amountSats);
    final change = inTotal - amountSats - fee;
    return TxPreview(
      chain: assetId == 'BTC' ? 'bitcoin' : 'liquid',
      recipientAddress: address,
      amountDisplay: assetId == 'BTC'
          ? '${(amountSats / 1e8).toStringAsFixed(8)} BTC'
          : '$amountSats sats',
      feeSats: fee,
      feeDisplay: '$fee sats (${feeRate.toStringAsFixed(1)} sat/vB)',
      totalDisplay: assetId == 'BTC'
          ? '${((amountSats + fee) / 1e8).toStringAsFixed(8)} BTC'
          : '${amountSats + fee} sats total',
      feeRate: feeRate,
      vsizeEst: 150,
      inputs: inputs,
      outputs: [
        for (final o in outputs)
          TxIo(address: o.address, amountSats: o.amountSats, isChange: false),
        if (change > 0)
          TxIo(
            address: 'tb1qmockchangeaddr9999',
            amountSats: change,
            isChange: true,
          ),
      ],
    );
  }

  @override
  Future<String> sendTransaction({
    required String walletId,
    required List<TxOutputSpec> outputs,
    required String assetId,
    required double feeRate,
    List<String>? utxos,
  }) async {
    await Future.delayed(const Duration(seconds: 2));
    // A multisig wallet cannot finish alone: the engine answers with a JSON
    // object carrying the partial PSBT instead of a txid, and the Send screen
    // opens its co-signature sheet on it. Mirrored here so that sheet — and
    // its quorum chart — is reachable on mock data.
    if (_isMultisigWallet(walletId)) {
      return jsonEncode({
        'partial_psbt': '$_mockPsbtBody$_mockSigMarker',
        'sigs_have': 1,
        'sigs_needed': 2,
      });
    }
    return 'mock_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Body of every mock PSBT. Signatures are appended as [_mockSigMarker]s,
  /// so pasting a "signed" copy back moves the quorum chart the way a real
  /// one does.
  static const _mockPsbtBody = 'cHNidP8BAH0mock';
  static const _mockSigMarker = '~sig';

  /// The mock's own multisig wallets: the seeded Treasury, and anything the
  /// multisig wizard created in this session.
  bool _isMultisigWallet(String walletId) =>
      walletId == 'wallet-2' || walletId.startsWith('ms_');

  @override
  Future<IssueResult> issueAsset({
    required String walletId,
    required String name,
    required String ticker,
    required int precision,
    String? domain,
    required int amountSats,
    required int reissuanceTokens,
  }) async {
    await Future.delayed(const Duration(seconds: 2));
    const assetId =
        'abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234';
    final d = (domain ?? '').trim();
    if (!_onLab && d.isEmpty) {
      throw Exception(
        'wallet-ffi: A domain is required to issue an asset on Liquid testnet',
      );
    }
    lastIssue = {
      'name': name,
      'ticker': ticker,
      'precision': precision,
      'domain': domain,
      'amount_sats': amountSats,
      'reissuance_tokens': reissuanceTokens,
    };
    // On a lab's regtest: no public registry and no proof; the book's
    // registry is asked at once (refused when [mockBookRegisterError]).
    final bookError = mockBookRegisterError;
    return IssueResult(
      assetId: assetId,
      tokenId: reissuanceTokens > 0
          ? 'efgh5678efgh5678efgh5678efgh5678efgh5678efgh5678efgh5678efgh5678'
          : null,
      txid: 'mock_issue_txid_${DateTime.now().millisecondsSinceEpoch}',
      registryRegistered: false,
      proofUrl: _onLab
          ? ''
          : 'https://$d/.well-known/liquid-asset-proof-$assetId',
      proofContent: _onLab
          ? ''
          : 'Authorize linking the domain name $d to the Liquid asset $assetId',
      bookRegistered: bookError == null,
      bookError: bookError,
      domain: _onLab && d.isEmpty ? 'regtest.templar.test' : d,
    );
  }

  /// The parameters of the last `issue_asset` (tests).
  Map<String, Object?>? lastIssue;

  /// The order book's refusal of the next registrations; null = stored.
  String? mockBookRegisterError;

  @override
  Future<IssueResult> reissueAsset({
    required String walletId,
    required String assetId,
    required int amountSats,
  }) async {
    await Future.delayed(const Duration(seconds: 2));
    return IssueResult(
      assetId: assetId,
      txid: 'mock_reissue_txid_${DateTime.now().millisecondsSinceEpoch}',
      registryRegistered: false,
      proofUrl: '',
      proofContent: '',
    );
  }

  @override
  Future<String> burnAsset({
    required String walletId,
    required String assetId,
    required int amountSats,
  }) async {
    await Future.delayed(const Duration(seconds: 2));
    return 'mock_burn_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  // ── LiquiDEX swaps (mock) ─────────────────────────────────────────────────
  //
  // New-feature models (SwapAnalysis, MyOffer, Peg*) are built via fromJson
  // with contract-shaped snake_case maps, mirroring what wallet-ffi returns.

  static const _lbtcTestnet =
      '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';
  static const _lbtcMainnet =
      '6f0279e9ed041c3d710a9f57d0c02928416460c4b722ae3457a11eec381c526d';
  static const _usdtTestnet =
      'b612eb46313a2cd6ebabd8b7a8eed5696e29898b87a43bff41c94f51acef9d73';
  static const _dbeerMainnet =
      '002452cb8f56a0a5628240edfb3d1e966c9b1959adcfb95b5726e5e9688611bf';

  static final _testnetProposalJson =
      '{"version":0,"tx":"0200000001016d0ck00000000000000000000000000000000000'
      '000000000000000000000000000000000ffffffff","inputs":[{"asset":'
      '"$_usdtTestnet","asset_blinder":"11${'0' * 62}","amount_blinder":'
      '"22${'0' * 62}","amount":500000000}],"outputs":[{"asset":"$_lbtcTestnet",'
      '"asset_blinder":"33${'0' * 62}","amount_blinder":"44${'0' * 62}",'
      '"amount":5000}]}';

  static Map<String, dynamic> _leg(
    String assetId,
    String ticker,
    int amountSats,
    String displayAmount,
  ) => {
    'asset_id': assetId,
    'ticker': ticker,
    'amount_sats': amountSats,
    'display_amount': displayAmount,
  };

  static Map<String, dynamic> _cannedAnalysisJson({required bool deep}) {
    final chainOk = deep ? true : null;
    final chainNote = deep ? null : 'needs chain access';
    return {
      'valid': true,
      'checks': [
        {'name': 'structure', 'ok': true, 'note': null},
        {'name': 'sighash_single_acp', 'ok': true, 'note': null},
        {'name': 'output_commitments', 'ok': true, 'note': null},
        {'name': 'input_commitments', 'ok': chainOk, 'note': chainNote},
        {'name': 'input_unspent', 'ok': chainOk, 'note': chainNote},
        {'name': 'signature', 'ok': chainOk, 'note': chainNote},
      ],
      'maker_offers': _leg(_usdtTestnet, 'USDT', 500000000, '5.00'),
      'maker_wants': _leg(_lbtcTestnet, 'LBTC', 5000, '0.00005000'),
      'network': 'testnet',
      // The engine only grants takeability after deep (chain) verification.
      'takeable': deep,
      'take_block_reason': deep
          ? null
          : 'deep (chain) verification required before taking',
    };
  }

  @override
  Future<List<SwapOffer>> listSwaps({bool includeUnavailable = false}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final offers = [
      SwapOffer.fromJson({
        'id': 101,
        'available': true,
        'receive': _leg(_usdtTestnet, 'USDT', 500000000, '5.00'),
        'pay': _leg(_lbtcTestnet, 'LBTC', 5000, '0.00005000'),
        'price': 0.00001,
        'price_display': '0.00001000 LBTC/USDT',
        'created': 'Mon, 03 Aug 2026 10:15:00 GMT',
        'verified': true,
        'verify_note': null,
        'proposal_json': _testnetProposalJson,
        'network': 'testnet',
        'takeable': true,
        'kind': 'swap',
      }),
      SwapOffer.fromJson({
        'id': 13,
        'available': true,
        'receive': _leg(_dbeerMainnet, 'DBEER', 1000, '10.00'),
        'pay': _leg(_lbtcMainnet, 'LBTC', 1000, '0.00001000'),
        'price': 1.0,
        'price_display': '1.00000000 LBTC/DBEER',
        'created': 'Wed, 09 Jun 2021 16:37:38 GMT',
        'verified': true,
        'verify_note': null,
        'proposal_json':
            '{"version":0,"tx":"0200…mock","inputs":[],"outputs":[]}',
        'network': 'mainnet',
        'takeable': false,
        'kind': 'swap',
      }),
      SwapOffer.fromJson({
        'id': 12,
        'available': false,
        'receive': _leg(_lbtcMainnet, 'LBTC', 50000, '0.00050000'),
        'pay': _leg(_dbeerMainnet, 'DBEER', 5200, '52.00'),
        'price': 9.6,
        'price_display': '9.60 DBEER/LBTC',
        'created': 'Sun, 14 Jun 2026 09:30:00 GMT',
        'verified': true,
        'verify_note': null,
        'proposal_json':
            '{"version":0,"tx":"0200…mock2","inputs":[],"outputs":[]}',
        'network': 'mainnet',
        'takeable': false,
        'kind': 'swap',
      }),
    ];
    return includeUnavailable
        ? offers
        : offers.where((o) => o.available).toList();
  }

  @override
  Future<List<MarketOffer>> listMarkets({
    bool includeUnavailable = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 350));
    // On the mock lab's regtest: its book, with a token named by the book's
    // registry (not by this wallet) and no cross-chain routes.
    if (_onLab) return [_labMarket()];
    final offers = [
      MarketOffer.fromJson({
        'id': 'liquid:101',
        'source_id': 101,
        'status': 'open',
        'settlement': 'liquidex-v0',
        'demo': false,
        'available': true,
        'maker_gives': {
          'chain': 'liquid',
          'network': 'liquid-testnet',
          'asset_id': _usdtTestnet,
          'ticker': 'USDT',
          'name': 'Tether USD',
          'precision': 8,
          'amount_sats': 500000000,
          'display_amount': '5.00',
        },
        'maker_wants': {
          'chain': 'liquid',
          'network': 'liquid-testnet',
          'asset_id': _lbtcTestnet,
          'ticker': 'LBTC',
          'name': 'Liquid Bitcoin',
          'precision': 8,
          'amount_sats': 5000,
          'display_amount': '0.00005000',
        },
        'price_display': '0.00001000 LBTC/USDT',
        'note': 'Verified local LiquiDEX offer',
        'created_at': 1785752100,
        'proposal_json': _testnetProposalJson,
        'verified': true,
        'takeable': true,
        'block_reason': null,
      }),
      MarketOffer.fromJson({
        'id': 'demo:1',
        'source_id': 1,
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
          'amount_sats': 120000,
          'display_amount': '0.00120000',
        },
        'maker_wants': {
          'chain': 'liquid',
          'network': 'liquid-testnet',
          'asset_id': _usdtTestnet,
          'ticker': 'USDT',
          'name': 'Tether USD',
          'precision': 8,
          'amount_sats': 12000000000,
          'display_amount': '120.00',
        },
        'price_display': '100000.00 USDT/BTC',
        'note': 'Cross-chain experience preview',
        'created_at': 1785753100,
        'proposal_json': '',
        'verified': false,
        'takeable': false,
        'block_reason':
            'HTLC settlement is intentionally disabled in this UI/UX demo build',
      }),
      MarketOffer.fromJson({
        'id': 'demo:2',
        'source_id': 2,
        'status': 'open',
        'settlement': 'htlc-demo',
        'demo': true,
        'available': true,
        'maker_gives': {
          'chain': 'liquid',
          'network': 'liquid-testnet',
          'asset_id': _lbtcTestnet,
          'ticker': 'LBTC',
          'name': 'Liquid Bitcoin',
          'precision': 8,
          'amount_sats': 250000,
          'display_amount': '0.00250000',
        },
        'maker_wants': {
          'chain': 'bitcoin',
          'network': 'bitcoin-testnet',
          'asset_id': 'btc',
          'ticker': 'BTC',
          'name': 'Bitcoin',
          'precision': 8,
          'amount_sats': 245000,
          'display_amount': '0.00245000',
        },
        'price_display': '0.98 BTC/LBTC',
        'note': 'Two-chain atomic path preview',
        'created_at': 1785754100,
        'proposal_json': '',
        'verified': false,
        'takeable': false,
        'block_reason':
            'HTLC settlement is intentionally disabled in this UI/UX demo build',
      }),
    ];
    return includeUnavailable
        ? offers
        : offers.where((offer) => offer.available).toList();
  }

  /// The id of the token the mock lab's book names `TMPL` (precision 2).
  static const String mockLabTokenId =
      '80d249a8c1f5e3b7a9d2c4e6f8a0b1c3d5e7f9a1b3c5d7e9f0a2b4c6d8e0f1a3';

  MarketOffer _labMarket() => MarketOffer.fromJson({
    'id': 'liquid:7',
    'source_id': 7,
    'status': 'open',
    'settlement': 'liquidex-v0',
    'demo': false,
    'available': true,
    'maker_gives': {
      'chain': 'liquid',
      'network': 'liquid-regtest',
      'asset_id': mockLabTokenId,
      'ticker': 'TMPL',
      'name': 'Templar Token',
      'precision': 2,
      'amount_sats': 10000,
      'display_amount': '100.00',
      'metadata_source': 'book',
      'book_source': 'contract',
    },
    'maker_wants': {
      'chain': 'liquid',
      'network': 'liquid-regtest',
      'asset_id': _labPolicyAsset,
      'ticker': 'LBTC',
      'name': 'Liquid Bitcoin',
      'precision': 8,
      'amount_sats': 5000000,
      'display_amount': '0.05000000',
      'metadata_source': 'wallet',
    },
    'price_display': '100.00 → 0.05000000',
    'note': '',
    'created_at': 1794944627,
    'proposal_json': _testnetProposalJson,
    'verified': true,
    'takeable': true,
    'block_reason': null,
  });

  @override
  Future<SwapAnalysis> swapVerify(
    String proposalJson, {
    bool deep = false,
  }) async {
    await Future.delayed(Duration(milliseconds: deep ? 900 : 250));
    return SwapAnalysis.fromJson(_cannedAnalysisJson(deep: deep));
  }

  @override
  Future<SwapTakePreview> swapTakePreview(
    String walletId,
    String proposalJson, {
    double? feeRate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 900));
    return SwapTakePreview.fromJson({
      'you_receive': _leg(_usdtTestnet, 'USDT', 500000000, '5.00'),
      'you_pay': _leg(_lbtcTestnet, 'LBTC', 5000, '0.00005000'),
      'fee_sats': 273,
      'fee_display': '273 sats',
      'change': [_leg(_lbtcTestnet, 'LBTC', 94727, '0.00094727')],
      'analysis': _cannedAnalysisJson(deep: true),
    });
  }

  @override
  Future<String> swapTake(
    String walletId,
    String proposalJson, {
    double? feeRate,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return 'mock_swap_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  static String _hex8() => (DateTime.now().microsecondsSinceEpoch & 0xffffffff)
      .toRadixString(16)
      .padLeft(8, '0');

  static int _nowSecs() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  final List<Map<String, dynamic>> _myOffers = [
    {
      'offer_id': 'of_a1b2c3d4',
      'kind': 'swap',
      'status': 'open',
      'created_at': _nowSecs() - 10800,
      'offers': _leg(_lbtcTestnet, 'LBTC', 25000, '0.00025000'),
      'wants': _leg(_usdtTestnet, 'USDT', 2500000000, '25.00'),
      'proposal_json': _testnetProposalJson,
      'utxo':
          'aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888:1',
    },
    // An older offer whose coin has since been spent: Activity's closed row.
    {
      'offer_id': 'of_9e8d7c6b',
      'kind': 'swap',
      'status': 'closed',
      'created_at': _nowSecs() - 2 * 86400 - 5400,
      'offers': _leg(_lbtcTestnet, 'LBTC', 100000, '0.00100000'),
      'wants': _leg(_usdtTestnet, 'USDT', 6800000000, '68.00'),
      'proposal_json': _testnetProposalJson,
      'utxo':
          'cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888aaaa1111bbbb2222:0',
    },
  ];

  @override
  Future<MyOffer> swapMake(
    String walletId,
    String utxo,
    String wantAssetId,
    int wantAmountSats,
  ) async {
    await Future.delayed(const Duration(milliseconds: 700));
    final wantTicker = wantAssetId == _lbtcTestnet ? 'LBTC' : 'USDT';
    final wantDisplay = wantAssetId == _lbtcTestnet
        ? (wantAmountSats / 1e8).toStringAsFixed(8)
        : (wantAmountSats / 1e8).toStringAsFixed(2);
    final offer = {
      'offer_id': 'of_${_hex8()}',
      'kind': 'swap',
      'status': 'open',
      'created_at': _nowSecs(),
      'offers': _leg(_lbtcTestnet, 'LBTC', 10000, '0.00010000'),
      'wants': _leg(wantAssetId, wantTicker, wantAmountSats, wantDisplay),
      'proposal_json': _testnetProposalJson,
      'utxo': utxo,
    };
    _myOffers.insert(0, offer);
    return MyOffer.fromJson(offer);
  }

  @override
  Future<String> swapMakePrepare(
    String walletId,
    String assetId,
    int amountSats, {
    double? feeRate,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    return 'mock_prepare_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<int> swapPublish(String proposalJson, {String note = ''}) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return 1;
  }

  @override
  Future<List<MyOffer>> listMyOffers(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final err = mockMyOffersError;
    if (err != null) throw Exception('wallet-ffi: $err');
    return _myOffers.map(MyOffer.fromJson).toList();
  }

  /// Knobs for My swaps: the next `list_my_offers` / `atomic_swap_list`
  /// fails with this text (tests of one list failing without the other).
  String? mockMyOffersError;
  String? mockAtomicSwapListError;

  @override
  Future<String> swapCancel(String walletId, String offerId) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final offer = _myOffers.firstWhere(
      (o) => o['offer_id'] == offerId,
      orElse: () => throw Exception('wallet-ffi: unknown offer $offerId'),
    );
    if (offer['status'] != 'open') {
      throw Exception('wallet-ffi: offer is not open');
    }
    offer['status'] = 'cancelled';
    return 'mock_cancel_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<AtomicSwap> atomicSwapCreate({
    required String walletId,
    required String direction,
    required int btcAmountSats,
    required String liquidAssetId,
    required String liquidTicker,
    required String liquidName,
    required int liquidPrecision,
    required int liquidAmountSats,
    String note = '',
  }) async =>
      throw UnimplementedError('Atomic swaps require the native engine');
  @override
  Future<AtomicSwap> atomicSwapJoin(String walletId, int offerId) async =>
      throw UnimplementedError('Atomic swaps require the native engine');
  @override
  Future<List<AtomicSwap>> atomicSwapList(String walletId) async {
    // Off Liquid testnet the engine answers [] at once (no coordinator).
    if (_liquidNetwork != 'testnet') return const [];
    final err = mockAtomicSwapListError;
    if (err != null) throw Exception('wallet-ffi: $err');
    // "Primary" (both chains) has one swap under way, so Activity and
    // LiquiDEX have a cross-chain row to draw; every other wallet has none.
    if (walletId != 'wallet-1') return const [];
    await Future.delayed(const Duration(milliseconds: 300));
    return [
      AtomicSwap.fromJson({
        'offer_id': 7,
        'role': 'taker',
        'next_action': 'wait',
        'can_fund': false,
        'can_claim': false,
        'can_refund': false,
        'row': {
          'status': 'funded',
          'state': {
            'offered_chain': 'liquid',
            'offered_asset_id': _usdtTestnet,
            'offered_ticker': 'USDT',
            'offered_name': 'Tether USD',
            'offered_precision': 8,
            'offered_amount_sats': 6800000000,
            'wanted_chain': 'bitcoin',
            'wanted_asset_id': 'btc',
            'wanted_ticker': 'BTC',
            'wanted_name': 'Bitcoin',
            'wanted_precision': 8,
            'wanted_amount_sats': 100000,
            'maker_timeout': 2905210,
            'taker_timeout': 2905150,
          },
        },
      }),
    ];
  }

  /// A Templar Protocol portfolio (`GET /connector/portfolio`, CONNECTOR.md
  /// §7) for "Primary", so Activity has loans to draw in mock mode. Not a
  /// bridge method — the real app asks the connected site — and null for
  /// every other wallet.
  Map<String, dynamic>? demoLoanPortfolio(String walletId) {
    if (walletId != 'wallet-1') return null;
    final now = _nowSecs();
    const day = 86400;
    return {
      'version': 2,
      'site': 'Templar Protocol demo',
      'network': 'liquid-testnet',
      'tip_height': 2905000,
      'as_of': now,
      'wallet': {'label': 'Primary', 'escrow_fingerprint': 'deadbeef'},
      'loans': [
        {
          'id': 45,
          'ref': 'SQ-45',
          'role': 'borrower',
          'state': 'originating',
          'principal': {
            'ticker': 'USDT',
            'amount': '250',
            'asset': _usdtTestnet,
          },
          'collateral': {
            'ticker': 'LBTC',
            'amount': '0.006',
            'sats': 600000,
            'asset': _lbtcTestnet,
          },
          'opened_at': now - 1800,
          'pending_request': {
            'id': 'req-45',
            'action': 'origination',
            'link': 'templar://sign?url=https%3A%2F%2Fdemo.invalid%2Freq-45',
            'expires_at': now + day,
          },
        },
        {
          'id': 42,
          'ref': 'SQ-42',
          'role': 'borrower',
          'state': 'active',
          'principal': {
            'ticker': 'USDT',
            'amount': '600',
            'asset': _usdtTestnet,
          },
          'collateral': {
            'ticker': 'LBTC',
            'amount': '0.012',
            'sats': 1200000,
            'asset': _lbtcTestnet,
          },
          'interest': {'ticker': 'USDT', 'amount': '18', 'rate_bps': 300},
          'owed': {'ticker': 'USDT', 'amount': '412'},
          'opened_at': now - 12 * day,
          'due_at_estimate': now + 18 * day,
          'txids': {'origination': 'a1' * 32},
          'repayment_plan': {
            'kind': 'installments',
            'n_total': 6,
            'n_paid': 2,
            'm_missed': 0,
            'm_max': 2,
            'balance': {'ticker': 'USDT', 'amount': '412'},
            'regular_due': {'ticker': 'USDT', 'amount': '103'},
            'deadline_estimate': now + 4 * day,
          },
          'covenant': {
            'status': 'active',
            'current_txid': 'c3' * 32,
            'nodes': [
              {'index': 0, 'status': 'replaced', 'txid': 'a1' * 32},
              {
                'index': 1,
                'status': 'replaced',
                'txid': 'b2' * 32,
                'created_by': 'installment',
              },
              {
                'index': 2,
                'status': 'active',
                'txid': 'c3' * 32,
                'created_by': 'installment',
              },
            ],
          },
        },
        {
          'id': 37,
          'ref': 'SQ-37',
          'role': 'lender',
          'state': 'repaid',
          'principal': {
            'ticker': 'USDT',
            'amount': '300',
            'asset': _usdtTestnet,
          },
          'collateral': {
            'ticker': 'LBTC',
            'amount': '0.006',
            'sats': 600000,
            'asset': _lbtcTestnet,
          },
          'interest': {'ticker': 'USDT', 'amount': '6', 'rate_bps': 200},
          'opened_at': now - 41 * day,
          'txids': {'origination': 'd4' * 32, 'repayment': 'e5' * 32},
        },
      ],
      'offers': const [],
    };
  }

  @override
  Future<AtomicSwap> atomicSwapFund(String walletId, int offerId) async =>
      throw UnimplementedError('Atomic swaps require the native engine');
  @override
  Future<AtomicSwap> atomicSwapClaim(String walletId, int offerId) async =>
      throw UnimplementedError('Atomic swaps require the native engine');
  @override
  Future<AtomicSwap> atomicSwapRefund(String walletId, int offerId) async =>
      throw UnimplementedError('Atomic swaps require the native engine');

  // ── Peg (mock of the native peg and SideSwap) ──────────────────────────────
  //
  // The provider follows the mock network the way the engine's does: native
  // on a joined lab's regtest, SideSwap on testnet beside a joined lab, none
  // otherwise. Each status read moves a funded order one step, so a debug
  // session (or a test) walks the whole flow by refreshing.

  static const int _pegMinSats = 10000;
  static const int _pegOutMaxSats = 100000000;
  static const int _pegClaimFeeSats = 35;

  /// Reads after which an unfunded native peg-in expires (the federation
  /// changed). Null: never.
  int? mockPegExpireAfterReads;

  /// What the next reads report as `last_error` (a chain server down).
  String? mockPegChainError;

  final Map<String, Map<String, dynamic>> _pegOrders = {};

  String? get _pegProvider {
    if (_onLab) return 'native';
    if (_testServerProfile != null && _liquidNetwork == 'testnet') {
      return 'sideswap';
    }
    return null;
  }

  String get _pegUnavailable => _liquidNetwork == 'testnet'
      ? 'PEG_UNAVAILABLE: Liquid testnet has no parent chain, so it has no '
            'native peg-in / peg-out (a test server whose config names '
            'SideSwap for testnet enables its swap service).'
      : 'PEG_UNAVAILABLE: a plain regtest has no peg; join a test server.';

  String _requirePegProvider() {
    final p = _pegProvider;
    if (p == null) throw Exception('wallet-ffi: $_pegUnavailable');
    return p;
  }

  void _checkPegLimits(String direction, int amountSats, String provider) {
    if (amountSats < _pegMinSats) {
      throw Exception(
        'wallet-ffi: Amount is below the minimum of $_pegMinSats sats',
      );
    }
    if (provider == 'native' &&
        direction == 'out' &&
        amountSats > _pegOutMaxSats) {
      throw Exception(
        'wallet-ffi: Amount is above the maximum of $_pegOutMaxSats sats',
      );
    }
  }

  @override
  Future<PegQuote> pegQuote(String direction, int amountSats) async {
    await Future.delayed(const Duration(milliseconds: 250));
    final provider = _requirePegProvider();
    _checkPegLimits(direction, amountSats, provider);
    final native = provider == 'native';
    final serviceFee = native ? 0 : amountSats ~/ 100;
    final networkFee = native
        ? _pegClaimFeeSats
        : (direction == 'out' ? 300 : 0);
    final included = !native || direction == 'in';
    return PegQuote.fromJson({
      'direction': direction,
      'amount_sats': amountSats,
      'rate': 1.0,
      'service_fee_sats': serviceFee,
      'network_fee_sats': networkFee,
      'receive_sats': amountSats - serviceFee - (included ? networkFee : 0),
      'min_sats': _pegMinSats,
      'max_sats': native && direction == 'out'
          ? _pegOutMaxSats
          : 2100000000000000,
      'eta_minutes': direction == 'in' ? 21 : 12,
      'simulated': false,
      'provider': provider,
      'confirmations_required': 2,
      'network_fee_included': included,
    });
  }

  @override
  Future<PegOrder> pegStart(
    String walletId,
    String direction,
    int amountSats,
    String payoutAddress,
  ) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final quote = await pegQuote(direction, amountSats);
    final provider = quote.provider;
    final now = _nowSecs();
    final orderId = 'pg_${_hex8()}';
    final order = <String, dynamic>{
      'order_id': orderId,
      'wallet_id': walletId,
      'direction': direction,
      'status': 'awaiting_deposit',
      // A native peg-out has nothing to pay by hand: funding makes it.
      'deposit_address': direction == 'in'
          ? '2MwZFDfh4yR5ahSbq2mqgzhv77kPxPQELUY'
          : (provider == 'sideswap'
                ? 'tlq1qqmocksideswapdeposit00000000000000000000000000000000'
                : ''),
      'deposit_expected_sats': amountSats,
      'payout_address': payoutAddress,
      'payout_expected_sats': quote.receiveSats,
      'created_at': now,
      'updated_at': now,
      'eta_minutes': quote.etaMinutes,
      'txid_deposit': null,
      'txid_payout': null,
      'txid_claim': null,
      'simulated': false,
      'provider': provider,
      'confirmations': 0,
      'confirmations_required': 2,
      'deposit_received_sats': null,
      'valid_until_liquid_height': provider == 'native' && direction == 'in'
          ? 189
          : null,
      'last_error': null,
      'expires_at': provider == 'sideswap' ? now + 3600 : null,
      'status_history': <Map<String, dynamic>>[
        {'status': 'awaiting_deposit', 'at': now},
      ],
      '_reads': 0,
    };
    _pegOrders[orderId] = order;
    return PegOrder.fromJson(order);
  }

  void _pegEnter(Map<String, dynamic> order, String status) {
    final now = _nowSecs();
    order['status'] = status;
    order['updated_at'] = now;
    (order['status_history'] as List).cast<Map<String, dynamic>>().add({
      'status': status,
      'at': now,
    });
  }

  /// One status read: a funded order moves one step.
  void _advancePegOrder(Map<String, dynamic> order) {
    final status = order['status'] as String;
    if (const {
      'completed',
      'cancelled',
      'expired',
      'failed',
    }.contains(status)) {
      return;
    }
    order['last_error'] = mockPegChainError;
    if (mockPegChainError != null) return;
    final reads = (order['_reads'] as int? ?? 0) + 1;
    order['_reads'] = reads;
    final pegIn = order['direction'] == 'in';
    switch (status) {
      case 'awaiting_deposit':
        final limit = mockPegExpireAfterReads;
        if (pegIn && limit != null && reads >= limit) {
          _pegEnter(order, 'expired');
        }
      case 'deposit_seen':
        order['confirmations'] = 1;
        _pegEnter(order, 'confirming');
      case 'confirming':
        order['confirmations'] = 2;
        if (pegIn && order['provider'] == 'native') {
          _pegEnter(order, 'claimable');
        } else {
          _pegEnter(order, 'settling');
          if (!pegIn) {
            order['txid_payout'] = 'mock_pegout_payment_${order['order_id']}';
          }
        }
      case 'settling':
        _pegEnter(order, 'completed');
    }
  }

  Map<String, dynamic> _pegOrder(String orderId) {
    final order = _pegOrders[orderId];
    if (order == null) {
      throw Exception('wallet-ffi: Unknown peg order $orderId');
    }
    return order;
  }

  bool _demoPegsSeeded = false;

  // The demo orders' deposit addresses: clearly fake but well-formed.
  static const _pegInDepositAddr =
      'tb1qsimulatedpegdeposit0demo0nly00000000000';
  static const _pegOutDepositAddr =
      'tlq1qqsimulatedpegdeposit0demo0nly00000000000000000000000000000';

  /// Two orders for "Primary", once: a peg-in that completed five days ago
  /// and a peg-out under way (the simulated provider walks it to
  /// `completed` over the next minute, as it does any new order).
  void _seedDemoPegs() {
    if (_demoPegsSeeded) return;
    _demoPegsSeeded = true;
    final now = _nowSecs();
    final done = now - 5 * 86400;
    _pegOrders['pg_demo_in'] = <String, dynamic>{
      'order_id': 'pg_demo_in',
      'wallet_id': 'wallet-1',
      'direction': 'in',
      'status': 'completed',
      'deposit_address': _pegInDepositAddr,
      'deposit_expected_sats': 500000,
      'payout_address': 'tlq1qqdemopayout0000000000000000000000000000000000000',
      'payout_expected_sats': 499250,
      'created_at': done,
      'updated_at': done + 110,
      'eta_minutes': 2,
      'txid_deposit': 'f6' * 32,
      'txid_payout': '07' * 32,
      'simulated': true,
      'status_history': <Map<String, dynamic>>[
        {'status': 'awaiting_deposit', 'at': done},
        {'status': 'deposit_seen', 'at': done + 20},
        {'status': 'confirming', 'at': done + 50},
        {'status': 'settling', 'at': done + 80},
        {'status': 'completed', 'at': done + 110},
      ],
    };
    final started = now - 55;
    _pegOrders['pg_demo_out'] = <String, dynamic>{
      'order_id': 'pg_demo_out',
      'wallet_id': 'wallet-1',
      'direction': 'out',
      'status': 'awaiting_deposit',
      'deposit_address': _pegOutDepositAddr,
      'deposit_expected_sats': 200000,
      'payout_address': 'tb1qw508d6qejxtdg4y5r3zarvary0c5xw7kxpjzsx',
      'payout_expected_sats': 199550,
      'created_at': started,
      'updated_at': started,
      'eta_minutes': 2,
      'txid_deposit': null,
      'txid_payout': null,
      'simulated': true,
      'status_history': <Map<String, dynamic>>[
        {'status': 'awaiting_deposit', 'at': started},
      ],
    };
  }

  @override
  Future<PegOrder> pegStatus(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final order = _pegOrder(orderId);
    _advancePegOrder(order);
    return PegOrder.fromJson(order);
  }

  @override
  Future<List<PegOrder>> pegList(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (walletId == 'wallet-1') _seedDemoPegs();
    final orders =
        _pegOrders.values.where((o) => o['wallet_id'] == walletId).toList()
          ..sort(
            (a, b) =>
                (b['created_at'] as int).compareTo(a['created_at'] as int),
          );
    for (final o in orders) {
      _advancePegOrder(o);
    }
    return orders.map(PegOrder.fromJson).toList();
  }

  @override
  Future<PegOrder> pegCancel(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final order = _pegOrder(orderId);
    if (order['status'] != 'awaiting_deposit') {
      throw Exception(
        'wallet-ffi: Order can no longer be cancelled (status: '
        '${order['status']})',
      );
    }
    _pegEnter(order, 'cancelled');
    return PegOrder.fromJson(order);
  }

  @override
  Future<PegOrder> pegFund(String orderId, {double? feeRate}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final order = _pegOrder(orderId);
    if (order['status'] == 'expired') {
      throw Exception('wallet-ffi: PEG_EXPIRED: the deposit address expired.');
    }
    if (order['status'] != 'awaiting_deposit') {
      throw Exception(
        'wallet-ffi: PEG_NOT_READY: the order is ${order['status']}.',
      );
    }
    final amount = order['deposit_expected_sats'] as int;
    final pegIn = order['direction'] == 'in';
    final chain = _onLab
        ? (pegIn ? 'Bitcoin regtest' : 'Liquid regtest')
        : (pegIn ? 'Bitcoin testnet' : 'Liquid testnet');
    // The mock wallet holds about 0.5 BTC (none at all while
    // [mockPegWalletEmpty]): a larger deposit cannot be built.
    final has = mockPegWalletEmpty ? 0 : 50000000;
    if (amount + 43 > has) {
      throw Exception(
        'wallet-ffi: PEG_INSUFFICIENT_FUNDS: this wallet has $has sat of '
        '${pegIn ? 'BTC' : 'L-BTC'} on $chain; the '
        '${pegIn ? 'deposit and its fee need' : 'peg-out and its fee need at least'} '
        '${amount + 43} sat.',
      );
    }
    order['txid_deposit'] = 'mock_peg_deposit_${order['order_id']}';
    order['deposit_received_sats'] = amount;
    _pegEnter(order, 'deposit_seen');
    return PegOrder.fromJson(order);
  }

  @override
  Future<PegOrder> pegClaim(String orderId) async {
    await Future.delayed(const Duration(milliseconds: 600));
    final order = _pegOrder(orderId);
    if (order['provider'] != 'native' || order['direction'] != 'in') {
      throw Exception(
        'wallet-ffi: PEG_UNAVAILABLE: only a native peg-in is claimed.',
      );
    }
    if (order['status'] != 'claimable') {
      throw Exception(
        'wallet-ffi: PEG_NOT_READY: the deposit has '
        '${order['confirmations']} of the 2 Bitcoin confirmations a claim '
        'needs.',
      );
    }
    order['txid_claim'] = 'mock_peg_claim_${order['order_id']}';
    order['txid_payout'] = order['txid_claim'];
    _pegEnter(order, 'settling');
    return PegOrder.fromJson(order);
  }

  @override
  Future<ReregisterResult> reregisterAsset({
    required String walletId,
    required String assetId,
    required String name,
    required String ticker,
    required int precision,
    String? domain,
  }) async {
    await Future.delayed(const Duration(seconds: 1));
    final bookError = mockBookRegisterError;
    return ReregisterResult(
      registered: false,
      bookRegistered: bookError == null,
      bookError: bookError,
    );
  }

  @override
  Future<List<HwDevice>> enumerateHwDevices() async {
    await Future.delayed(const Duration(seconds: 2));
    return [
      const HwDevice(
        model: 'Ledger Nano S',
        fingerprint: 'deadbeef',
        path: 'hid:/0001:0002:00',
      ),
    ];
  }

  @override
  Future<List<String>> jadePorts() async => const ['/dev/cu.usbserial-mock'];

  @override
  Future<WalletSummary> importJadeLiquidWallet(String name) async {
    await Future.delayed(const Duration(seconds: 2));
    return WalletSummary(
      id: 'mock-jade-liquid-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: WalletType.watchOnly,
      network: WalletNetwork.testnet,
      balanceSats: 0,
      txCount: 0,
      lastSyncAt: DateTime.now(),
      isWatchOnly: true,
      typeLabel: 'Hardware (deadbeef)',
      liquidEnabled: true,
    );
  }

  @override
  Future<List<NativeDevice>> enumerateNativeDevices() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return const [
      NativeDevice(
        family: 'ledger',
        model: 'Nano S Plus',
        transport: 'hid',
        path: 'hid:/0001:0002:00',
        vendorId: 0x2c97,
        productId: 0x5011,
      ),
    ];
  }

  @override
  Future<HwImportResult> importHwWallet(
    String name,
    String fingerprint, {
    bool liquid = false,
  }) async {
    await Future.delayed(const Duration(seconds: 2));
    final wallet = WalletSummary(
      id: 'hw_${fingerprint.substring(0, 6)}',
      name: name,
      type: WalletType.watchOnly,
      network: WalletNetwork.testnet,
      balanceSats: 0,
      txCount: 0,
      lastSyncAt: DateTime.now(),
      isWatchOnly: true,
      typeLabel: 'Hardware ($fingerprint)',
      liquidEnabled: liquid,
      deviceModel: 'Blockstream Jade',
    );
    return HwImportResult(
      wallet: wallet,
      fingerprint: fingerprint,
      deviceModel: 'Blockstream Jade',
      bitcoinDescriptor:
          "wpkh([$fingerprint/84'/1'/0']tpubDMockReceiveDescriptorForUiWork/0/*)",
      liquidDescriptor: liquid
          ? 'ct(slip77(mock),elwpkh([$fingerprint/84h/1h/0h]tpubDMock/<0;1>/*))'
          : null,
      liquidRequested: liquid,
    );
  }

  @override
  Future<WalletSummary> addLiquidToWallet(String walletId) async {
    await Future.delayed(const Duration(seconds: 1));
    return WalletSummary(
      id: walletId,
      name: 'Mock hardware wallet',
      type: WalletType.watchOnly,
      network: WalletNetwork.testnet,
      balanceSats: 0,
      txCount: 0,
      lastSyncAt: DateTime.now(),
      isWatchOnly: true,
      typeLabel: 'Hardware (deadbeef)',
      liquidEnabled: true,
      deviceModel: 'Blockstream Jade',
    );
  }

  @override
  Future<WalletSummary> createWatchOnlyWallet(
    String name,
    String recvDesc,
    String changeDesc, {
    String? liquidCtDescriptor,
    bool airgap = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final liquid =
        liquidCtDescriptor != null && liquidCtDescriptor.trim().isNotEmpty;
    return WalletSummary(
      id: 'watch_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: WalletType.watchOnly,
      network: WalletNetwork.testnet,
      balanceSats: 0,
      txCount: 0,
      lastSyncAt: DateTime.now(),
      isWatchOnly: true,
      typeLabel: airgap ? 'Air-gap watch-only' : 'Watch-only',
      liquidEnabled: liquid,
    );
  }

  @override
  Future<WalletSummary> createMultisigWallet({
    required String name,
    required int requiredSigs,
    required int totalSigners,
    required List<String> cosignerXpubs,
    String? localMnemonic,
    List<String>? localMnemonics,
    List<String> liquidXpubs = const [],
    int? liquidCapableKeys,
  }) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return WalletSummary(
      id: 'ms_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      type: WalletType.multisig,
      network: WalletNetwork.testnet,
      balanceSats: 0,
      txCount: 0,
      lastSyncAt: DateTime.now(),
      typeLabel: 'Multisig $requiredSigs-of-$totalSigners',
      liquidEnabled: liquidXpubs.isNotEmpty,
    );
  }

  @override
  Future<String> getHwCosignerXpub(String fingerprint) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return "[$fingerprint/48'/1'/0'/2']tpubDMockHw${fingerprint.hashCode.toRadixString(16)}";
  }

  @override
  Future<String> getJadeLiquidCosignerXpub({String? expectFingerprint}) async {
    await Future.delayed(const Duration(milliseconds: 400));
    final fp = expectFingerprint?.isNotEmpty == true
        ? expectFingerprint!
        : 'jade0000';
    return "[$fp/87'/1'/0']tpubDMockJadeLiquid${fp.hashCode.toRadixString(16)}";
  }

  @override
  Future<String> deriveLiquidDescriptor(String btcDescriptor) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final key = btcDescriptor.contains('(')
        ? btcDescriptor.substring(
            btcDescriptor.indexOf('(') + 1,
            btcDescriptor.lastIndexOf(')'),
          )
        : "[00000000/84'/1'/0']$btcDescriptor/<0;1>/*";
    return 'ct(elip151,wpkh($key))';
  }

  @override
  Future<HwiStatus> hwiStatus() async => const HwiStatus(
    resolvedBin: '/mock/data/hwi/hwi',
    version: '3.2.0',
    platform: 'mock',
    udevRulesInstalled: null,
  );

  @override
  Future<void> setHwiPath(String path) async {}

  @override
  Future<String> getDataDir() async => '/mock/data';

  @override
  Future<String> getVersion() async => '0.0.0-mock';

  @override
  Future<String> deriveCosignerXpub(List<String> mnemonic) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final tag = mnemonic.first.substring(0, 2);
    return "[${tag}adbeef/48'/1'/0'/2']tpubDMock${mnemonic.hashCode.toRadixString(16)}";
  }

  @override
  Future<String> getCosignerXpub(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return "[cafebabe/48'/1'/0'/2']tpubDMockFromWallet$walletId";
  }

  @override
  Future<String> deriveLiquidCosignerXpub(List<String> mnemonic) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return "[${mnemonic.join().hashCode.toRadixString(16).padLeft(8, '0')}"
        "/87'/1'/0']tpubDMockLiquidCosigner";
  }

  @override
  Future<String> getLiquidCosignerXpub(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return "[cafebabe/87'/1'/0']tpubDMockLiquidFromWallet$walletId";
  }

  @override
  Future<WalletSummary> repairMultisigWallet(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 120));
    throw Exception('wallet-ffi: "$walletId" has nothing to repair.');
  }

  /// Mirrors the engine closely enough for the wizard's field states to be
  /// exercised without the dylib: reduces a scanned descriptor to its key,
  /// refuses a key with no origin, warns on a singlesig account path.
  @override
  Future<CosignerKeyInfo> validateCosignerKey(
    String key, {
    bool liquid = false,
  }) async {
    await Future.delayed(const Duration(milliseconds: 60));
    final compact = key.replaceAll(RegExp(r'\s'), '').split('#').first;
    final open = compact.indexOf('[');
    final close = compact.indexOf(']');
    if (open < 0 || close < open + 2) {
      throw Exception(
        'wallet-ffi: This key has no origin. A cosigner key must '
        'carry the fingerprint and the path it was derived at.',
      );
    }
    final origin = compact.substring(open + 1, close);
    final marker = liquid ? 'h' : "'";
    final parts = origin.split('/');
    final fingerprint = parts.first.toLowerCase();
    final path = parts
        .skip(1)
        .map((p) => p.replaceAll(RegExp("[hH']"), marker))
        .join('/');
    final tail = compact.substring(close + 1).split('(').last;
    final xpub = RegExp(r'^[1-9A-HJ-NP-Za-km-z]+').stringMatch(tail) ?? '';
    final expected = liquid ? '87h/1h/0h' : "48'/1'/0'/2'";
    return CosignerKeyInfo(
      normalized: '[$fingerprint/$path]$xpub',
      fingerprint: fingerprint,
      path: path,
      warning: path == expected
          ? null
          : 'm/$path is not the usual cosigner path (m/$expected).',
    );
  }

  @override
  Future<List<String>> getMnemonic(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return const [
      'abandon',
      'ability',
      'able',
      'about',
      'above',
      'absent',
      'absorb',
      'abstract',
      'absurd',
      'abuse',
      'access',
      'accident',
    ];
  }

  @override
  Future<String> getPrivateKey(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    // Fake testnet master xprv so the reveal UI works in mock mode.
    return 'tprv8ZgxMBicQKsPeMockRootKeyForUiTesting'
        '$walletId'
        'aXyZ1234567890abcdefGHIJKLMNOPqrstuvwxyz';
  }

  @override
  Future<PsbtInspection> inspectPsbt(String psbtBase64) async {
    await Future.delayed(const Duration(milliseconds: 400));
    // Count the signatures the blob actually carries, so a copy coming back
    // from a co-signer reads as one more signature than the copy that went
    // out — the whole point of the chart on the co-signature sheet.
    const fingerprints = ['deadbeef', 'cafebabe'];
    final signed = _mockSigMarker
        .allMatches(psbtBase64)
        .length
        .clamp(0, fingerprints.length);
    if (psbtBase64.contains(_mockBumpMarker)) {
      return _mockBumpInspection(psbtBase64, signed);
    }
    // The shape a current engine answers with a wallet open: every input
    // priced and owned, the recipient not ours, the change ours — so the
    // co-sign screen's ownership banner and its YOURS chips are exercised on
    // fake data too.
    return PsbtInspection(
      inputs: const [
        PsbtInput(
          outpoint: 'abcdef1234:0',
          amountSats: 1234567,
          displayAmount: '0.01234567 BTC',
          utxoStatus: PsbtUtxoStatus.ok,
          isMine: true,
        ),
      ],
      outputs: const [
        PsbtOutput(
          address: 'tb1qmockrecipient…',
          amountSats: 100000,
          displayAmount: '100000 sats',
          isMine: false,
        ),
        PsbtOutput(
          address: 'tb1qmockchange…',
          amountSats: 1133007,
          displayAmount: '0.01133007 BTC',
          isMine: true,
        ),
      ],
      feeSats: 1560,
      feeDisplay: '1560 sats',
      sigsPresent: signed,
      sigsRequired: 2,
      signers: [
        for (var i = 0; i < fingerprints.length; i++)
          PsbtSigner(fingerprint: fingerprints[i], hasSigned: i < signed),
      ],
      policyHint: '2-of-2 multisig',
      rawPsbt: psbtBase64,
      finalized: false,
      utxoCheck: PsbtUtxoStatus.ok,
      ownershipKnown: true,
    );
  }

  @override
  Future<String> signPsbt(String walletId, String psbtBase64) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return '$psbtBase64$_mockSigMarker';
  }

  @override
  Future<String> sendTransactionHw({
    required String walletId,
    required List<TxOutputSpec> outputs,
    required String assetId,
    required double feeRate,
    List<String>? utxos,
  }) async {
    await Future.delayed(const Duration(seconds: 3));
    return 'mock_hw_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<String> signPsbtHw(String fingerprint, String psbtBase64) async {
    await Future.delayed(const Duration(seconds: 2));
    return psbtBase64;
  }

  @override
  Future<String> combinePsbts(List<String> psbtsBase64) async {
    if (psbtsBase64.length < 2) {
      throw Exception('wallet-ffi: Combining needs at least two copies');
    }
    // Mock PSBTs carry no real signatures: the longest copy stands in for
    // the merged one.
    return psbtsBase64.reduce((a, b) => b.length > a.length ? b : a);
  }

  @override
  Future<PsetInspection> inspectPset(String walletId, String psetBase64) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return PsetInspection(
      feeSats: 250,
      feeDisplay: '250 sats',
      recipients: const [
        PsetRecipient(
          address: 'tlq1qqmockrecipient…',
          assetId:
              '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49',
          ticker: 'LBTC',
          amountSats: 100000,
          displayAmount: '0.00100000 LBTC',
        ),
      ],
      sigsHave: 1,
      sigsNeeded: 2,
      signersPresent: const ['cafebabe'],
      signersMissing: const ['deadbeef'],
      canFinalize: false,
      rawPset: psetBase64,
    );
  }

  @override
  Future<String> signPset(String walletId, String psetBase64) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return psetBase64;
  }

  @override
  Future<String> signPsetHw(String walletId, String psetBase64) async {
    await Future.delayed(const Duration(seconds: 2));
    return psetBase64;
  }

  @override
  Future<String> combinePsets(String walletId, List<String> psetsBase64) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return psetsBase64.first;
  }

  @override
  Future<String> broadcastPset(String walletId, String psetBase64) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return 'mock_liquid_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<String> signTransactionHw({
    required String walletId,
    required List<TxOutputSpec> outputs,
    required String assetId,
    required double feeRate,
    List<String>? utxos,
  }) async {
    await Future.delayed(const Duration(seconds: 3));
    return 'cHNidP8BAHUCAAAAASaBcTce3/KF6Tet7qSze3gADAVmy7OtZGQXE8pn/xMAAAAAAAD+////AtPf9QUAAAAAGXapFNDFmQPFusKGh2DpD9UhpGZap2UgiKwA8gUqAQAAACJRIGDYV0EaKVNO0V02YSEVfx7T/9lJAAAAAA==MOCKSIGNED';
  }

  @override
  Future<String> buildUnsignedPsbt({
    required String walletId,
    required List<TxOutputSpec> outputs,
    required double feeRate,
    String assetId = 'BTC',
    List<String>? utxos,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return 'cHNidP8BAHUCAAAAASaBcTce3/KF6Tet7qSze3gADAVmy7OtZGQXE8pn/xMAAAAAAAD+////AtPf9QUAAAAAGXapFNDFmQPFusKGh2DpD9UhpGZap2UgiKwA8gUqAQAAACJRIGDYV0EaKVNO0V02YSEVfx7T/9lJAAAAAA==MOCK';
  }

  @override
  Future<String> broadcastSignedPsbt({
    required String walletId,
    required String psbtBase64,
  }) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return 'mock_airgap_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<String> verifyHwAddress(String walletId) async {
    await Future.delayed(const Duration(seconds: 2));
    // What a device answers: the wallet's current receive address.
    return (await generateReceiveAddress(walletId, 'BTC')).address;
  }

  @override
  Future<String> consolidateUtxos({
    required String walletId,
    required List<String> outpoints,
    required String chain,
    required double feeRate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));
    return 'mock_consolidate_txid_${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> renameWallet(String walletId, String newName) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<void> deleteWallet(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  @override
  Future<String> buildConsolidationPsbt({
    required String walletId,
    required List<String> outpoints,
    required String chain,
    required double feeRate,
  }) async {
    await Future.delayed(const Duration(milliseconds: 400));
    return 'cHNidP8BAHECAAAAAWNvbnNvbGlkYXRlbW9jaw==';
  }

  @override
  Future<void> enableLiquid(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }

  // ── Vault (C1) — in-memory only; no real encryption in mock mode ────────────
  bool _vaultInitialized = false;
  bool _vaultUnlocked = false;

  String _liquidNetwork = 'testnet';
  String _liquidPolicyAsset =
      '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';

  LiquidNetworkInfo _liquidNetworkInfo() => LiquidNetworkInfo(
    network: 'liquid-$_liquidNetwork',
    shortName: _liquidNetwork,
    policyAsset: _liquidPolicyAsset,
    backend: _onLab || _liquidNetwork != 'regtest'
        ? 'electrum'
        : 'elements_rpc',
    backendDescription: _liquidBackendDescription(),
    regtestDefaultPolicyAsset:
        '5ac9f65c0efcc4775e0baec4ec03abdde22473cd3cf33c0419ca290e0751b225',
    backendSource: _onLab ? 'profile' : 'default',
    testServer: _testServerProfile?.baseUrl,
    pegProvider: _pegProvider,
    pegUnavailableReason: _pegProvider == null ? _pegUnavailable : null,
  );

  String _liquidBackendDescription() {
    if (_liquidNetwork != 'regtest') {
      return 'electrum ssl://elements-testnet.blockstream.info:50002';
    }
    final lab = _testServerProfile;
    return lab != null
        ? 'electrum ${lab.regtest.liquidElectrumUrl}'
        : 'elements-rpc http://127.0.0.1:18884';
  }

  // ── Test server — in memory; no network ─────────────────────────────────────

  /// What the next live check of a joined server reports. Debug and test
  /// knobs: a mock session can show the unreachable and the stale state.
  bool mockTestServerReachable = true;
  bool mockTestServerStale = false;

  TestServerProfile? _testServerProfile;

  /// Liquid runs on the joined lab's regtest — and so does Bitcoin.
  bool get _onLab => _testServerProfile != null && _liquidNetwork == 'regtest';

  static const _labPolicyAsset =
      'b2e15d0d7a0c94e4e2ce0fe6e8691b9e451377f6e46e8045a86f7c4b5d4f0f23';

  TestServerProfile _mockProfile(String baseUrl) => TestServerProfile(
    baseUrl: baseUrl,
    name: 'Mock testlab',
    version: 1,
    fetchedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    orderbookUrl: 'http://127.0.0.1:3210',
    regtest: const TestServerRegtest(
      instanceId: 'mock0001',
      policyAsset: _labPolicyAsset,
      genesisHash:
          '00902a6b70c2ca83b5d9c815d96a0e2f4202179316970d14ea1847dae5b1ca21',
      liquidElectrumUrl: 'tcp://127.0.0.1:19061',
      bitcoinNetwork: 'regtest',
      bitcoinElectrumUrl: 'tcp://127.0.0.1:19060',
      bitcoinEsploraUrl: 'http://127.0.0.1:19070',
      faucetUrl: 'http://127.0.0.1:8096/api/faucet',
      peg: TestServerPeg(provider: 'native'),
      faucet: mockFaucetAssets,
    ),
    protocolUrl: 'http://127.0.0.1:8098',
  );

  /// What the mock lab's faucet pays: BTC, its L-BTC and a lab USDt.
  static const List<FaucetAsset> mockFaucetAssets = [
    FaucetAsset(
      asset: 'btc',
      network: 'bitcoin-regtest',
      ticker: 'BTC',
      name: 'Bitcoin (regtest)',
      precision: 8,
      defaultSat: 1000000,
      maxSat: 10000000,
    ),
    FaucetAsset(
      asset: 'lbtc',
      network: 'liquid-regtest',
      ticker: 'LBTC',
      name: 'Liquid Bitcoin',
      precision: 8,
      assetId: _labPolicyAsset,
      defaultSat: 1000000,
      maxSat: 10000000,
    ),
    FaucetAsset(
      asset: 'USDt',
      network: 'liquid-regtest',
      ticker: 'USDt',
      name: 'Tether USD (test)',
      precision: 8,
      assetId: mockLabUsdtId,
      defaultSat: 10000000000,
      maxSat: 100000000000,
    ),
  ];

  static const String mockLabUsdtId =
      '74e90b06d984b77ef6651a82814f054282c13b424a008a87f97060635f45ce7d';

  /// The next faucet requests fail with this engine error (e.g.
  /// `FAUCET_RATE_LIMITED: … Try again in 90 seconds.`); null = they pay.
  String? mockFaucetError;

  /// The wallet has no coins for a peg deposit (until the faucet pays BTC).
  bool mockPegWalletEmpty = false;

  /// Every faucet request answered so far (tests).
  final List<String> faucetRequests = [];

  @override
  Future<FaucetPayment> testServerFaucet(String walletId, String asset) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final lab = _testServerProfile;
    if (lab == null || !_onLab) {
      throw Exception(
        'wallet-ffi: FAUCET_UNAVAILABLE: no test server is joined, or the '
        'wallet is not on its regtest.',
      );
    }
    final err = mockFaucetError;
    if (err != null) throw Exception('wallet-ffi: $err');
    final coin = lab.regtest.faucet.firstWhere(
      (a) =>
          a.asset.toLowerCase() == asset.toLowerCase() ||
          a.ticker.toLowerCase() == asset.toLowerCase(),
      orElse: () => throw Exception(
        'wallet-ffi: FAUCET_UNAVAILABLE: the lab\'s faucet does not pay '
        '"$asset"; it pays BTC, LBTC, USDt.',
      ),
    );
    faucetRequests.add(coin.asset);
    if (coin.isBitcoin) mockPegWalletEmpty = false;
    return FaucetPayment(
      txid: 'mock_faucet_${coin.asset}_${faucetRequests.length}',
      asset: coin.asset,
      network: coin.network,
      amountSat: coin.defaultSat ?? 100000,
      address: coin.isBitcoin
          ? 'bcrt1qmockfaucet0000000000000000000000000000'
          : 'el1qqmockfaucet00000000000000000000000000000000',
      ticker: coin.ticker,
      precision: coin.precision,
      assetId: coin.assetId,
    );
  }

  TestServerInfo _testServerInfo({
    TestServerCheck? check,
    TestServerApplied? applied,
  }) {
    final lab = _testServerProfile;
    final bookSource = lab != null ? 'profile' : 'default';
    final origin = lab?.orderbookUrl ?? 'http://127.0.0.1:3210';
    SourcedUrl route(String path) =>
        SourcedUrl(url: '$origin$path', source: bookSource);
    return TestServerInfo(
      configured: lab != null,
      profile: lab,
      check: check,
      applied: applied,
      active: ActiveEndpoints(
        liquidNetwork: 'liquid-$_liquidNetwork',
        envLocked: false,
        orderbook: OrderbookEndpoints(
          origin: SourcedUrl(url: origin, source: bookSource),
          book: route('/api/book'),
          markets: route('/api/markets'),
          publish: route('/api/offers'),
          atomicSwaps: route('/api/atomic-swaps'),
          assets: route('/api/assets'),
        ),
        liquid: LiquidEndpoint(
          network: 'liquid-$_liquidNetwork',
          policyAsset: _liquidPolicyAsset,
          genesisHash: _onLab ? lab!.regtest.genesisHash : null,
          paramsSource: _onLab ? 'profile' : 'default',
          backend: _onLab || _liquidNetwork != 'regtest'
              ? 'electrum'
              : 'elements_rpc',
          backendDescription: _liquidBackendDescription(),
          backendSource: _onLab ? 'profile' : 'default',
        ),
        bitcoin: _onLab
            ? BitcoinEndpoint(
                network: 'bitcoin-regtest',
                electrumUrl: lab!.regtest.bitcoinElectrumUrl,
                source: 'profile',
              )
            : const BitcoinEndpoint(
                network: 'bitcoin-testnet',
                electrumUrl: 'ssl://electrum.blockstream.info:60002',
                source: 'default',
              ),
        protocol: _onLab && lab!.protocolUrl != null
            ? SourcedUrl(url: lab.protocolUrl!, source: 'profile')
            : null,
      ),
      faucet: lab == null
          ? null
          : TestServerFaucet(
              url: lab.regtest.faucetUrl,
              assetsSource: 'profile',
              assets: lab.regtest.faucet,
              available: _onLab,
            ),
    );
  }

  @override
  Future<TestServerInfo> getTestServer({bool check = false}) async {
    final lab = _testServerProfile;
    if (!check || lab == null) return _testServerInfo();
    await Future.delayed(const Duration(milliseconds: 200));
    return _testServerInfo(
      check: mockTestServerReachable
          ? TestServerCheck(
              reachable: true,
              stale: mockTestServerStale,
              serverInstanceId: mockTestServerStale
                  ? 'mock0002'
                  : lab.regtest.instanceId,
            )
          : const TestServerCheck(
              reachable: false,
              stale: false,
              error: 'Cannot reach the test server: connection refused',
            ),
    );
  }

  @override
  Future<TestServerInfo> setTestServer(String url) async {
    await Future.delayed(const Duration(milliseconds: 300));
    var base = url.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw Exception(
        'wallet-ffi: Invalid test server URL: $url (expected http(s)://host[:port])',
      );
    }
    // `.invalid` never resolves (RFC 2606): the mock's unreachable server.
    if (uri.host.endsWith('.invalid')) {
      throw Exception(
        'wallet-ffi: Cannot reach the test server: ${uri.host}: '
        'connection refused',
      );
    }
    final switched = _liquidNetwork != 'regtest';
    _testServerProfile = _mockProfile(base);
    _liquidNetwork = 'regtest';
    _liquidPolicyAsset = _labPolicyAsset;
    final wasStale = mockTestServerStale;
    mockTestServerStale = false;
    return _testServerInfo(
      check: TestServerCheck(
        reachable: true,
        stale: false,
        serverInstanceId: _testServerProfile!.regtest.instanceId,
      ),
      applied: TestServerApplied(
        liquidNetwork: 'liquid-regtest',
        networkSwitched: switched,
        walletClosed: true,
        regtestCacheReset: wasStale,
      ),
    );
  }

  @override
  Future<TestServerInfo> clearTestServer() async {
    await Future.delayed(const Duration(milliseconds: 200));
    final wasOnLab = _onLab;
    _testServerProfile = null;
    mockTestServerStale = false;
    if (wasOnLab) {
      _liquidNetwork = 'testnet';
      _liquidPolicyAsset =
          '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';
    }
    return _testServerInfo(
      applied: TestServerApplied(
        liquidNetwork: 'liquid-$_liquidNetwork',
        networkSwitched: wasOnLab,
        walletClosed: true,
        regtestCacheReset: wasOnLab,
      ),
    );
  }

  @override
  Future<LiquidNetworkInfo> getLiquidNetwork() async => _liquidNetworkInfo();

  @override
  Future<LiquidNetworkInfo> setLiquidNetwork(
    String network, {
    String? policyAsset,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final name = network.replaceFirst('liquid-', '');
    if (name != 'testnet' && name != 'regtest') {
      throw Exception('wallet-ffi: unknown Liquid network "$network"');
    }
    final lab = _testServerProfile;
    if (name == 'regtest' &&
        lab != null &&
        (policyAsset ?? '').trim().isNotEmpty &&
        policyAsset!.trim().toLowerCase() != lab.regtest.policyAsset) {
      throw Exception(
        'wallet-ffi: Liquid regtest is the test server\'s '
        '(${lab.regtest.policyAsset}). Clear the test server to use another '
        'regtest.',
      );
    }
    _liquidNetwork = name;
    if (name == 'regtest' && lab != null) {
      _liquidPolicyAsset = lab.regtest.policyAsset;
      return _liquidNetworkInfo();
    }
    _liquidPolicyAsset = name == 'regtest'
        ? ((policyAsset ?? '').trim().isEmpty
              ? '5ac9f65c0efcc4775e0baec4ec03abdde22473cd3cf33c0419ca290e0751b225'
              : policyAsset!.trim())
        : '144c654344aa716d6f3abcc1ca90e5641e4e2a7f633bc09fe3baf64585819a49';
    return _liquidNetworkInfo();
  }

  @override
  Future<String> getProtocolEscrowXpub(String walletId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return '[deadbeef/2121h/1h/0h]tpubDCMockEscrowKey1111111111111111111111111111111111111111111111111111111111111111111111111111111111111';
  }

  @override
  Future<ProtocolCheck> protocolCheckPset(
    String walletId,
    String challenge,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    return ProtocolCheck(
      psetBase64: 'cHNldP8BAgQCAAAAMOCK${base64Encode(utf8.encode(challenge))}',
      loanKey: await getProtocolEscrowXpub(walletId),
      fingerprint: 'deadbeef',
    );
  }

  @override
  Future<ProtocolCheckVerdict> protocolIsCheckPset(
    String walletId,
    String challenge,
    String psetBase64,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    // The mock has no key to recompute with: a PSET it built itself for the
    // same challenge is the check, anything else is not.
    final expected = (await protocolCheckPset(walletId, challenge)).psetBase64;
    return psetBase64.trim() == expected
        ? const ProtocolCheckVerdict(
            isCheck: true,
            loanKeyFingerprint: 'deadbeef',
          )
        : const ProtocolCheckVerdict(
            isCheck: false,
            reason:
                'not a check PSET: the mock bridge recognises only the '
                'check it built for this challenge',
            loanKeyFingerprint: 'deadbeef',
          );
  }

  @override
  Future<VaultStatus> vaultStatus() async =>
      VaultStatus(initialized: _vaultInitialized, unlocked: _vaultUnlocked);

  /// Stand-in for the engine's vault key: 32 random bytes as hex, fresh on
  /// every [setupVault] so a re-created vault rejects an old exported key the
  /// same way the real engine does ("does not match").
  String _vaultKeyHex = '';

  static String _randomKeyHex() {
    final rnd = math.Random.secure();
    final sb = StringBuffer();
    for (var i = 0; i < 32; i++) {
      sb.write(rnd.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  @override
  Future<void> setupVault(String passphrase) async {
    _vaultInitialized = true;
    _vaultUnlocked = true;
    _vaultKeyHex = _randomKeyHex();
  }

  @override
  Future<void> unlockVault(String passphrase) async {
    _vaultUnlocked = true;
  }

  @override
  Future<void> lockVault() async {
    _vaultUnlocked = false;
  }

  @override
  Future<String> exportVaultKey() async {
    if (!_vaultInitialized) throw Exception('wallet-ffi: no vault is set up');
    if (!_vaultUnlocked) throw Exception('wallet-ffi: vault is locked');
    return _vaultKeyHex;
  }

  @override
  Future<void> unlockVaultWithKey(String keyHex) async {
    if (!_vaultInitialized) throw Exception('wallet-ffi: no vault is set up');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(keyHex)) {
      throw Exception('wallet-ffi: invalid key: expected 64 hex characters');
    }
    if (keyHex.toLowerCase() != _vaultKeyHex) {
      throw Exception('wallet-ffi: key does not match this vault');
    }
    _vaultUnlocked = true;
  }

  @override
  Future<void> verifyVaultPassphrase(String passphrase) async {
    if (passphrase.isEmpty) throw Exception('Wrong app password');
  }

  @override
  Future<void> verifyVaultKey(String keyHex) async {
    if (!_vaultInitialized) throw Exception('wallet-ffi: no vault is set up');
    if (keyHex.length != 64) {
      throw Exception('wallet-ffi: Vault key must be 64 hex characters');
    }
    if (keyHex.toLowerCase() != _vaultKeyHex) {
      throw Exception('wallet-ffi: key does not match this vault');
    }
  }

  @override
  Future<BackupVerification> verifyBackup(
    String walletId,
    String mnemonic,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final matched = mnemonic.trim().split(RegExp(r'\s+')).length >= 12;
    return BackupVerification(
      matched: matched,
      reason: matched ? 'ok' : 'checksum',
      derivedFingerprint: matched ? 'f0b68896' : '',
      expectedFingerprint: 'f0b68896',
      fingerprintMatch: matched,
    );
  }

  @override
  Future<List<String>> urPsbtEncode(
    String psbtBase64, {
    int maxFragmentLen = 100,
  }) async {
    await Future.delayed(const Duration(milliseconds: 80));
    return ['ur:crypto-psbt/mock-part-1', 'ur:crypto-psbt/mock-part-2'];
  }

  @override
  Future<List<String>> urPsetEncode(
    String psetBase64, {
    int maxFragmentLen = 100,
  }) async {
    await Future.delayed(const Duration(milliseconds: 80));
    return ['ur:bytes/mock-part-1', 'ur:bytes/mock-part-2'];
  }

  @override
  Future<UrDecodeResult> urDecodeParts(List<String> parts) async {
    await Future.delayed(const Duration(milliseconds: 80));
    return const UrDecodeResult(
      progress: 1.0,
      complete: true,
      kind: 'psbt',
      psbtBase64: 'cHNidP8BAAoCAAAAAAAAAAAAAAAA',
    );
  }
}
