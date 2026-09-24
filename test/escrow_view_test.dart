import 'package:escrow_pay/core/escrow.dart';
import 'package:escrow_pay/core/qr_payload.dart';
import 'package:escrow_pay/solana/escrow_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solana_kit/solana_kit.dart';

void main() {
  const offer = EscrowOffer(
    seller: 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS',
    lamports: 1500000000,
    nonce: 7,
    item: 'Pixel 8 Pro',
    cluster: 'devnet',
  );

  Escrow escrowIn(EscrowState state, {int amount = 2000000000}) => Escrow(
    address: '11111111111111111111111111111112',
    seller: 'Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS',
    buyer: '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM',
    amount: amount,
    state: state,
    createdAt: DateTime.utc(2026, 9, 24),
    nonce: 7,
    bump: 254,
  );

  group('amount', () {
    test('falls back to the scanned offer before the account exists', () {
      expect(const EscrowView(offer: offer).amount, 1500000000);
    });

    test('prefers the chain once the account exists', () {
      // The QR is untrusted input; the account is the source of truth.
      expect(
        EscrowView(offer: offer, escrow: escrowIn(EscrowState.funded)).amount,
        2000000000,
      );
    });

    test('is zero with neither', () {
      expect(const EscrowView().amount, 0);
    });
  });

  group('available actions', () {
    test('only a funded escrow can be released or refunded', () {
      for (final state in EscrowState.values) {
        final view = EscrowView(offer: offer, escrow: escrowIn(state));
        final expected = state == EscrowState.funded;
        expect(view.canConfirm, expected, reason: '$state canConfirm');
        expect(view.canRefund, expected, reason: '$state canRefund');
      }
    });

    test('nothing is actionable while a wallet round trip is in flight', () {
      final view = EscrowView(
        offer: offer,
        escrow: escrowIn(EscrowState.funded),
        busy: true,
      );
      expect(view.canConfirm, isFalse);
      expect(view.canRefund, isFalse);
    });

    test('an escrow that does not exist yet reports created', () {
      expect(const EscrowView(offer: offer).state, EscrowState.created);
    });
  });

  group('copyWith', () {
    test('clearError wins over a supplied error', () {
      const view = EscrowView(error: 'boom');
      expect(view.copyWith(clearError: true).error, isNull);
      expect(view.copyWith(error: 'other', clearError: true).error, isNull);
    });

    test('a null confirmToken leaves the previous one alone', () {
      // This is what stops the particle burst replaying when a transaction is
      // submitted but never confirms: _run passes null, and the token must not
      // change, or the burst fires again.
      const view = EscrowView(confirmToken: 1);
      expect(view.copyWith(confirmToken: null).confirmToken, 1);
      expect(view.copyWith(confirmToken: 2).confirmToken, 2);
    });

    test('carries the escrow address forward', () {
      const address = Address('11111111111111111111111111111112');
      expect(const EscrowView().copyWith(address: address).address, address);
    });
  });
}
