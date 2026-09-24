import 'dart:convert';

import 'package:solana_kit/solana_kit.dart';
import 'package:solana_kit_mobile_wallet_adapter/solana_kit_mobile_wallet_adapter.dart';
import 'package:solana_kit_mobile_wallet_adapter_protocol/solana_kit_mobile_wallet_adapter_protocol.dart';

import 'cluster.dart';

/// A connected wallet.
class WalletSession {
  const WalletSession({
    required this.address,
    required this.authToken,
    this.label,
  });

  final Address address;

  /// Lets later transactions reauthorize silently instead of prompting the
  /// user to pick an account again.
  final String authToken;
  final String? label;
}

/// Raised when the user dismisses the wallet, or no wallet is installed.
class WalletCancelled implements Exception {
  const WalletCancelled(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thin wrapper over Mobile Wallet Adapter.
///
/// MWA has no long-lived connection: every call opens a session, hands control
/// to the wallet app, and tears the session down. What persists between calls
/// is the auth token, which is why it is threaded through every method here.
class WalletService {
  WalletService({required this.cluster});

  final Cluster cluster;

  static final _identity = AppIdentity(
    name: 'Escrow Pay',
    uri: Uri.parse('https://escrowpay.app'),
    icon: 'favicon.ico',
  );

  bool get isSupported => isMwaSupported();

  /// Prompts the user to pick an account and approve this app.
  Future<WalletSession> connect() async {
    return _guard(() async {
      return transact((wallet) async {
        final result = await wallet.authorize(
          identity: _identity,
          chain: cluster.chain,
        );
        return _toSession(result);
      });
    });
  }

  /// Builds, signs and submits a transaction in one wallet round trip.
  ///
  /// [build] is given the address the wallet actually authorized, which can
  /// differ from the cached one if the user switched accounts — so the
  /// transaction is always assembled against the key that will sign it.
  Future<String> signAndSend({
    required WalletSession session,
    required Future<String> Function(Address signer) buildBase64Transaction,
  }) async {
    return _guard(() async {
      return transact((wallet) async {
        final auth = await wallet.reauthorize(
          authToken: session.authToken,
          identity: _identity,
        );
        final signer = _addressOf(auth);

        final payload = await buildBase64Transaction(signer);
        final signatures = await wallet.signAndSendTransactions(
          payloads: [payload],
          options: const SignAndSendOptions(commitment: 'confirmed'),
        );

        if (signatures.isEmpty) {
          throw const WalletCancelled('The wallet returned no signature.');
        }
        return signatures.first;
      });
    });
  }

  /// Revokes this app's authorization in the wallet.
  Future<void> disconnect(WalletSession session) async {
    try {
      await transact(
        (wallet) => wallet.deauthorize(authToken: session.authToken),
      );
    } on Object {
      // Local state is cleared either way; a failed revoke must not strand the
      // user on a screen they cannot leave.
    }
  }

  WalletSession _toSession(AuthorizationResult result) {
    final account = result.accounts.first;
    return WalletSession(
      address: _addressOf(result),
      authToken: result.authToken,
      label: account.label,
    );
  }

  /// MWA reports addresses as base64-encoded public keys, not base58.
  Address _addressOf(AuthorizationResult result) {
    if (result.accounts.isEmpty) {
      throw const WalletCancelled('The wallet authorized no accounts.');
    }
    final bytes = base64Decode(result.accounts.first.address);
    return getAddressFromPublicKey(bytes);
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    if (!isSupported) {
      throw const WalletCancelled(
        'Mobile Wallet Adapter needs Android. Install a wallet such as '
        'Solflare or Phantom and run this on a device or emulator.',
      );
    }
    try {
      return await action();
    } on WalletCancelled {
      rethrow;
    } on Object catch (error) {
      throw WalletCancelled(_readable(error));
    }
  }

  String _readable(Object error) {
    final text = error.toString();
    if (text.contains('NoWalletFound') || text.contains('ActivityNotFound')) {
      return 'No Solana wallet app found. Install Solflare or Phantom first.';
    }
    if (text.contains('timed out') || text.contains('Timeout')) {
      return 'The wallet did not respond in time. Try again.';
    }
    if (text.contains('declined') || text.contains('Cancel')) {
      return 'Request declined in the wallet.';
    }
    return text;
  }
}
