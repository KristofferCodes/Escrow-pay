import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The buyer's release secret, and the QR payload that carries it.
///
/// The buyer generates 32 random bytes when funding; only `sha256(secret)`
/// goes onchain. Showing the secret is what pays the seller, so the money
/// moves at the moment the goods do rather than on a promise either side has
/// to keep afterwards.
///
/// Handing over the code is safe for the buyer: the program pins the payout
/// to the seller recorded at funding, so the code authorises a payment, never
/// a destination.
class ReleaseCode {
  const ReleaseCode(this.secret);

  static const secretLength = 32;

  final Uint8List secret;

  /// Uses [Random.secure] — the platform CSPRNG. A predictable secret would
  /// let anyone who saw the escrow address release it.
  factory ReleaseCode.generate() {
    final random = Random.secure();
    return ReleaseCode(
      Uint8List.fromList(
        List<int>.generate(secretLength, (_) => random.nextInt(256)),
      ),
    );
  }

  /// What the program stores and compares against.
  Uint8List get hash => Uint8List.fromList(sha256.convert(secret).bytes);

  String get secretHex => _hex(secret);
  String get hashHex => _hex(hash);

  /// Round-trips through secure storage, which only holds strings.
  static ReleaseCode? fromHex(String? value) {
    if (value == null || value.length != secretLength * 2) return null;

    final bytes = Uint8List(secretLength);
    for (var i = 0; i < secretLength; i++) {
      final byte = int.tryParse(value.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) return null;
      bytes[i] = byte;
    }
    return ReleaseCode(bytes);
  }

  /// All zeroes: what `initialize_escrow` is given when no code is set.
  /// The program refuses to release against it rather than treating the
  /// preimage of 32 zero bytes as a secret.
  static Uint8List get noCodeHash => Uint8List(secretLength);

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// The QR the buyer shows at handover.
///
/// Deliberately a different scheme path from the seller's offer code
/// (`escrowpay:v1`) so a scanner can tell them apart before parsing, and
/// refuse one where it expected the other.
///
///     escrowpay:release:v1?e=<escrow address>&k=<secret hex>&c=<cluster>
class ReleasePayload {
  const ReleasePayload({
    required this.escrow,
    required this.code,
    required this.cluster,
  });

  static const scheme = 'escrowpay';
  static const path = 'release:v1';
  static const prefix = '$scheme:$path';

  final String escrow;
  final ReleaseCode code;
  final String cluster;

  String encode() {
    final query = Uri(
      queryParameters: {'e': escrow, 'k': code.secretHex, 'c': cluster},
    ).query;
    return '$prefix?$query';
  }

  /// Returns `null` for anything that is not a well-formed release code, so
  /// the scanner can keep scanning rather than throwing on every stray
  /// barcode — including the seller's own offer QR.
  static ReleasePayload? decode(String raw) {
    final text = raw.trim();
    if (!text.startsWith('$prefix?')) return null;

    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }

    final params = uri.queryParameters;
    final escrow = params['e'];
    final cluster = params['c'];
    final code = ReleaseCode.fromHex(params['k']);

    if (escrow == null || escrow.isEmpty) return null;
    if (cluster == null || cluster.isEmpty) return null;
    if (code == null) return null;

    return ReleasePayload(escrow: escrow, code: code, cluster: cluster);
  }

  /// True when this is a release code rather than an offer. Lets the scanner
  /// give a useful message for the wrong kind of code instead of silently
  /// ignoring it.
  static bool looksLikeRelease(String raw) => raw.trim().startsWith('$prefix?');
}

/// Where a buyer's secrets live between funding and handover.
///
/// Keyed by escrow address because one wallet can have several trades open,
/// and the seller's scanner has to be told which escrow a code belongs to.
abstract final class ReleaseCodeKeys {
  static String forEscrow(String escrowAddress) =>
      'release_secret_${base64Url.encode(utf8.encode(escrowAddress))}';
}
