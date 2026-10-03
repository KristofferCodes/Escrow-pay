import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:solana_kit/solana_kit.dart';

/// Client-side bindings for the `escrow_pay` Anchor program.
///
/// Anchor's IDL is not consumed at runtime here: the program has four
/// instructions with fixed layouts, so hand-rolling the encoders keeps the app
/// free of a codegen step and makes the wire format visible at the call site.
/// The trade-off is that this file and `program/programs/escrow_pay/src` have
/// to be changed together.
abstract final class EscrowProgram {
  /// Must match `declare_id!` in the program. Kept on its own line so
  /// `scripts/sync_program_id.sh` can rewrite it after a deploy.
  static const programIdBase58 = '5pY9AH8qYE6u17MYknPeoy9HufpguEAt9Lj1vnoXqzNC';

  static const programId = Address(programIdBase58);

  static const systemProgramId = Address('11111111111111111111111111111111');

  static const _seedPrefix = 'escrow';

  /// Anchor prefixes every instruction with the first eight bytes of
  /// `sha256("global:<instruction_name>")`.
  static Uint8List discriminator(String instruction) {
    final digest = sha256.convert(utf8.encode('global:$instruction'));
    return Uint8List.fromList(digest.bytes.sublist(0, 8));
  }

  /// `[b"escrow", seller, buyer, nonce]` — identical to the `seeds` constraint
  /// in the program. Any drift here shows up as `ConstraintSeeds`.
  static Future<ProgramDerivedAddress> deriveEscrow({
    required Address seller,
    required Address buyer,
    required int nonce,
  }) => getProgramDerivedAddress(
    programAddress: programId,
    seeds: [
      Uint8List.fromList(utf8.encode(_seedPrefix)),
      getPublicKeyFromAddress(seller),
      getPublicKeyFromAddress(buyer),
      _u64(nonce),
    ],
  );

  /// Opens the escrow. Signed by the buyer — see the note on
  /// `initialize_escrow` in the program for why the seller is not a signer.
  static Instruction initializeEscrow({
    required Address escrow,
    required Address buyer,
    required Address seller,
    required int nonce,
    required int lamports,
    required int timeoutSeconds,
    required Uint8List releaseHash,
  }) => Instruction(
    programAddress: programId,
    accounts: [
      AccountMeta(address: escrow, role: AccountRole.writable),
      AccountMeta(address: buyer, role: AccountRole.writableSigner),
      AccountMeta(address: seller, role: AccountRole.readonly),
      AccountMeta(address: systemProgramId, role: AccountRole.readonly),
    ],
    data: _concat([
      discriminator('initialize_escrow'),
      _u64(nonce),
      _u64(lamports),
      _i64(timeoutSeconds),
      // Fixed 32 bytes, so no length prefix.
      releaseHash,
    ]),
  );

  /// Moves the agreed amount into the escrow PDA.
  static Instruction deposit({
    required Address escrow,
    required Address buyer,
  }) => Instruction(
    programAddress: programId,
    accounts: [
      AccountMeta(address: escrow, role: AccountRole.writable),
      AccountMeta(address: buyer, role: AccountRole.writableSigner),
      AccountMeta(address: systemProgramId, role: AccountRole.readonly),
    ],
    data: discriminator('deposit'),
  );

  /// Releases the escrow to the seller.
  static Instruction confirmReceipt({
    required Address escrow,
    required Address buyer,
    required Address seller,
  }) => Instruction(
    programAddress: programId,
    accounts: [
      AccountMeta(address: escrow, role: AccountRole.writable),
      AccountMeta(address: buyer, role: AccountRole.writableSigner),
      AccountMeta(address: seller, role: AccountRole.writable),
    ],
    data: discriminator('confirm_receipt'),
  );

  /// Releases to the seller by presenting the buyer's secret.
  ///
  /// [payer] only covers the fee — it has no authority here. The payout is
  /// pinned to the recorded seller by the program, which is what lets a
  /// courier submit this without being trusted.
  static Instruction releaseWithCode({
    required Address escrow,
    required Address seller,
    required Address payer,
    required Uint8List secret,
  }) => Instruction(
    programAddress: programId,
    accounts: [
      AccountMeta(address: escrow, role: AccountRole.writable),
      AccountMeta(address: seller, role: AccountRole.writable),
      AccountMeta(address: payer, role: AccountRole.writableSigner),
    ],
    data: _concat([discriminator('release_with_code'), secret]),
  );

  /// Seller takes the funds once the refund window has closed. The only
  /// instruction the seller can call.
  static Instruction claim({
    required Address escrow,
    required Address seller,
  }) => Instruction(
    programAddress: programId,
    accounts: [
      AccountMeta(address: escrow, role: AccountRole.writable),
      AccountMeta(address: seller, role: AccountRole.writableSigner),
    ],
    data: discriminator('claim'),
  );

  /// Returns the escrow to the buyer.
  static Instruction refund({
    required Address escrow,
    required Address buyer,
  }) => Instruction(
    programAddress: programId,
    accounts: [
      AccountMeta(address: escrow, role: AccountRole.writable),
      AccountMeta(address: buyer, role: AccountRole.writableSigner),
    ],
    data: discriminator('refund'),
  );

  static Uint8List _i64(int value) {
    final bytes = ByteData(8)..setInt64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static Uint8List _u64(int value) {
    final bytes = ByteData(8)..setUint64(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static Uint8List _concat(List<Uint8List> chunks) {
    final total = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final out = Uint8List(total);
    var offset = 0;
    for (final chunk in chunks) {
      out.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return out;
  }
}
