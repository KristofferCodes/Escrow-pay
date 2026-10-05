import 'package:escrow_pay/core/deep_link.dart';
import 'package:escrow_pay/core/qr_payload.dart';
import 'package:escrow_pay/core/release_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const seller = 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';
  const escrow = '11111111111111111111111111111112';

  const offer = EscrowOffer(
    seller: seller,
    lamports: 500000000,
    nonce: 42,
    item: 'Pixel 8 Pro',
    cluster: 'devnet',
  );

  final release = ReleasePayload(
    escrow: escrow,
    code: ReleaseCode.generate(),
    cluster: 'devnet',
  );

  group('routing', () {
    test('a listing link routes to the buyer flow', () {
      final link = DeepLink.parse(offer.encode());
      expect(link, isA<OfferLink>());
      expect((link! as OfferLink).offer.nonce, 42);
    });

    test('a release link routes to redemption, not the buyer flow', () {
      // Both are escrowpay: links; sending a release code to the funding
      // screen would be a confusing dead end.
      final link = DeepLink.parse(release.encode());
      expect(link, isA<ReleaseLink>());
      expect((link! as ReleaseLink).payload.escrow, escrow);
    });

    test('ignores anything that is not ours', () {
      expect(DeepLink.parse('https://example.com'), isNull);
      expect(DeepLink.parse('solana:abc'), isNull);
      expect(DeepLink.parse(''), isNull);
      expect(DeepLink.parse('escrowpay:v2?s=x'), isNull);
    });
  });

  group('links shared inside a message', () {
    test('finds a listing wrapped in a sentence', () {
      // This is how share_plus sends it, and how a person would paste it.
      final shared =
          'Pay 0.5 SOL for "Pixel 8 Pro" through Escrow Pay.\n\n'
          'Open this in Escrow Pay, or scan the code:\n'
          '${offer.encode()}';

      final link = DeepLink.findIn(shared);
      expect(link, isA<OfferLink>());
      expect((link! as OfferLink).offer.item, 'Pixel 8 Pro');
    });

    test('finds a release code wrapped in a sentence', () {
      final link = DeepLink.findIn('here you go: ${release.encode()} thanks');
      expect(link, isA<ReleaseLink>());
    });

    test('returns null when the message holds no link', () {
      expect(DeepLink.findIn('just a normal message'), isNull);
    });

    test('does not mistake a release link for a listing', () {
      // Both start 'escrowpay:', so a loose pattern would match the wrong
      // one and send the seller to the funding screen.
      final link = DeepLink.findIn('code: ${release.encode()}');
      expect(link, isA<ReleaseLink>());
      expect(link, isNot(isA<OfferLink>()));
    });
  });
}
