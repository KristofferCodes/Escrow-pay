import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana_kit/solana_kit.dart';

import '../core/escrow.dart';
import '../core/release_code.dart';
import 'escrow_repository.dart';
import 'wallet_controller.dart';

/// What the seller sees after scanning a buyer's release code.
///
/// The distinction that matters is [confirmed]: the seller must not hand the
/// item over until the chain has settled. A submitted-but-unconfirmed release
/// can still lose to a refund the buyer sends in the same window.
class ReleaseScanState {
  const ReleaseScanState({
    this.escrow,
    this.submitting = false,
    this.signature,
    this.confirmed = false,
    this.error,
  });

  final Escrow? escrow;
  final bool submitting;

  /// Set as soon as the wallet submits — not proof of anything yet.
  final String? signature;

  /// Set only once the chain reports the escrow Released.
  final bool confirmed;

  final String? error;

  /// Submitted but not yet settled. The seller is told to wait.
  bool get pending => signature != null && !confirmed;

  ReleaseScanState copyWith({
    Escrow? escrow,
    bool? submitting,
    String? signature,
    bool? confirmed,
    String? error,
    bool clearError = false,
  }) => ReleaseScanState(
    escrow: escrow ?? this.escrow,
    submitting: submitting ?? this.submitting,
    signature: signature ?? this.signature,
    confirmed: confirmed ?? this.confirmed,
    error: clearError ? null : (error ?? this.error),
  );
}

class ReleaseScanController extends Notifier<ReleaseScanState> {
  @override
  ReleaseScanState build() => const ReleaseScanState();

  EscrowRepository get _repo => ref.read(escrowRepositoryProvider);

  void reset() => state = const ReleaseScanState();

  /// Submits the scanned code, then waits for the chain before reporting
  /// success. The wait is the point — see [ReleaseScanState.confirmed].
  Future<void> redeem(ReleasePayload payload) async {
    if (state.submitting) return;
    state = const ReleaseScanState(submitting: true);

    try {
      final cluster = ref.read(clusterProvider);
      if (payload.cluster != cluster.id) {
        state = ReleaseScanState(
          error:
              'That code is for ${payload.cluster}. This app is on '
              '${cluster.id}.',
        );
        return;
      }

      final address = Address(payload.escrow);
      final escrow = await _repo.fetch(address);

      if (escrow == null) {
        state = const ReleaseScanState(
          error: 'That escrow does not exist on this network.',
        );
        return;
      }
      if (escrow.state != EscrowState.funded) {
        state = ReleaseScanState(
          escrow: escrow,
          error: 'This escrow is already ${escrow.state.name}.',
        );
        return;
      }

      final session = await ref
          .read(walletControllerProvider.notifier)
          .require();
      if (session == null) {
        state = ReleaseScanState(
          escrow: escrow,
          error:
              ref.read(walletControllerProvider).error ??
              'Connect a wallet to collect payment.',
        );
        return;
      }

      final signature = await _repo.releaseWithCode(
        session: session,
        escrow: escrow,
        secret: payload.code.secret,
      );
      state = state.copyWith(escrow: escrow, signature: signature);

      final settled = await _repo.awaitState(
        address,
        target: EscrowState.released,
      );

      state = state.copyWith(
        escrow: settled ?? escrow,
        submitting: false,
        // Only the chain decides this.
        confirmed: settled?.state == EscrowState.released,
        error: settled?.state == EscrowState.released
            ? null
            : 'Submitted, but not confirmed yet. Do not hand over the item '
                  'until it shows as paid.',
        clearError: settled?.state == EscrowState.released,
      );
    } on Object catch (error) {
      state = state.copyWith(submitting: false, error: _readable(error));
    }
  }

  String _readable(Object error) {
    final text = error.toString();
    if (text.contains('BadReleaseCode')) {
      return 'That code does not match this escrow.';
    }
    if (text.contains('NoReleaseCode')) {
      return 'This escrow was opened without a release code.';
    }
    if (text.contains('InvalidState')) {
      return 'This escrow has already been settled.';
    }
    return text;
  }
}

final releaseScanControllerProvider =
    NotifierProvider<ReleaseScanController, ReleaseScanState>(
      ReleaseScanController.new,
    );
