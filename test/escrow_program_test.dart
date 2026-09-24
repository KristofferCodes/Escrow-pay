import 'dart:typed_data';

import 'package:escrow_pay/solana/escrow_program.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana_kit/solana_kit.dart';

void main() {
  const seller = Address('Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS');
  const buyer = Address('9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM');
  const escrow = Address('11111111111111111111111111111112');

  group('discriminators', () {
    // These are the bytes Anchor itself emits for each instruction. They are
    // hardcoded rather than recomputed so a change to the derivation, or a
    // rename of an instruction, fails loudly instead of silently producing a
    // transaction the program rejects as unknown.
    const expected = {
      'initialize_escrow': [243, 160, 77, 153, 11, 92, 48, 209],
      'deposit': [242, 35, 198, 137, 82, 225, 242, 182],
      'confirm_receipt': [203, 36, 80, 115, 249, 12, 141, 170],
      'refund': [2, 96, 183, 251, 63, 208, 46, 46],
    };

    expected.forEach((instruction, bytes) {
      test('$instruction matches Anchor', () {
        expect(EscrowProgram.discriminator(instruction), bytes);
      });
    });
  });

  group('instruction data', () {
    test('initialize_escrow carries nonce then amount, little endian', () {
      final data = EscrowProgram.initializeEscrow(
        escrow: escrow,
        buyer: buyer,
        seller: seller,
        nonce: 1,
        lamports: 500000000,
      ).data!;

      expect(data.length, 8 + 8 + 8);

      final view = ByteData.sublistView(data);
      expect(view.getUint64(8, Endian.little), 1);
      expect(view.getUint64(16, Endian.little), 500000000);
    });

    test('the other three carry only a discriminator', () {
      expect(
        EscrowProgram.deposit(escrow: escrow, buyer: buyer).data,
        hasLength(8),
      );
      expect(
        EscrowProgram.confirmReceipt(
          escrow: escrow,
          buyer: buyer,
          seller: seller,
        ).data,
        hasLength(8),
      );
      expect(
        EscrowProgram.refund(escrow: escrow, buyer: buyer).data,
        hasLength(8),
      );
    });
  });

  group('account roles', () {
    test('initialize_escrow leaves the seller unsigned and read only', () {
      final accounts = EscrowProgram.initializeEscrow(
        escrow: escrow,
        buyer: buyer,
        seller: seller,
        nonce: 1,
        lamports: 1,
      ).accounts!;

      expect(accounts[0].role, AccountRole.writable); // escrow PDA
      expect(accounts[1].role, AccountRole.writableSigner); // buyer pays
      expect(accounts[2].address, seller);
      expect(accounts[2].role, AccountRole.readonly);
      expect(accounts[3].address, EscrowProgram.systemProgramId);
    });

    test('confirm_receipt makes the seller writable so they can be paid', () {
      final accounts = EscrowProgram.confirmReceipt(
        escrow: escrow,
        buyer: buyer,
        seller: seller,
      ).accounts!;

      expect(
        accounts[1].role,
        AccountRole.writableSigner,
      ); // only the buyer signs
      expect(accounts[2].address, seller);
      expect(accounts[2].role, AccountRole.writable);
    });

    test('refund never references the seller', () {
      final accounts = EscrowProgram.refund(
        escrow: escrow,
        buyer: buyer,
      ).accounts!;
      expect(accounts.map((a) => a.address), isNot(contains(seller)));
    });
  });

  group('PDA derivation', () {
    test('is deterministic for the same seller, buyer and nonce', () async {
      final (first, firstBump) = await EscrowProgram.deriveEscrow(
        seller: seller,
        buyer: buyer,
        nonce: 42,
      );
      final (second, secondBump) = await EscrowProgram.deriveEscrow(
        seller: seller,
        buyer: buyer,
        nonce: 42,
      );

      expect(first, second);
      expect(firstBump, secondBump);
      expect(firstBump, inInclusiveRange(0, 255));
    });

    test(
      'the nonce separates repeat trades between the same wallets',
      () async {
        final (first, _) = await EscrowProgram.deriveEscrow(
          seller: seller,
          buyer: buyer,
          nonce: 1,
        );
        final (second, _) = await EscrowProgram.deriveEscrow(
          seller: seller,
          buyer: buyer,
          nonce: 2,
        );

        expect(first, isNot(second));
      },
    );

    test('swapping buyer and seller yields a different escrow', () async {
      final (forward, _) = await EscrowProgram.deriveEscrow(
        seller: seller,
        buyer: buyer,
        nonce: 1,
      );
      final (reversed, _) = await EscrowProgram.deriveEscrow(
        seller: buyer,
        buyer: seller,
        nonce: 1,
      );

      expect(forward, isNot(reversed));
    });
  });
}
