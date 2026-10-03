import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solana_kit/solana_kit.dart';

import '../core/escrow.dart';
import '../core/qr_payload.dart';
import '../core/release_code.dart';
import 'escrow_repository.dart';
import 'release_code_store.dart';
import 'wallet.dart';
import 'wallet_controller.dart';

/// Everything the status screen renders.
class EscrowView {
  const EscrowView({
    this.address,
    this.escrow,
    this.offer,
    this.loading = false,
    this.busy = false,
    this.error,
    this.lastSignature,
    this.confirmToken,
    this.releaseCode,
    this.showingReleaseCode = false,
  });

  /// The PDA, known as soon as the buyer scans — before the account exists.
  final Address? address;

  /// Null until the account has been created onchain.
  final Escrow? escrow;

  /// The scanned terms. Lets the screen show the amount and item before there
  /// is anything onchain to read.
  final EscrowOffer? offer;

  final bool loading;

  /// A wallet round trip is in flight.
  final bool busy;
  final String? error;
  final String? lastSignature;

  /// Changes each time a transaction confirms, which is what fires the
  /// particle burst. A token rather than a flag, so two confirmations in a row
  /// both play.
  final Object? confirmToken;

  /// The buyer's secret for this escrow, if this device holds it. Null after
  /// a reinstall or on another phone, which hides the code option rather than
  /// offering one that cannot work.
  final ReleaseCode? releaseCode;

  /// Whether the handover QR is currently on screen.
  final bool showingReleaseCode;

  /// The code is only meaningful while funds are actually held.
  bool get canShowReleaseCode =>
      releaseCode != null &&
      escrow?.state == EscrowState.funded &&
      (escrow?.hasReleaseCode ?? false);

  EscrowState get state => escrow?.state ?? EscrowState.created;

  /// Lamports, from the chain when available and from the scanned offer until
  /// then.
  int get amount => escrow?.amount ?? offer?.lamports ?? 0;

  String? get seller => escrow?.seller ?? offer?.seller;

  bool get canConfirm => escrow?.state == EscrowState.funded && !busy;
  bool get canRefund => escrow?.state == EscrowState.funded && !busy;

  EscrowView copyWith({
    Address? address,
    Escrow? escrow,
    EscrowOffer? offer,
    bool? loading,
    bool? busy,
    String? error,
    String? lastSignature,
    Object? confirmToken,
    ReleaseCode? releaseCode,
    bool? showingReleaseCode,
    bool clearError = false,
  }) => EscrowView(
    address: address ?? this.address,
    escrow: escrow ?? this.escrow,
    offer: offer ?? this.offer,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: clearError ? null : (error ?? this.error),
    lastSignature: lastSignature ?? this.lastSignature,
    confirmToken: confirmToken ?? this.confirmToken,
    releaseCode: releaseCode ?? this.releaseCode,
    showingReleaseCode: showingReleaseCode ?? this.showingReleaseCode,
  );
}

/// Drives one escrow from scan through settlement.
///
/// Each action follows the same arc: mark busy, hand the transaction to the
/// wallet, then poll the account until the chain agrees. The poll is the part
/// that matters — `signAndSendTransactions` returns as soon as the wallet has
/// submitted, which is well before the state the user is waiting to see.
class EscrowController extends Notifier<EscrowView> {
  @override
  EscrowView build() => const EscrowView();

  EscrowRepository get _repo => ref.read(escrowRepositoryProvider);
  WalletController get _wallet => ref.read(walletControllerProvider.notifier);

