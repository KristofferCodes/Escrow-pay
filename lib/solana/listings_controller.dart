import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/escrow.dart';
import '../core/listing.dart';
import 'listing_store.dart';
import 'wallet_controller.dart';

/// A listing plus whatever the chain knows about it.
class WatchedListing {
  const WatchedListing({required this.listing, this.escrow});

  final Listing listing;

  /// Null until a buyer funds it. A listing is only an offer; there is no
  /// account until someone acts on it.
  final Escrow? escrow;

  bool get isPaid => escrow != null;
  bool get isSettled => escrow?.state.isSettled ?? false;

  /// The seller is waiting on this one.
  bool get isAwaitingBuyer => escrow == null;
}

class ListingsState {
  const ListingsState({
    this.listings = const [],
    this.loading = false,
    this.error,
  });

  final List<WatchedListing> listings;
  final bool loading;
  final String? error;

  /// Drives the badge on the home screen: something happened you have not
  /// looked at.
  int get awaitingCollection =>
      listings.where((l) => l.isPaid && !l.isSettled).length;
}

/// The seller's side of a trade, which until now had no screen at all.
///
/// A seller cannot derive their own escrow's address — the PDA seeds include
/// the buyer's key — so the only way to learn a listing was paid is to ask
/// the chain for escrows naming this seller and match the nonce from the QR.
class ListingsController extends Notifier<ListingsState> {
  Timer? _poll;

  @override
  ListingsState build() {
    ref.onDispose(() => _poll?.cancel());

    // Rebuilds when the wallet changes, so a different seller does not see
    // the previous one's listings matched against their escrows.
    ref.watch(walletControllerProvider.select((w) => w.session?.address));

    scheduleMicrotask(refresh);
    return const ListingsState(loading: true);
  }

  Future<void> refresh() async {
    final stored = await ref.read(listingStoreProvider).load();
    final session = ref.read(walletControllerProvider).session;

    if (stored.isEmpty) {
      _poll?.cancel();
      state = const ListingsState();
      return;
    }

    // Without a wallet we can still show the listings; we just cannot say
    // whether any were paid.
    if (session == null) {
      state = ListingsState(
        listings: [
          for (final listing in stored) WatchedListing(listing: listing),
        ],
      );
      return;
    }

    try {
      final escrows = await ref
          .read(escrowRepositoryProvider)
          .escrowsForSeller(session.address);

      final byNonce = {for (final escrow in escrows) escrow.nonce: escrow};

      state = ListingsState(
        listings: [
          for (final listing in stored)
            WatchedListing(
              listing: listing,
              escrow: byNonce[listing.offer.nonce],
            ),
        ],
      );
      _schedulePolling();
    } on Object catch (error) {
      state = ListingsState(
        listings: [
          for (final listing in stored) WatchedListing(listing: listing),
        ],
        error: _readable(error),
      );
    }
  }

  /// Watches for a buyer funding, so the seller is told rather than having
  /// to go looking. Stops once nothing is left that can change.
  void _schedulePolling() {
    _poll?.cancel();

    final live = state.listings.any((l) => !l.isSettled);
    if (!live) return;

    _poll = Timer.periodic(const Duration(seconds: 20), (timer) async {
      if (state.listings.every((l) => l.isSettled)) {
        timer.cancel();
        return;
      }
      await refresh();
    });
  }

  Future<void> save(Listing listing) async {
    await ref.read(listingStoreProvider).add(listing);
    await refresh();
  }

  Future<void> remove(int nonce) async {
    await ref.read(listingStoreProvider).remove(nonce);
    await refresh();
  }

  String _readable(Object error) {
    final text = error.toString();
    if (text.contains('400') || text.contains('not available')) {
      return 'Could not check which listings were paid — this RPC endpoint '
          'will not serve that query. Your listings are still here.';
    }
    if (text.contains('429')) {
      return 'Rate limited while checking for payments. Pull to refresh in '
          'a moment.';
    }
    return text;
  }
}

final listingsControllerProvider =
    NotifierProvider<ListingsController, ListingsState>(ListingsController.new);
