import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/release_code.dart';

/// Keeps the buyer's release secrets off the chain and off disk in clear.
///
/// Keystore-backed on Android, so a secret is not readable from a backup or
/// by another app. It is deliberately *not* synced anywhere: losing the phone
/// loses the code, and the app falls back to the buyer tapping release.
class ReleaseCodeStore {
  /// The default Android options are already keystore-backed AES-GCM with
  /// RSA key wrapping, and require API 23 — which matches the app's minSdk.
  ReleaseCodeStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<void> save(String escrowAddress, ReleaseCode code) => _storage.write(
    key: ReleaseCodeKeys.forEscrow(escrowAddress),
    value: code.secretHex,
  );

  /// Null when the buyer funded on another device, reinstalled, or the escrow
  /// predates release codes. The UI hides the code option rather than showing
  /// one that cannot work.
  Future<ReleaseCode?> read(String escrowAddress) async {
    try {
      return ReleaseCode.fromHex(
        await _storage.read(key: ReleaseCodeKeys.forEscrow(escrowAddress)),
      );
    } on Object {
      // A corrupt keystore entry should degrade to "no code", not crash the
      // handover screen.
      return null;
    }
  }

  /// Called once an escrow settles; the secret is spent and worth nothing.
  Future<void> forget(String escrowAddress) async {
    try {
      await _storage.delete(key: ReleaseCodeKeys.forEscrow(escrowAddress));
    } on Object {
      // Nothing useful to do, and the secret is already unusable.
    }
  }
}

final releaseCodeStoreProvider = Provider<ReleaseCodeStore>(
  (ref) => ReleaseCodeStore(),
);
