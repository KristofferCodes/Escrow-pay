import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cluster.dart';
import 'escrow_repository.dart';
import 'wallet.dart';

final clusterProvider = Provider<Cluster>((ref) => Cluster.active);

final walletServiceProvider = Provider<WalletService>(
  (ref) => WalletService(cluster: ref.watch(clusterProvider)),
);

final escrowRepositoryProvider = Provider<EscrowRepository>(
  (ref) => EscrowRepository(
    cluster: ref.watch(clusterProvider),
    wallet: ref.watch(walletServiceProvider),
  ),
);

/// Whether a wallet is attached, and anything that went wrong attaching one.
class WalletState {
  const WalletState({this.session, this.connecting = false, this.error});

  final WalletSession? session;
  final bool connecting;
  final String? error;

  bool get isConnected => session != null;

  WalletState copyWith({
    WalletSession? session,
    bool? connecting,
    String? error,
    bool clearError = false,
    bool clearSession = false,
  }) => WalletState(
    session: clearSession ? null : (session ?? this.session),
    connecting: connecting ?? this.connecting,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Owns the wallet connection for the whole app.
///
/// The session lives only as long as the process. Persisting the auth token
/// would skip the approval sheet on relaunch, but it also means a stale token
/// can silently fail mid-demo — not a trade worth making before the token is
/// stored somewhere encrypted.
class WalletController extends Notifier<WalletState> {
  @override
  WalletState build() => const WalletState();

  WalletService get _wallet => ref.read(walletServiceProvider);

  bool get isSupported => _wallet.isSupported;

  Future<WalletSession?> connect() async {
    if (state.connecting) return state.session;
    state = state.copyWith(connecting: true, clearError: true);

    try {
      final session = await _wallet.connect();
      state = WalletState(session: session);
      return session;
    } on WalletCancelled catch (error) {
      state = state.copyWith(connecting: false, error: error.message);
      return null;
    }
  }

  /// Returns the live session, prompting for one if the user has not connected
  /// yet. Lets action handlers treat "connect" as an implementation detail.
  Future<WalletSession?> require() async => state.session ?? await connect();

  Future<void> disconnect() async {
    final session = state.session;
    state = const WalletState();
    if (session != null) await _wallet.disconnect(session);
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final walletControllerProvider =
    NotifierProvider<WalletController, WalletState>(WalletController.new);
