import 'dart:convert';
import 'dart:typed_data';

import 'package:solana_kit/solana_kit.dart';
import 'package:solana_kit_rpc_api/solana_kit_rpc_api.dart';

import '../core/escrow.dart';
import '../core/qr_payload.dart';
import 'cluster.dart';
import 'escrow_program.dart';
import 'wallet.dart';

/// Reads escrow state from the cluster and turns user intents into signed,
/// submitted transactions.
///
/// Every mutating method follows the same shape: derive the PDA, assemble the
/// instructions, compile against a fresh blockhash, then hand the base64 wire
/// transaction to the wallet. Nothing is cached — an escrow's state is the
/// chain's to decide.
class EscrowRepository {
  EscrowRepository({required this.cluster, required this.wallet});

  final Cluster cluster;
  final WalletService wallet;

  /// Typed via inference: the concrete `Rpc` class lives in
  /// `solana_kit_rpc_spec`, which the umbrella package does not re-export.
  late final _rpc = createSolanaRpc(url: cluster.rpcUrl);

  Future<ProgramDerivedAddress> derive({
    required Address seller,
    required Address buyer,
    required int nonce,
  }) => EscrowProgram.deriveEscrow(seller: seller, buyer: buyer, nonce: nonce);

  /// Returns `null` when the account does not exist yet — the normal state
  /// between a seller generating a QR and a buyer funding it.
  Future<Escrow?> fetch(Address escrow) async {
    final response = await _rpc
        .getAccountInfoValue(
          escrow,
          const GetAccountInfoConfig(encoding: AccountEncoding.base64),
        )
        .send();

    final account = response.value;
    if (account == null) return null;

    final data = account['data'];
    if (data is! List || data.isEmpty) return null;

    final Uint8List bytes;
    try {
      bytes = base64Decode(data.first! as String);
    } on FormatException {
      return null;
    }

    return Escrow.decode(
      address: escrow.value,
      data: bytes,
      encodeAddress: (key) => getAddressFromPublicKey(key).value,
    );
  }

  /// Opens the escrow and funds it in a single transaction, so the buyer
  /// approves one signature rather than two and cannot end up stranded with an
  /// initialised-but-unfunded escrow.
  Future<EscrowSubmission> openAndFund({
    required WalletSession session,
    required EscrowOffer offer,
  }) async {
    final seller = Address(offer.seller);
    late Address escrowAddress;

    final signature = await wallet.signAndSend(
      session: session,
      buildBase64Transaction: (buyer) async {
        final (escrow, _) = await derive(
          seller: seller,
          buyer: buyer,
          nonce: offer.nonce,
        );
        escrowAddress = escrow;

        return _compile(
          feePayer: buyer,
          instructions: [
            EscrowProgram.initializeEscrow(
              escrow: escrow,
              buyer: buyer,
              seller: seller,
              nonce: offer.nonce,
              lamports: offer.lamports,
            ),
            EscrowProgram.deposit(escrow: escrow, buyer: buyer),
          ],
        );
      },
    );

    return EscrowSubmission(signature: signature, escrow: escrowAddress);
  }

  /// Buyer confirms the goods arrived; the program pays the seller.
  Future<String> confirmReceipt({
    required WalletSession session,
    required Escrow escrow,
  }) => wallet.signAndSend(
    session: session,
    buildBase64Transaction: (buyer) => _compile(
      feePayer: buyer,
      instructions: [
        EscrowProgram.confirmReceipt(
          escrow: Address(escrow.address),
          buyer: buyer,
          seller: Address(escrow.seller),
        ),
      ],
    ),
  );

  /// Buyer pulls out before confirming; the program pays the buyer back.
  Future<String> refund({
    required WalletSession session,
    required Escrow escrow,
  }) => wallet.signAndSend(
    session: session,
    buildBase64Transaction: (buyer) => _compile(
      feePayer: buyer,
      instructions: [
        EscrowProgram.refund(escrow: Address(escrow.address), buyer: buyer),
      ],
    ),
  );

  /// Polls until the escrow reaches [target], or gives up.
  ///
  /// `signAndSendTransactions` returns once the wallet has submitted, which is
  /// ahead of the account actually reflecting the change. Re-reading the
  /// account is what the status screen trusts.
  Future<Escrow?> awaitState(
    Address escrow, {
    required EscrowState target,
    Duration timeout = const Duration(seconds: 45),
    Duration interval = const Duration(milliseconds: 900),
  }) async {
    final deadline = DateTime.now().add(timeout);
    Escrow? last;

    while (DateTime.now().isBefore(deadline)) {
      last = await fetch(escrow);
      if (last?.state == target) return last;
      await Future<void>.delayed(interval);
    }
    return last;
  }

  Future<String> _compile({
    required Address feePayer,
    required List<Instruction> instructions,
  }) async {
    final blockhash = await _rpc.getLatestBlockhashValue().send();

    final message = createTransactionMessage(version: TransactionVersion.v0)
        .withFeePayer(feePayer)
        .withBlockhashLifetime(
          BlockhashLifetimeConstraint(
            blockhash: blockhash.value.blockhash.value,
            lastValidBlockHeight: blockhash.value.lastValidBlockHeight,
          ),
        )
        .appendInstructions(instructions);

    return getBase64EncodedWireTransaction(compileTransaction(message));
  }
}

/// The result of opening an escrow: what was signed, and where it lives.
class EscrowSubmission {
  const EscrowSubmission({required this.signature, required this.escrow});
  final String signature;
  final Address escrow;
}
