use anchor_lang::prelude::*;

/// Lifecycle of a single escrow. Four states, exactly as scoped for v1:
/// `Created -> Funded -> Released`, or `Created -> Funded -> Refunded`.
/// Arbitration/dispute is deliberately out of scope.
#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug, InitSpace)]
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
#[derive(InitSpace)]
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
}
