import 'dart:typed_data';

import 'package:escrow_pay/core/escrow.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds account data in exactly the layout the onchain `EscrowAccount`
/// serialises to, so a change on either side shows up as a failure here.
Uint8List encodeAccount({
  required int sellerFill,
  required int buyerFill,
  required int amount,
  required int state,
  required int createdAt,
  required int nonce,
  required int bump,
}) {
  final data = Uint8List(Escrow.encodedLength);
  final view = ByteData.sublistView(data);
  var offset = 0;

  // Anchor discriminator; the decoder skips it.
  offset += 8;

  data.fillRange(offset, offset + 32, sellerFill);
  offset += 32;
  data.fillRange(offset, offset + 32, buyerFill);
  offset += 32;

  view.setUint64(offset, amount, Endian.little);
  offset += 8;
  view.setUint8(offset, state);
  offset += 1;
  view.setInt64(offset, createdAt, Endian.little);
  offset += 8;
  view.setUint64(offset, nonce, Endian.little);
  offset += 8;
  view.setUint8(offset, bump);

  return data;
}

String hexAddress(Uint8List key) =>
    key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  Escrow? decode(Uint8List data) => Escrow.decode(
    address: 'EscrowPda',
    data: data,
    encodeAddress: hexAddress,
  );

  test('agrees with the program on the EscrowAccount size', () {
    // The Rust side pins the same number in `EscrowAccount::LEN`. If these two
    // ever disagree, every offset below is reading the wrong bytes.
    expect(Escrow.encodedLength, 98);
  });

  test('decodes every field at the right offset', () {
    final escrow = decode(
      encodeAccount(
        sellerFill: 0xAA,
        buyerFill: 0xBB,
        amount: 1500000000,
        state: 1,
        createdAt: 1727180000,
        nonce: 77,
        bump: 254,
      ),
    )!;

    expect(escrow.address, 'EscrowPda');
    expect(escrow.seller, 'aa' * 32);
    expect(escrow.buyer, 'bb' * 32);
    expect(escrow.amount, 1500000000);
    expect(escrow.state, EscrowState.funded);
    expect(escrow.nonce, 77);
    expect(escrow.bump, 254);
    expect(escrow.createdAt.toUtc(), DateTime.utc(2024, 9, 24, 12, 13, 20));
  });

  test('maps each state ordinal to the onchain enum', () {
    const expected = {
      0: EscrowState.created,
      1: EscrowState.funded,
      2: EscrowState.released,
      3: EscrowState.refunded,
    };

    expected.forEach((ordinal, state) {
      final escrow = decode(
        encodeAccount(
          sellerFill: 1,
          buyerFill: 2,
          amount: 1,
          state: ordinal,
          createdAt: 0,
          nonce: 0,
          bump: 255,
        ),
      );
      expect(escrow!.state, state);
    });
  });

  test('returns null rather than throwing on foreign account data', () {
    // Short buffer — an account that is not an escrow at all.
    expect(decode(Uint8List(20)), isNull);
    // Valid length, but a state ordinal the program never writes.
    expect(
      decode(
        encodeAccount(
          sellerFill: 1,
          buyerFill: 2,
          amount: 1,
          state: 9,
          createdAt: 0,
          nonce: 0,
          bump: 255,
        ),
      ),
      isNull,
    );
  });

  test('only released and refunded are terminal', () {
    expect(EscrowState.created.isSettled, isFalse);
    expect(EscrowState.funded.isSettled, isFalse);
    expect(EscrowState.released.isSettled, isTrue);
    expect(EscrowState.refunded.isSettled, isTrue);
  });
}
