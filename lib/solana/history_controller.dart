import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana_kit/solana_kit.dart';

import '../core/escrow.dart';
import 'wallet_controller.dart';

/// Every escrow the connected wallet has been party to.
///
/// Rebuilds when the wallet changes, so disconnecting clears the list rather
/// than leaving someone else's trades on screen.
class HistoryController extends AsyncNotifier<List<Escrow>> {
  @override
  Future<List<Escrow>> build() async {
    final session = ref.watch(walletControllerProvider).session;
    if (session == null) return const [];

    return ref.read(escrowRepositoryProvider).history(session.address);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Seller takes an escrow whose refund window has closed.
  ///
  /// This is the seller's only way to move funds, and it exists so that a
  /// buyer who never confirms cannot strand the money indefinitely.
  Future<String?> claim(Escrow escrow) async {
    final session = await ref.read(walletControllerProvider.notifier).require();
    if (session == null) return null;

    final signature = await ref
        .read(escrowRepositoryProvider)
        .claim(session: session, escrow: escrow);

    // Re-read rather than patching locally: the chain decides whether it
    // actually settled.
    final settled = await ref
        .read(escrowRepositoryProvider)
        .awaitState(Address(escrow.address), target: EscrowState.released);

    if (settled != null) await refresh();
    return signature;
  }
}

final historyControllerProvider =
    AsyncNotifierProvider<HistoryController, List<Escrow>>(
      HistoryController.new,
    );

/// What the wallet did in a given escrow. The same account reads differently
/// depending on which side you were on.
enum TradeSide { bought, sold }

extension EscrowSide on Escrow {
  TradeSide sideFor(String wallet) =>
      buyer == wallet ? TradeSide.bought : TradeSide.sold;

  /// Whether this wallet can claim right now: it has to be the seller, the
  /// escrow still funded, and the buyer's refund window closed.
  bool claimableBy(String wallet) =>
      seller == wallet && state == EscrowState.funded && refundWindowClosed;
}
