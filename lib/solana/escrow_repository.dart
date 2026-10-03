import 'dart:convert';
import 'dart:typed_data';

import 'package:solana_kit/solana_kit.dart';
import 'package:solana_kit_rpc_api/solana_kit_rpc_api.dart';

import '../core/escrow.dart';
import '../core/qr_payload.dart';
import 'cluster.dart';
import 'escrow_program.dart';
import 'rpc_retry_client.dart';
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
  ///
  /// Every call goes through [RpcRetryClient], so a throttled endpoint costs a
  /// few hundred milliseconds rather than surfacing as a failed escrow.
  late final _rpc = createSolanaRpc(
    url: cluster.rpcUrl,
    client: RpcRetryClient(),
  );

  /// `getProgramAccounts` is expensive to serve and several providers gate it
  /// — Alchemy's free tier refuses it outright — so history falls back to the
  /// public endpoint, which does serve it. Only built when there is a custom
  /// endpoint that might refuse.
  late final _fallbackRpc = cluster.usesCustomRpc
      ? createSolanaRpc(url: cluster.defaultRpcUrl, client: RpcRetryClient())
      : null;

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
    required Uint8List releaseHash,
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
              timeoutSeconds: offer.timeoutSeconds,
              releaseHash: releaseHash,
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

  /// Releases to the seller by presenting the buyer's secret.
  ///
  /// Submitted by whoever scanned the code. The connected wallet only pays
  /// the fee — the program decides the destination.
  Future<String> releaseWithCode({
    required WalletSession session,
    required Escrow escrow,
    required Uint8List secret,
  }) => wallet.signAndSend(
    session: session,
    buildBase64Transaction: (payer) => _compile(
      feePayer: payer,
      instructions: [
        EscrowProgram.releaseWithCode(
          escrow: Address(escrow.address),
          seller: Address(escrow.seller),
          payer: payer,
          secret: secret,
        ),
      ],
    ),
  );

  /// Seller takes the funds once the refund window has closed.
  Future<String> claim({
    required WalletSession session,
    required Escrow escrow,
  }) => wallet.signAndSend(
    session: session,
    buildBase64Transaction: (seller) => _compile(
      feePayer: seller,
      instructions: [
        EscrowProgram.claim(escrow: Address(escrow.address), seller: seller),
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

  /// Every escrow this wallet is party to, newest first.
  ///
  /// Read straight off the chain rather than from local storage, so history
  /// follows the wallet to a new device and cannot drift from what actually
  /// happened. Two queries — one where the wallet is the buyer, one where it
  /// is the seller — because `memcmp` cannot express "or".
  Future<List<Escrow>> history(Address wallet) async {
    final results = await Future.wait([
      _accountsWhere(offset: _buyerOffset, equals: wallet),
      _accountsWhere(offset: _sellerOffset, equals: wallet),
    ]);

    // A wallet can be both parties only in a malformed escrow, but dedupe
    // anyway so the list never shows the same PDA twice.
    final byAddress = <String, Escrow>{};
    for (final escrow in results.expand((list) => list)) {
      byAddress[escrow.address] = escrow;
    }

    final all = byAddress.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  /// Field offsets inside `EscrowAccount`, after the 8-byte discriminator.
  /// Mirrors the layout in `Escrow.decode` and `EscrowAccount::BODY_LEN`.
  static const _sellerOffset = 8;
  static const _buyerOffset = 8 + 32;

  Future<List<Escrow>> _accountsWhere({
    required int offset,
    required Address equals,
  }) async {
    final params = <Object?>[
      EscrowProgram.programId.value,
      {
        'encoding': 'base64',
        'filters': [
          // Cheap pre-filter: anything of a different size is not ours.
          {'dataSize': Escrow.encodedLength},
          {
            'memcmp': {'offset': offset, 'bytes': equals.value},
          },
        ],
      },
    ];

    List<Object?> response;
    try {
      response = await _rpc
          .request<List<Object?>>('getProgramAccounts', params)
          .send();
    } on Object catch (error) {
      final fallback = _fallbackRpc;
      if (fallback == null || !_isMethodUnavailable(error)) rethrow;

      response = await fallback
          .request<List<Object?>>('getProgramAccounts', params)
          .send();
    }

    final escrows = <Escrow>[];
    for (final entry in response) {
      if (entry is! Map) continue;

      final address = entry['pubkey'];
      final account = entry['account'];
      if (address is! String || account is! Map) continue;

      final data = account['data'];
      if (data is! List || data.isEmpty) continue;

      final Uint8List bytes;
      try {
        bytes = base64Decode(data.first! as String);
      } on FormatException {
        continue;
      }

      final escrow = Escrow.decode(
        address: address,
        data: bytes,
        encodeAddress: (key) => getAddressFromPublicKey(key).value,
      );
      if (escrow != null) escrows.add(escrow);
    }
    return escrows;
  }

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

  /// Distinguishes "this provider will not serve the method" from a genuine
  /// failure. Only the former is worth retrying somewhere else.
  static bool _isMethodUnavailable(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('not available') ||
        text.contains('not supported') ||
        text.contains('unsupported') ||
        text.contains('method not found') ||
        text.contains('disabled');
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
