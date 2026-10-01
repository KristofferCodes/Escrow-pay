use anchor_lang::prelude::*;

#[error_code]
pub enum EscrowError {
    #[msg("Escrow is not in the state this instruction requires")]
    InvalidState,
    #[msg("Escrow amount must be greater than zero")]
    ZeroAmount,
    #[msg("Buyer and seller must be different wallets")]
    SameParty,
    #[msg("Buyer does not hold enough lamports to fund this escrow")]
    InsufficientFunds,
    #[msg("Escrow PDA does not hold the lamports it claims to")]
    VaultUnderfunded,
    #[msg("Timeout must be between 1 hour and 30 days")]
    TimeoutOutOfRange,
    #[msg("The refund window has closed; the seller can now claim")]
    RefundWindowClosed,
    #[msg("The refund window is still open; the buyer may still refund")]
    DeadlineNotReached,
}