  /// Called when the buyer scans a QR code. Derives the PDA and looks it up, so
  /// rescanning an escrow that is already funded picks up where it left off
  /// rather than trying to open it twice.
  Future<void> adopt(EscrowOffer offer) async {
    state = EscrowView(offer: offer, loading: true);

    final session = await _wallet.require();
    if (session == null) {
      state = state.copyWith(
        loading: false,
        error:
            ref.read(walletControllerProvider).error ?? 'Wallet not connected.',
      );
      return;
    }

    try {
      final (address, _) = await _repo.derive(
        seller: Address(offer.seller),
        buyer: session.address,
        nonce: offer.nonce,
      );
      final existing = await _repo.fetch(address);
      state = state.copyWith(
        address: address,
        escrow: existing,
        loading: false,
      );
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: _readable(error));
    }
  }

  /// Opens and funds the escrow in one signature.
  Future<void> fund() async {
    final offer = state.offer;
    if (offer == null || state.busy) return;

    // Generated here, before anything is signed, so the hash that goes
    // onchain and the secret that stays on this device come from one place.
    final code = ReleaseCode.generate();

    await _run(
      target: EscrowState.funded,
      action: () async {
        final session = await _requireWallet();
        if (session == null) return null;

        final submission = await _repo.openAndFund(
          session: session,
          offer: offer,
          releaseHash: code.hash,
        );
        state = state.copyWith(address: submission.escrow);

        // Persist before confirming: if the app dies waiting on the chain,
        // the escrow still exists and the secret is the only way to release
        // it by code.
        await ref
            .read(releaseCodeStoreProvider)
            .save(submission.escrow.value, code);
        state = state.copyWith(releaseCode: code);

        final settled = await _repo.awaitState(
          submission.escrow,
          target: EscrowState.funded,
        );
        return (settled, submission.signature);
      },
    );
  }

  /// Releases the escrow to the seller.
  Future<void> confirmReceipt() => _settle(
    action: (session, escrow) =>
        _repo.confirmReceipt(session: session, escrow: escrow),
    target: EscrowState.released,
  );

  /// Returns the escrow to the buyer.
  Future<void> refund() => _settle(
    action: (session, escrow) => _repo.refund(session: session, escrow: escrow),
    target: EscrowState.refunded,
  );

  /// Re-reads the account. Used by pull to refresh and after an error.
  Future<void> reload() async {
    final address = state.address;
    if (address == null) return;

    state = state.copyWith(loading: true, clearError: true);
    try {
      final escrow = await _repo.fetch(address);
      state = state.copyWith(escrow: escrow, loading: false);
    } on Object catch (error) {
      state = state.copyWith(loading: false, error: _readable(error));
    }
  }

  /// Shown only after the buyer confirms they have inspected the item.
  void showReleaseCode() => state = state.copyWith(showingReleaseCode: true);

  void hideReleaseCode() => state = state.copyWith(showingReleaseCode: false);

  void clear() => state = const EscrowView();

  void clearError() => state = state.copyWith(clearError: true);

  Future<void> _settle({
    required Future<String> Function(WalletSession, Escrow) action,
    required EscrowState target,
  }) async {
    final escrow = state.escrow;
    if (escrow == null || state.busy) return;

    await _run(
      target: target,
      action: () async {
        final session = await _requireWallet();
        if (session == null) return null;

        final signature = await action(session, escrow);
        final settled = await _repo.awaitState(
          Address(escrow.address),
          target: target,
        );
        return (settled, signature);
      },
    );
  }

  Future<WalletSession?> _requireWallet() async {
    final session = await _wallet.require();
    if (session == null) {
      state = state.copyWith(
        busy: false,
        error:
            ref.read(walletControllerProvider).error ?? 'Wallet not connected.',
      );
    }
    return session;
  }

  /// Shared busy/error/confirm bookkeeping for the three mutating actions.
  ///
  /// [target] is the state the chain is expected to land in. The confirmation
  /// token only fires when it actually got there: `awaitState` gives up after
  /// its timeout and returns whatever it last read, so firing unconditionally
  /// would play the burst and the haptic for a transaction that is still in
  /// flight — or that failed.
  Future<void> _run({
    required EscrowState target,
    required Future<(Escrow?, String)?> Function() action,
  }) async {
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await action();
      if (result == null) {
        // The wallet step bailed out and has already set its own message.
        state = state.copyWith(busy: false);
        return;
      }

      final (escrow, signature) = result;
      final confirmed = escrow?.state == target;

      state = state.copyWith(
        escrow: escrow,
        busy: false,
        lastSignature: signature,
        confirmToken: confirmed ? DateTime.now().microsecondsSinceEpoch : null,
        error: confirmed
            ? null
            : 'Submitted, but the cluster has not confirmed it yet. Pull down '
                  'to refresh.',
        clearError: confirmed,
      );
    } on Object catch (error) {
      state = state.copyWith(busy: false, error: _readable(error));
    }
  }

  String _readable(Object error) {
    if (error is WalletCancelled) return error.message;

    final text = error.toString();
    // Surface the program's own error names rather than a raw simulation dump.
    if (text.contains('InvalidState')) {
      return 'This escrow has already moved on. Pull down to refresh.';
    }
    if (text.contains('InsufficientFunds') || text.contains('insufficient')) {
      return 'Not enough SOL in the wallet to cover the amount plus fees.';
    }
    if (text.contains('ConstraintSeeds')) {
      return 'The escrow address did not match. Check the program id is in '
          'sync with the deployed program.';
    }
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return 'Could not reach the cluster. Check the connection and retry.';
    }
    return text;
  }
}

final escrowControllerProvider = NotifierProvider<EscrowController, EscrowView>(
  EscrowController.new,
);
