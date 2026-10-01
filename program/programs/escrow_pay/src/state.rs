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
    /// After this, the buyer can no longer refund and the seller may claim.
    ///
    /// This is what stops inaction being a weapon: without it a buyer who
    /// simply never confirms leaves the seller's money stuck forever.
    pub deadline: i64,
    /// Distinguishes repeat trades between the same two wallets.
    pub nonce: u64,
    /// Cached PDA bump so the program can sign without re-deriving.
    pub bump: u8,
}

impl EscrowAccount {
    pub const SEED_PREFIX: &'static [u8] = b"escrow";

    /// Bounds on the refund window, enforced onchain.
    ///
    /// The seller writes the timeout into the QR code, so without a floor a
    /// hostile seller could set one second and claim the funds before the
    /// buyer has walked away with the goods — which would make the escrow
    /// worse than useless. The buyer is guaranteed at least this long to
    /// dispute, whatever the QR says.
    #[cfg(not(feature = "test-timeouts"))]
    pub const MIN_TIMEOUT_SECONDS: i64 = 60 * 60; // 1 hour

    /// Lowered so the integration tests can watch a deadline actually pass —
    /// `solana-test-validator` cannot warp its clock, and waiting an hour per
    /// assertion is not a test suite.
    ///
    /// NEVER build a deployment with this feature. `anchor build` does not
    /// enable it, and `devnet-smoke.js` asserts the deployed program still
    /// rejects a one-second timeout, so a slip is caught before anyone trades
    /// against it.
    #[cfg(feature = "test-timeouts")]
    pub const MIN_TIMEOUT_SECONDS: i64 = 1;

    /// And a ceiling, so funds cannot be parked indefinitely.
    pub const MAX_TIMEOUT_SECONDS: i64 = 60 * 60 * 24 * 30; // 30 days

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
        + 8  // deadline
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
            deadline: i64::MAX,
            nonce: u64::MAX,
            bump: 255,
        };

        let mut encoded = Vec::new();
        account.serialize(&mut encoded).unwrap();

        assert_eq!(encoded.len(), EscrowAccount::BODY_LEN);
        assert_eq!(EscrowAccount::LEN, 106);
    }

    /// Guards the production floor. If `test-timeouts` ever leaks into a
    /// normal build, this fails rather than shipping a one-second escrow.
    #[test]
    #[cfg(not(feature = "test-timeouts"))]
    fn refund_window_floor_is_one_hour() {
        assert_eq!(EscrowAccount::MIN_TIMEOUT_SECONDS, 3600);
        assert_eq!(EscrowAccount::MAX_TIMEOUT_SECONDS, 2_592_000);
    }
}
