import 'dart:typed_data';

/// Mirrors `EscrowState` in the onchain program. The ordinals are part of the
/// wire format — reordering this enum silently misreads every account.
enum EscrowState {
  created,
  funded,
  released,
  refunded;

  static EscrowState? fromOrdinal(int value) =>
      value >= 0 && value < values.length ? values[value] : null;

  String get label => switch (this) {
    EscrowState.created => 'Awaiting funds',
    EscrowState.funded => 'In escrow',
    EscrowState.released => 'Released to seller',
    EscrowState.refunded => 'Refunded to buyer',
  };

  /// One line telling the current user what happens next.
  String get blurb => switch (this) {
    EscrowState.created => 'The escrow is open. Fund it to lock in the trade.',
    EscrowState.funded =>
      'Funds are held by the program. Neither wallet can touch them.',
    EscrowState.released => 'The seller has been paid. This trade is closed.',
    EscrowState.refunded => 'The buyer was paid back. This trade is closed.',
  };

  /// Terminal states cannot transition again.
  bool get isSettled =>
      this == EscrowState.released || this == EscrowState.refunded;

  String get key => name;
}

/// A decoded `EscrowAccount`.
class Escrow {
  const Escrow({
    required this.address,
    required this.seller,
    required this.buyer,
    required this.amount,
    required this.state,
    required this.createdAt,
    required this.nonce,
    required this.bump,
  });

  /// Byte layout of `EscrowAccount`, after the 8-byte Anchor discriminator:
  /// seller(32) buyer(32) amount(u64) state(u8) created_at(i64) nonce(u64)
  /// bump(u8).
  static const _discriminatorLength = 8;
  static const encodedLength =
      _discriminatorLength + 32 + 32 + 8 + 1 + 8 + 8 + 1;

  final String address;
  final String seller;
  final String buyer;
  final int amount;
  final EscrowState state;
  final DateTime createdAt;
  final int nonce;
  final int bump;

  /// Decodes raw account data. Returns `null` rather than throwing when the
  /// bytes are not an escrow — an address collision or a stale program id
  /// should surface as "not found", not as a crash mid-demo.
  static Escrow? decode({
    required String address,
    required Uint8List data,
    required String Function(Uint8List) encodeAddress,
  }) {
    if (data.length < encodedLength) return null;

    final view = ByteData.sublistView(data);
    var offset = _discriminatorLength;

    String readPubkey() {
      final bytes = Uint8List.sublistView(data, offset, offset + 32);
      offset += 32;
      return encodeAddress(bytes);
    }

    final seller = readPubkey();
    final buyer = readPubkey();

    final amount = view.getUint64(offset, Endian.little);
    offset += 8;

    final state = EscrowState.fromOrdinal(view.getUint8(offset));
    offset += 1;
    if (state == null) return null;

    final createdAt = view.getInt64(offset, Endian.little);
    offset += 8;

    final nonce = view.getUint64(offset, Endian.little);
    offset += 8;

    final bump = view.getUint8(offset);

    return Escrow(
      address: address,
      seller: seller,
      buyer: buyer,
      amount: amount,
      state: state,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        createdAt * 1000,
        isUtc: true,
      ).toLocal(),
      nonce: nonce,
      bump: bump,
    );
  }

  Escrow copyWith({EscrowState? state}) => Escrow(
    address: address,
    seller: seller,
    buyer: buyer,
    amount: amount,
    state: state ?? this.state,
    createdAt: createdAt,
    nonce: nonce,
    bump: bump,
  );
}
