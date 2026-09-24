/// The offer a seller encodes into a QR code, and the buyer scans.
///
/// This is the only channel between the two devices — there is no backend — so
/// the payload has to carry everything `initialize_escrow` needs. It is a URI
/// rather than opaque bytes so a scan can be eyeballed and debugged, and so a
/// generic QR reader shows something meaningful.
///
///     escrowpay:v1?s=<seller>&a=<lamports>&n=<nonce>&i=<item>&c=<cluster>
///
/// Nothing here is trusted: the buyer confirms the seller address and amount on
/// screen before signing, and the program re-derives the PDA from these same
/// values, so a tampered QR simply produces a different escrow.
class EscrowOffer {
  const EscrowOffer({
    required this.seller,
    required this.lamports,
    required this.nonce,
    required this.item,
    required this.cluster,
  });

  static const scheme = 'escrowpay';
  static const version = 'v1';

  /// Base58 address that will be paid on `confirm_receipt`.
  final String seller;
  final int lamports;
  final int nonce;
  final String item;

  /// `devnet` or `mainnet-beta`. Carried so a devnet QR cannot be funded with
  /// real SOL by a buyer whose app is pointed elsewhere.
  final String cluster;

  String encode() {
    final query = Uri(
      queryParameters: {
        's': seller,
        'a': '$lamports',
        'n': '$nonce',
        'i': item,
        'c': cluster,
      },
    ).query;
    return '$scheme:$version?$query';
  }

  /// Parses a scanned string. Returns `null` for anything that is not a
  /// well-formed v1 offer, so the scanner can keep scanning instead of
  /// throwing on every stray barcode in frame.
  static EscrowOffer? decode(String raw) {
    final text = raw.trim();
    if (!text.startsWith('$scheme:')) return null;

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }

    // `escrowpay:v1?...` parses with `v1` as the path.
    if (uri.path != version) return null;

    final params = uri.queryParameters;
    final seller = params['s'];
    final lamports = int.tryParse(params['a'] ?? '');
    final nonce = int.tryParse(params['n'] ?? '');
    final cluster = params['c'];

    if (seller == null || seller.isEmpty) return null;
    if (lamports == null || lamports <= 0) return null;
    if (nonce == null || nonce < 0) return null;
    if (cluster == null || cluster.isEmpty) return null;

    return EscrowOffer(
      seller: seller,
      lamports: lamports,
      nonce: nonce,
      item: params['i']?.trim().isNotEmpty == true
          ? params['i']!.trim()
          : 'Item',
      cluster: cluster,
    );
  }

  /// Nonces only need to be unique per seller/buyer pair, so the clock is
  /// enough and keeps the QR short.
  static int freshNonce() => DateTime.now().millisecondsSinceEpoch;
}
