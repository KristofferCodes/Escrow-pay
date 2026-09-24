use anchor_lang::prelude::*;

/// Lifecycle of a single escrow. Four states, exactly as scoped for v1:
/// `Created -> Funded -> Released`, or `Created -> Funded -> Refunded`.
/// Arbitration/dispute is deliberately out of scope.
///
/// Borsh encodes this as a single byte holding the variant index, so the order
/// of these variants is wire format. `EscrowState` in
/// `lib/core/escrow.dart` mirrors it and reads that byte directly — reordering
/// here silently misreads every account in the app.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug)]
pub enum EscrowState {
    /// PDA exists, terms are locked in, no funds moved yet.
    Created,
    /// Buyer's lamports are held by the PDA.
    Funded,
    /// Buyer confirmed receipt; funds went to the seller.
    Released,
    /// Buyer backed out before confirming; funds went back to the buyer.
    Refunded,
}

/// The escrow itself. A PDA at
/// `[b"escrow", seller, buyer, nonce]` that custodies the buyer's funds.
/// Neither party can move lamports out of it directly — only this program can.
#[account]
pub struct EscrowAccount {
    /// Receives the funds on `confirm_receipt`. Taken from the seller's QR code.
    pub seller: Pubkey,
    /// Funds the escrow and is the only account allowed to release or refund.
    pub buyer: Pubkey,
    /// Lamports held on top of rent. Fixed at `initialize_escrow`.
    pub amount: u64,
    /// Current lifecycle position.
    pub state: EscrowState,
    /// Unix timestamp of `initialize_escrow`.
    pub created_at: i64,
    /// Distinguishes repeat trades between the same two wallets.
    pub nonce: u64,
    /// Cached PDA bump so the program can sign without re-deriving.
    pub bump: u8,
}

impl EscrowAccount {
    pub const SEED_PREFIX: &'static [u8] = b"escrow";

    /// Anchor's account discriminator.
    pub const DISCRIMINATOR_LEN: usize = 8;

    /// Serialized body, spelled out rather than derived.
    ///
    /// The Dart client decodes these bytes by offset instead of parsing an IDL
    /// (see `Escrow.decode`), so the layout is a contract between the two
    /// codebases and is worth stating in full here.
    pub const BODY_LEN: usize = 32 // seller
        + 32 // buyer
        + 8  // amount
        + 1  // state
        + 8  // created_at
        + 8  // nonce
        + 1; // bump

    /// What `init` must allocate.
    pub const LEN: usize = Self::DISCRIMINATOR_LEN + Self::BODY_LEN;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Guards the layout the Dart decoder depends on. If a field is added here
    /// without updating `BODY_LEN`, this fails before anything is deployed.
    #[test]
    fn body_len_matches_serialized_size() {
        let account = EscrowAccount {
            seller: Pubkey::new_unique(),
            buyer: Pubkey::new_unique(),
            amount: u64::MAX,
            state: EscrowState::Refunded,
            created_at: i64::MIN,
            nonce: u64::MAX,
            bump: 255,
        };

        let mut encoded = Vec::new();
        account.serialize(&mut encoded).unwrap();

        assert_eq!(encoded.len(), EscrowAccount::BODY_LEN);
        assert_eq!(EscrowAccount::LEN, 98);
    }
}
