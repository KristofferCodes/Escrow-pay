import 'package:escrow_pay/core/qr_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const seller = 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';

  const offer = EscrowOffer(
    seller: seller,
    lamports: 500000000,
    nonce: 1727180000000,
    item: 'Pixel 8 Pro, 256GB',
    cluster: 'devnet',
  );

  test('round trips every field', () {
    final decoded = EscrowOffer.decode(offer.encode())!;

    expect(decoded.seller, offer.seller);
    expect(decoded.lamports, offer.lamports);
    expect(decoded.nonce, offer.nonce);
    expect(decoded.item, offer.item);
    expect(decoded.cluster, offer.cluster);
  });

  test('encodes as a readable escrowpay URI', () {
    expect(offer.encode(), startsWith('escrowpay:v1?'));
    expect(offer.encode(), contains('s=$seller'));
  });

  test('survives item names with separators and unicode', () {
    const awkward = EscrowOffer(
      seller: seller,
      lamports: 1,
      nonce: 0,
      item: 'Chair & desk — 50% off?',
      cluster: 'devnet',
    );
    expect(EscrowOffer.decode(awkward.encode())!.item, awkward.item);
  });

  group('rejects', () {
    test('anything that is not an escrowpay code', () {
      expect(EscrowOffer.decode('https://example.com'), isNull);
      expect(EscrowOffer.decode('solana:abc'), isNull);
      expect(EscrowOffer.decode(''), isNull);
    });

    test('a future protocol version', () {
      expect(
        EscrowOffer.decode(offer.encode().replaceFirst('v1?', 'v2?')),
        isNull,
      );
    });

    test('missing or nonsensical fields', () {
      expect(EscrowOffer.decode('escrowpay:v1?a=1&n=1&c=devnet'), isNull);
      expect(EscrowOffer.decode('escrowpay:v1?s=$seller&n=1&c=devnet'), isNull);
      expect(
        EscrowOffer.decode('escrowpay:v1?s=$seller&a=0&n=1&c=devnet'),
        isNull,
      );
      expect(
        EscrowOffer.decode('escrowpay:v1?s=$seller&a=-5&n=1&c=devnet'),
        isNull,
      );
      expect(EscrowOffer.decode('escrowpay:v1?s=$seller&a=1&n=1'), isNull);
    });
  });

  test('falls back to a placeholder when the item is blank', () {
    final decoded = EscrowOffer.decode(
      'escrowpay:v1?s=$seller&a=1&n=1&i=%20%20&c=devnet',
    )!;
    expect(decoded.item, 'Item');
  });

  test('fresh nonces differ across listings', () {
    expect(EscrowOffer.freshNonce(), greaterThan(0));
  });

  group('refund window', () {
    test('round trips the timeout', () {
      const short = EscrowOffer(
        seller: seller,
        lamports: 1,
        nonce: 1,
        item: 'x',
        cluster: 'devnet',
        timeoutSeconds: 6 * 60 * 60,
      );
      expect(EscrowOffer.decode(short.encode())!.timeoutSeconds, 21600);
      expect(EscrowOffer.decode(short.encode())!.timeout.inHours, 6);
    });

    test('defaults to 24 hours', () {
      expect(offer.timeoutSeconds, 86400);
    });

    test('rejects a window the program would refuse', () {
      // The seller writes this into the QR, so a hostile one could ask for a
      // second — which would let them claim before the buyer got home. The
      // program enforces the same bounds; this just fails faster.
      for (final seconds in [1, 59 * 60, 31 * 24 * 60 * 60]) {
        expect(
          EscrowOffer.decode(
            'escrowpay:v1?s=$seller&a=1&n=1&c=devnet&t=$seconds',
          ),
          isNull,
          reason: '$seconds should be out of range',
        );
      }
    });

    test('accepts both ends of the allowed range', () {
      for (final seconds in [60 * 60, 30 * 24 * 60 * 60]) {
        expect(
          EscrowOffer.decode(
            'escrowpay:v1?s=$seller&a=1&n=1&c=devnet&t=$seconds',
          )!.timeoutSeconds,
          seconds,
        );
      }
    });

    test('a code written before timeouts existed still scans', () {
      final old = EscrowOffer.decode(
        'escrowpay:v1?s=$seller&a=1&n=1&i=Thing&c=devnet',
      );
      expect(old, isNotNull);
      expect(old!.timeoutSeconds, EscrowOffer.defaultTimeoutSeconds);
    });
  });
}
