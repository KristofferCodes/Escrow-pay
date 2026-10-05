import 'qr_payload.dart';
import 'release_code.dart';

/// What an incoming `escrowpay:` link turned out to be.
///
/// Both kinds of QR are also links, so a shared one has to be routed to the
/// right place rather than assumed to be a listing.
sealed class DeepLink {
  const DeepLink();

  /// Returns null for anything that is not ours — another app's scheme, a
  /// truncated paste, a link for a different cluster.
  static DeepLink? parse(String raw) {
    final text = raw.trim();

    final release = ReleasePayload.decode(text);
    if (release != null) return ReleaseLink(release);

    final offer = EscrowOffer.decode(text);
    if (offer != null) return OfferLink(offer);

    return null;
  }

  /// Pulls a link out of surrounding text. Shared messages arrive wrapped in
  /// a sentence, and demanding a bare URI would make sharing useless.
  static DeepLink? findIn(String text) {
    final match = RegExp(
      r'escrowpay:(?:release:v1|v1)\?[^\s]+',
    ).firstMatch(text);
    return match == null ? null : parse(match.group(0)!);
  }
}

/// A seller's listing: the buyer should review and fund it.
class OfferLink extends DeepLink {
  const OfferLink(this.offer);
  final EscrowOffer offer;
}

/// A buyer's release code: the seller should redeem it.
class ReleaseLink extends DeepLink {
  const ReleaseLink(this.payload);
  final ReleasePayload payload;
}
