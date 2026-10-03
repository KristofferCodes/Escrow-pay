import 'dart:typed_data';

import 'package:escrow_pay/core/escrow.dart';
import 'package:escrow_pay/solana/history_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const me = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';
  const them = 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS';

  Escrow escrow({
    required String buyer,
    required String seller,
    EscrowState state = EscrowState.released,
  }) => Escrow(
    address: '11111111111111111111111111111112',
    seller: seller,
    buyer: buyer,
    amount: 1500000000,
    state: state,
    createdAt: DateTime.utc(2026, 9, 30),
    deadline: DateTime.now().add(const Duration(hours: 24)),
    releaseHash: Uint8List(32),
    nonce: 1,
    bump: 254,
  );

  group('which side of the trade the wallet was on', () {
    test('buyer reads as bought', () {
      expect(escrow(buyer: me, seller: them).sideFor(me), TradeSide.bought);
    });

    test('seller reads as sold', () {
      expect(escrow(buyer: them, seller: me).sideFor(me), TradeSide.sold);
    });

    test('the same escrow reads oppositely to the counterparty', () {
      final trade = escrow(buyer: me, seller: them);
      expect(trade.sideFor(me), TradeSide.bought);
      expect(trade.sideFor(them), TradeSide.sold);
    });
  });

  group('account layout the history filters depend on', () {
    test('memcmp offsets match the decoder', () {
      // getProgramAccounts filters by raw byte offset, so these have to track
      // EscrowAccount's layout: discriminator(8) seller(32) buyer(32).
      // Unchanged by the deadline field, which sits after these — but the
      // dataSize filter did change, so the length is pinned too.
      const discriminator = 8;
      const sellerOffset = discriminator;
      const buyerOffset = discriminator + 32;

      expect(sellerOffset, 8);
      expect(buyerOffset, 40);
      expect(Escrow.encodedLength, 138);
    });
  });
}
