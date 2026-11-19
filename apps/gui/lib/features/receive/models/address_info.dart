class AddressInfo {
  const AddressInfo({
    required this.address,
    required this.index,
    required this.asset,
    this.label,
    this.receivedSats = 0,
    this.derivationPath,
    this.unconfidentialAddress,
  });

  /// The address to hand out. On Liquid the confidential form, which carries
  /// the wallet's blinding key so a payer hides amount and asset.
  final String address;
  final int index;
  final String asset;
  final String? label;
  final int receivedSats;
  final String? derivationPath;

  /// Liquid only: [address] without its blinding key. The key never goes on
  /// chain, so this is the form an explorer shows; paying it sends amount
  /// and asset in the clear. Null on Bitcoin.
  final String? unconfidentialAddress;
}
