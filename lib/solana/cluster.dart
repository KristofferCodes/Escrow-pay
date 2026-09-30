/// Which Solana cluster the app talks to.
///
/// The cluster is baked into every QR code so a devnet offer cannot be funded
/// by a buyer whose app is pointed at mainnet, and vice versa.
enum Cluster {
  devnet(
    id: 'devnet',
    defaultRpcUrl: 'https://api.devnet.solana.com',

    /// CAIP-2 identifier handed to the wallet during MWA authorization.
    chain: 'solana:devnet',
    label: 'Devnet',
  ),
  mainnet(
    id: 'mainnet-beta',
    defaultRpcUrl: 'https://api.mainnet-beta.solana.com',
    chain: 'solana:mainnet',
    label: 'Mainnet',
  );

  const Cluster({
    required this.id,
    required this.defaultRpcUrl,
    required this.chain,
    required this.label,
  });

  final String id;

  /// The public endpoint. Correct, but heavily rate limited — it answers 429
  /// under any real load, which is why the override below exists.
  final String defaultRpcUrl;

  final String chain;
  final String label;

  /// Endpoint overrides, supplied at build time so no key is committed:
  ///
  ///     flutter run --dart-define-from-file=config/local.json
  ///
  /// `config/local.json` is gitignored; `config/local.example.json` shows the
  /// shape. Note that anything compiled into an APK can be extracted by
  /// whoever installs it, so treat a key shipped this way as public and
  /// rate-limit it at the provider.
  static const _devnetRpcOverride = String.fromEnvironment('DEVNET_RPC_URL');
  static const _mainnetRpcOverride = String.fromEnvironment('MAINNET_RPC_URL');

  String get rpcUrl => switch (this) {
    Cluster.devnet =>
      _devnetRpcOverride.isEmpty ? defaultRpcUrl : _devnetRpcOverride,
    Cluster.mainnet =>
      _mainnetRpcOverride.isEmpty ? defaultRpcUrl : _mainnetRpcOverride,
  };

  /// Whether this build points at a private endpoint. Surfaced in diagnostics
  /// so the URL itself never has to be.
  bool get usesCustomRpc => rpcUrl != defaultRpcUrl;

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
