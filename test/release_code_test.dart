import 'dart:typed_data';

import 'package:escrow_pay/core/qr_payload.dart';
import 'package:escrow_pay/core/release_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const escrow = '11111111111111111111111111111112';

  group('hashing', () {
    test('agrees with the Rust program on a fixed vector', () {
      // The buyer's phone hashes in Dart; the program checks in Rust. If the
      // two ever disagree every release code silently stops working, so both
      // sides pin the same pair. The Rust half lives in state.rs as
      // sha256_matches_the_shared_test_vector.
      final secret = Uint8List.fromList(List.generate(32, (i) => i));
      expect(
        ReleaseCode(secret).hashHex,
        '630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd',
      );

      final allAb = Uint8List.fromList(List.filled(32, 0xAB));
      expect(
        ReleaseCode(allAb).hashHex,
        '9a2db2e23f1504cd056606553ac049c5e718e8f9ce9233876df1a7a1821af885',
      );
    });

    test('generates 32 bytes that differ between codes', () {
      final a = ReleaseCode.generate();
      final b = ReleaseCode.generate();

      expect(a.secret, hasLength(32));
      expect(a.hash, hasLength(32));
      expect(a.secretHex, isNot(b.secretHex));
    });

    test('the no-code sentinel is all zeroes', () {
      // The program refuses to release against this, so it must not look
      // like a real hash.
      expect(ReleaseCode.noCodeHash, Uint8List(32));
      expect(ReleaseCode.noCodeHash.every((b) => b == 0), isTrue);
    });
  });

  group('secret round trip', () {
    test('survives storage as hex', () {
      final code = ReleaseCode.generate();
      expect(ReleaseCode.fromHex(code.secretHex)!.secret, code.secret);
    });

    test('rejects anything that is not a 32-byte hex secret', () {
      expect(ReleaseCode.fromHex(null), isNull);
      expect(ReleaseCode.fromHex(''), isNull);
      expect(ReleaseCode.fromHex('abcd'), isNull);
      expect(ReleaseCode.fromHex('z' * 64), isNull);
      expect(ReleaseCode.fromHex('a' * 63), isNull);
      expect(ReleaseCode.fromHex('a' * 65), isNull);
    });
  });

  group('release payload', () {
    final code = ReleaseCode.generate();
    final payload = ReleasePayload(
      escrow: escrow,
      code: code,
      cluster: 'devnet',
    );

    test('round trips', () {
      final decoded = ReleasePayload.decode(payload.encode())!;

      expect(decoded.escrow, escrow);
      expect(decoded.cluster, 'devnet');
      expect(decoded.code.secretHex, code.secretHex);
    });

    test('uses a scheme a scanner can tell from an offer', () {
      expect(payload.encode(), startsWith('escrowpay:release:v1?'));
      expect(ReleasePayload.looksLikeRelease(payload.encode()), isTrue);
    });

    test('an offer code is not mistaken for a release code', () {
      // The seller's scanner sees both kinds and has to say which is which.
      const offer = EscrowOffer(
        seller: 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS',
        lamports: 1,
        nonce: 1,
        item: 'Thing',
        cluster: 'devnet',
      );

      expect(ReleasePayload.decode(offer.encode()), isNull);
      expect(ReleasePayload.looksLikeRelease(offer.encode()), isFalse);
      // And the reverse, so the buyer's scanner rejects a release code.
      expect(EscrowOffer.decode(payload.encode()), isNull);
    });

    test('rejects malformed codes', () {
      expect(ReleasePayload.decode('escrowpay:release:v2?e=x&k=y&c=z'), isNull);
      expect(ReleasePayload.decode('https://example.com'), isNull);
      expect(ReleasePayload.decode(''), isNull);
      // Missing or bad secret.
      expect(
        ReleasePayload.decode('escrowpay:release:v1?e=$escrow&c=devnet'),
        isNull,
      );
      expect(
        ReleasePayload.decode(
          'escrowpay:release:v1?e=$escrow&k=short&c=devnet',
        ),
        isNull,
      );
      // Missing escrow.
      expect(
        ReleasePayload.decode(
          'escrowpay:release:v1?k=${code.secretHex}&c=devnet',
        ),
        isNull,
      );
    });

    test('carries the cluster so a devnet code cannot be used on mainnet', () {
      final mainnet = ReleasePayload(
        escrow: escrow,
        code: code,
        cluster: 'mainnet-beta',
      );
      expect(ReleasePayload.decode(mainnet.encode())!.cluster, 'mainnet-beta');
    });
  });

  test('storage keys are distinct per escrow', () {
    expect(
      ReleaseCodeKeys.forEscrow('escrowA'),
      isNot(ReleaseCodeKeys.forEscrow('escrowB')),
    );
    expect(ReleaseCodeKeys.forEscrow(escrow), startsWith('release_secret_'));
  });
}
