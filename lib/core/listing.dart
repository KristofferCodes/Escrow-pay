import 'qr_payload.dart';

/// A listing the seller created, kept so it survives leaving the app.
///
/// Generating a QR costs nothing onchain — it is pure offer data — but
/// losing it meant retyping the item and price and, worse, getting a new
/// nonce, so a buyer holding the old code could no longer pay.
class Listing {
  const Listing({required this.offer, required this.createdAt});

  final EscrowOffer offer;
  final DateTime createdAt;

  /// Listings are swept after this. Long enough to cover a trade arranged
  /// today and completed tomorrow; short enough that the list does not
  /// become a graveyard of abandoned codes.
  static const lifetime = Duration(hours: 48);

  DateTime get expiresAt => createdAt.add(lifetime);
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Duration get timeLeft => expiresAt.difference(DateTime.now());

  /// Stored as the offer URI plus a timestamp — the URI is already the
  /// canonical form, so there is no second encoding to keep in step.
  String encode() => '${createdAt.millisecondsSinceEpoch}|${offer.encode()}';

  static Listing? decode(String raw) {
    final split = raw.indexOf('|');
    if (split <= 0) return null;

    final millis = int.tryParse(raw.substring(0, split));
    if (millis == null) return null;

    final offer = EscrowOffer.decode(raw.substring(split + 1));
    if (offer == null) return null;

    return Listing(
      offer: offer,
      createdAt: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}
