/// Who named a Liquid asset, and when the app shows its id beside the name.
///
/// The engine names an asset from the wallet's own knowledge first, then
/// from the active order book's public registry, then from a market row's
/// own display data (templarlib docs/API.md, "Asset names"); it says which
/// in `metadata_source`. A registry or a feed can be wrong — anyone can
/// announce a token called "Tether" — but the asset id cannot, so a name
/// that did not come from the wallet is shown with its short id beside it.
library;

/// `wallet` | `book` | `feed` | `none`.
abstract final class AssetNameSource {
  static const wallet = 'wallet';
  static const book = 'book';
  static const feed = 'feed';
  static const none = 'none';
}

/// The first 8 hex digits of an asset id, as the engine shortens it.
String shortAssetId(String assetId) =>
    assetId.length > 8 ? assetId.substring(0, 8) : assetId;

/// Whether a name of [source] needs the short id beside it. Not for the
/// wallet's own names, not for an unnamed asset (its "name" is already the
/// short id), and not when the source is unknown (an older engine).
bool showsAssetIdBeside(String? source, {String? shownName, String? assetId}) {
  if (source != AssetNameSource.book && source != AssetNameSource.feed) {
    return false;
  }
  if (assetId == null || assetId.isEmpty || assetId.length < 16) return false;
  final short = shortAssetId(assetId);
  if (shownName != null && shownName.toLowerCase().startsWith(short)) {
    return false;
  }
  return true;
}

/// How a person reads where the name came from, for a tooltip or a caption.
String assetNameSourceLabel(String? source) => switch (source) {
  AssetNameSource.book => 'Named by the order book\'s registry',
  AssetNameSource.feed => 'Named by the market listing',
  AssetNameSource.none => 'Unnamed asset',
  _ => 'Named by this wallet',
};
