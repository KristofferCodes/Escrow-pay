import 'package:escrow_pay/core/listing.dart';
import 'package:escrow_pay/core/qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const offer = EscrowOffer(
    seller: 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS',
    lamports: 500000000,
    nonce: 42,
    item: 'Pixel 8 Pro',
    cluster: 'devnet',
  );

  test('round trips through storage', () {
    final created = DateTime.fromMillisecondsSinceEpoch(1790000000000);
    final listing = Listing(offer: offer, createdAt: created);

    final decoded = Listing.decode(listing.encode())!;
    expect(decoded.createdAt, created);
    expect(decoded.offer.nonce, 42);
    expect(decoded.offer.item, 'Pixel 8 Pro');
    // The nonce surviving is the whole point: regenerating it would orphan
    // a code the buyer may already be holding.
    expect(decoded.offer.encode(), offer.encode());
  });

  test('rejects corrupt entries rather than throwing', () {
    expect(Listing.decode(''), isNull);
    expect(Listing.decode('no separator'), isNull);
    expect(Listing.decode('|escrowpay:v1?s=x'), isNull);
    expect(Listing.decode('notanumber|${offer.encode()}'), isNull);
    expect(Listing.decode('123|not-an-offer'), isNull);
  });

  group('expiry', () {
    test('a fresh listing is live with time left', () {
      final listing = Listing(offer: offer, createdAt: DateTime.now());
      expect(listing.isExpired, isFalse);
      expect(listing.timeLeft.inHours, greaterThan(46));
    });

    test('one past its lifetime is expired', () {
      final listing = Listing(
        offer: offer,
        createdAt: DateTime.now().subtract(const Duration(hours: 49)),
      );
      expect(listing.isExpired, isTrue);
      expect(listing.timeLeft.isNegative, isTrue);
    });

    test('the boundary is 48 hours', () {
      expect(Listing.lifetime, const Duration(hours: 48));

      final almost = Listing(
        offer: offer,
        createdAt: DateTime.now().subtract(const Duration(hours: 47)),
      );
      expect(almost.isExpired, isFalse);
    });
  });
}
