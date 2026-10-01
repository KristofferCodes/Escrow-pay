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

/// Raised when the user dismisses the wallet, or the handoff fails.
class WalletCancelled implements Exception {
  const WalletCancelled(this.message, {this.noWalletInstalled = false});

  final String message;

  /// True when nothing on the device can answer a Mobile Wallet Adapter
  /// intent. The only useful response is to install a wallet, so the UI
  /// offers that instead of a retry that cannot succeed.
  final bool noWalletInstalled;

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

  /// How long to wait for the wallet to answer before giving up.
  ///
  /// The plugin's own default is 30s, but relying on a default means a future
  /// version could silently make the user stare at a spinner. Stated here so
  /// the ceiling is ours: long enough for a cold wallet launch, short enough
  /// that a wallet which never comes back surfaces as an error.
  static const _handoffTimeout = Duration(seconds: 25);

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
      }, connectionTimeout: _handoffTimeout);
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
      return transact(
        (wallet) async {
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
        },
        // Bounds reaching the wallet, not how long the user spends reading
        // the confirmation sheet.
        connectionTimeout: _handoffTimeout,
      );
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
      // Reached on iOS, where the MWA plugin is a deliberate no-op. Say why
      // rather than offering Android advice the user cannot act on: there is
      // no iOS wallet to install that would make this work.
      throw const WalletCancelled(
        'Wallet signing is Android-only. Mobile Wallet Adapter has no iOS '
        'equivalent, so this build can show the app but cannot connect a '
        'wallet or move funds.',
      );
    }
    try {
      return await action();
    } on WalletCancelled {
      rethrow;
    } on Object catch (error) {
      if (_looksLikeNoWallet(error)) {
        throw const WalletCancelled(
          'No Solana wallet app is installed. Escrow Pay signs through a '
          'wallet, so you need one before you can connect.',
          noWalletInstalled: true,
        );
      }
      throw WalletCancelled(_readable(error));
    }
  }

  /// MWA launches the wallet through an intent. With nothing installed to
  /// handle it, Android reports no matching activity — which arrives here
  /// under a few different names depending on the layer that caught it.
  static bool _looksLikeNoWallet(Object error) {
    final text = error.toString();
    return text.contains('NoWalletFound') ||
        text.contains('ActivityNotFound') ||
        text.contains('No Activity found') ||
        text.contains('ERROR_WALLET_NOT_FOUND');
  }

  String _readable(Object error) {
    final text = error.toString();
    if (text.contains('timed out') || text.contains('Timeout')) {
      return 'The wallet did not respond in time. Try again.';
    }
    if (text.contains('declined') || text.contains('Cancel')) {
      return 'Request declined in the wallet.';
    }
    return text;
  }
}
