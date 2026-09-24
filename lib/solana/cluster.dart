/// Which Solana cluster the app talks to.
///
/// The cluster is baked into every QR code so a devnet offer cannot be funded
/// by a buyer whose app is pointed at mainnet, and vice versa.
enum Cluster {
  devnet(
    id: 'devnet',
    rpcUrl: 'https://api.devnet.solana.com',

    /// CAIP-2 identifier handed to the wallet during MWA authorization.
    chain: 'solana:devnet',
    label: 'Devnet',
  ),
  mainnet(
    id: 'mainnet-beta',
    rpcUrl: 'https://api.mainnet-beta.solana.com',
    chain: 'solana:mainnet',
    label: 'Mainnet',
  );

  const Cluster({
    required this.id,
    required this.rpcUrl,
    required this.chain,
    required this.label,
  });

  final String id;
  final String rpcUrl;
  final String chain;
  final String label;

  static Cluster? fromId(String id) {
    for (final cluster in values) {
      if (cluster.id == id) return cluster;
    }
    return null;
  }

  /// The cluster this build targets. Devnet through the hackathon; flip to
  /// [Cluster.mainnet] for the dApp Store submission build.
  static const active = Cluster.devnet;

  String explorerTx(String signature) =>
      'https://explorer.solana.com/tx/$signature?cluster=$id';

  String explorerAddress(String address) =>
      'https://explorer.solana.com/address/$address?cluster=$id';
}
