import 'package:flutter_riverpod/flutter_riverpod.dart';

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
}
