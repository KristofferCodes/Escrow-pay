import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/listing.dart';

/// Persists the seller's open listings across app launches.
///
/// Nothing here is secret — an offer is public by design, it gets shared —
/// but the app already depends on secure storage for release secrets, so
/// reusing it avoids a second storage dependency for one list.
class ListingStore {
  ListingStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _key = 'seller_listings_v1';
  static const _separator = '\n';

  /// Newest first, with expired entries swept on the way out so the sweep
  /// needs no background job.
  Future<List<Listing>> load() async {
    final raw = await _read();
    if (raw == null || raw.isEmpty) return const [];

    final listings =
        raw
            .split(_separator)
            .map(Listing.decode)
            .whereType<Listing>()
            .where((listing) => !listing.isExpired)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Write back only when the sweep actually removed something.
    if (listings.length != raw.split(_separator).length) {
      await _write(listings);
    }
    return listings;
  }

  Future<List<Listing>> add(Listing listing) async {
    final existing = await load();

    // The nonce identifies a listing; re-saving the same one should not
    // duplicate it.
    final merged = [
      listing,
      ...existing.where((l) => l.offer.nonce != listing.offer.nonce),
    ];
    await _write(merged);
    return merged;
  }

  Future<List<Listing>> remove(int nonce) async {
    final remaining = (await load())
        .where((l) => l.offer.nonce != nonce)
        .toList();
    await _write(remaining);
    return remaining;
  }

  Future<String?> _read() async {
    try {
      return await _storage.read(key: _key);
    } on Object {
      // A corrupt entry should read as "no listings", not crash the home
      // screen on launch.
      return null;
    }
  }

  Future<void> _write(List<Listing> listings) async {
    try {
      await _storage.write(
        key: _key,
        value: listings.map((l) => l.encode()).join(_separator),
      );
    } on Object {
      // Losing a listing is a nuisance, not a failure worth surfacing.
    }
  }
}

final listingStoreProvider = Provider<ListingStore>((ref) => ListingStore());
