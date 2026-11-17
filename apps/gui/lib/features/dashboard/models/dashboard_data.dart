class AssetBalance {
  const AssetBalance({
    required this.assetId,
    required this.ticker,
    required this.name,
    required this.amount,
    required this.displayAmount,
    this.fiatEstimate,
    this.status = 'synced',
    this.utxoCount = 0,
    this.isNative = false,
    this.precision,
    this.metadataSource = 'wallet',
    this.bookSource,
  });

  final String assetId;
  final String ticker;
  final String name;
  final int amount;
  final String displayAmount;
  final String? fiatEstimate;
  final String status;
  final int utxoCount;
  final bool isNative;

  /// Decimals of the display unit, when the engine knows them (null from an
  /// older engine): what an amount of this asset is typed in.
  final int? precision;

  /// Who named it: `wallet` | `book` | `feed` | `none` (see
  /// `shared/asset_naming.dart`).
  final String metadataSource;

  /// The book's own provenance of a `book` name: `admin` | `contract` |
  /// `other`.
  final String? bookSource;
}

class RecentActivityItem {
  const RecentActivityItem({
    required this.txid,
    required this.direction,
    required this.chain,
    required this.amount,
    required this.ticker,
    required this.timestamp,
    required this.confirmations,
    this.note,
    this.counterparty,
  });

  final String txid;
  final String direction;

  /// "bitcoin" | "liquid" — Home groups activity per chain, and a token's
  /// ticker cannot tell you which chain it came from.
  final String chain;
  final String amount;
  final String ticker;
  final DateTime timestamp;
  final int confirmations;
  final String? note;
  final String? counterparty;

  bool get isConfirmed => confirmations > 0;

  bool get isLiquid => chain == 'liquid';
}

class DashboardData {
  const DashboardData({
    required this.walletId,
    required this.walletName,
    required this.totalBalanceDisplay,
    required this.assets,
    required this.recentActivity,
    required this.syncState,
    this.liquidNetwork = 'liquid-testnet',
    this.bitcoinNetwork = 'bitcoin-testnet',
  });

  final String walletId;
  final String walletName;
  final String totalBalanceDisplay;
  final List<AssetBalance> assets;
  final List<RecentActivityItem> recentActivity;
  final String syncState;

  /// `liquid-testnet` | `liquid-regtest` — where the Liquid side lives.
  final String liquidNetwork;

  bool get isLiquidRegtest => liquidNetwork == 'liquid-regtest';

  /// `bitcoin-testnet` | `bitcoin-regtest` — where the Bitcoin side lives.
  final String bitcoinNetwork;

  bool get isBitcoinRegtest => bitcoinNetwork == 'bitcoin-regtest';

  DashboardData withActivity(List<RecentActivityItem> activity) =>
      DashboardData(
        walletId: walletId,
        walletName: walletName,
        totalBalanceDisplay: totalBalanceDisplay,
        assets: assets,
        recentActivity: activity,
        syncState: syncState,
        liquidNetwork: liquidNetwork,
        bitcoinNetwork: bitcoinNetwork,
      );
}
