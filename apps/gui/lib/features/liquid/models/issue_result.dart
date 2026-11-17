/// What `issue_asset` / `reissue_asset` answered (templarlib docs/API.md,
/// **IssueResult**).
class IssueResult {
  const IssueResult({
    required this.assetId,
    this.tokenId,
    required this.txid,
    required this.registryRegistered,
    required this.proofUrl,
    required this.proofContent,
    this.bookRegistered = false,
    this.bookError,
    this.domain = '',
  });

  final String assetId;
  final String? tokenId;
  final String txid;

  /// Liquid testnet's public registry took it (never on a regtest).
  final bool registryRegistered;

  /// The testnet domain proof; empty on a regtest and for a reissuance.
  final String proofUrl;
  final String proofContent;

  /// The active order book's registry stored the asset, so other wallets
  /// and the book name it.
  final bool bookRegistered;

  /// Why the book did not, for people; null when stored or not asked.
  final String? bookError;

  /// The issuer domain in the contract (on a test server's regtest the
  /// engine's reserved default); empty for a reissuance.
  final String domain;

  factory IssueResult.fromJson(Map<String, dynamic> j) => IssueResult(
    assetId: j['asset_id'] as String? ?? '',
    tokenId: j['token_id'] as String?,
    txid: j['txid'] as String? ?? '',
    registryRegistered: j['registry_registered'] as bool? ?? false,
    proofUrl: j['proof_url'] as String? ?? '',
    proofContent: j['proof_content'] as String? ?? '',
    bookRegistered: j['book_registered'] as bool? ?? false,
    bookError: j['book_error'] as String?,
    domain: j['domain'] as String? ?? '',
  );
}

/// What `reregister_asset` answered.
class ReregisterResult {
  const ReregisterResult({
    required this.registered,
    required this.bookRegistered,
    this.bookError,
  });

  /// Liquid testnet's public registry took it (always false on a regtest).
  final bool registered;

  /// The active order book's registry stored it.
  final bool bookRegistered;

  /// Why the book did not, for people.
  final String? bookError;

  factory ReregisterResult.fromJson(Map<String, dynamic> j) => ReregisterResult(
    registered: j['registered'] as bool? ?? false,
    bookRegistered: j['book_registered'] as bool? ?? false,
    bookError: j['book_error'] as String?,
  );
}
