//! Escrow Pay — a trust-minimised P2P escrow for in-person resale.
//!
//! A seller advertises terms via a QR code. The buyer scans it, opens the
//! escrow and funds it in a single transaction. The lamports sit in a PDA that
//! neither party owns. When the goods change hands the buyer confirms receipt
//! and the program pays the seller; if the buyer backs out first, the program
//! pays the buyer back.
//!
//! v1 settles in native SOL. `EscrowAccount` is laid out so an SPL/USDC vault
//! can be added later without changing the PDA derivation.

use anchor_lang::prelude::*;
use anchor_lang::system_program::{transfer, Transfer};

pub mod errors;
pub mod state;

use errors::EscrowError;
use state::{EscrowAccount, EscrowState};

declare_id!("Fg6PaFpoGXkYsidMpWTK6W2BeZ7FEfcYkg476zPFsLnS");

#[program]
pub mod escrow_pay {
    use super::*;

    /// Opens the escrow with the terms encoded in the seller's QR code.
    ///
    /// Signed by the buyer, not the seller: the seller is offline at scan time
    /// and there is no backend to co-sign, so the seller's key is carried as
    /// data. The seller never has to trust the buyer here — no funds move until
    /// `deposit`, and the only account `confirm_receipt` can pay is the seller
    /// recorded right here.
    pub fn initialize_escrow(ctx: Context<InitializeEscrow>, nonce: u64, amount: u64) -> Result<()> {
        require!(amount > 0, EscrowError::ZeroAmount);
        require_keys_neq!(
            ctx.accounts.seller.key(),
            ctx.accounts.buyer.key(),
            EscrowError::SameParty
        );

        let escrow = &mut ctx.accounts.escrow;
        escrow.seller = ctx.accounts.seller.key();
        escrow.buyer = ctx.accounts.buyer.key();
        escrow.amount = amount;
        escrow.state = EscrowState::Created;
        escrow.created_at = Clock::get()?.unix_timestamp;
        escrow.nonce = nonce;
        escrow.bump = ctx.bumps.escrow;

        emit!(EscrowInitialized {
            escrow: escrow.key(),
            seller: escrow.seller,
            buyer: escrow.buyer,
            amount,
            nonce,
        });
        Ok(())
    }

    /// Moves the agreed amount from the buyer into the escrow PDA.
    ///
    /// Usually packed into the same transaction as `initialize_escrow`, so the
    /// buyer approves one signature in their wallet, not two.
    pub fn deposit(ctx: Context<Deposit>) -> Result<()> {
        let amount = ctx.accounts.escrow.amount;

        require!(
            ctx.accounts.escrow.state == EscrowState::Created,
            EscrowError::InvalidState
        );
        require!(
            ctx.accounts.buyer.lamports() >= amount,
            EscrowError::InsufficientFunds
        );

        // The buyer is a plain system account, so the System Program moves the
        // lamports. Paying out later cannot use this path — see `pay_out`.
        transfer(
            // Anchor 1.x takes the program id here, not its AccountInfo.
            CpiContext::new(
                ctx.accounts.system_program.key(),
                Transfer {
                    from: ctx.accounts.buyer.to_account_info(),
                    to: ctx.accounts.escrow.to_account_info(),
                },
            ),
            amount,
        )?;

        ctx.accounts.escrow.state = EscrowState::Funded;

        emit!(EscrowFunded {
            escrow: ctx.accounts.escrow.key(),
            amount,
        });
        Ok(())
    }

    /// Buyer confirms the goods arrived; the program pays the seller.
    pub fn confirm_receipt(ctx: Context<ConfirmReceipt>) -> Result<()> {
        require!(
            ctx.accounts.escrow.state == EscrowState::Funded,
            EscrowError::InvalidState
        );

        let amount = ctx.accounts.escrow.amount;
        pay_out(
            &ctx.accounts.escrow.to_account_info(),
            &ctx.accounts.seller,
            amount,
        )?;

        ctx.accounts.escrow.state = EscrowState::Released;

        emit!(EscrowReleased {
            escrow: ctx.accounts.escrow.key(),
            seller: ctx.accounts.escrow.seller,
            amount,
        });
        Ok(())
    }

    /// Buyer pulls out before confirming; the program pays the buyer back.
    pub fn refund(ctx: Context<Refund>) -> Result<()> {
        require!(
            ctx.accounts.escrow.state == EscrowState::Funded,
            EscrowError::InvalidState
        );

        let amount = ctx.accounts.escrow.amount;
        pay_out(
            &ctx.accounts.escrow.to_account_info(),
            &ctx.accounts.buyer.to_account_info(),
            amount,
        )?;

        ctx.accounts.escrow.state = EscrowState::Refunded;

        emit!(EscrowRefunded {
            escrow: ctx.accounts.escrow.key(),
            buyer: ctx.accounts.escrow.buyer,
            amount,
        });
        Ok(())
    }
}

/// Moves lamports out of the escrow PDA.
///
/// A System Program transfer cannot be used here: the source carries account
/// data, which the System Program rejects. Because the PDA belongs to this
/// program we debit and credit the lamport balances directly instead.
///
/// Only the escrowed `amount` moves — the rent deposit stays behind so the
/// account survives and the app can still show a settled escrow's history.
fn pay_out<'info>(
    escrow: &AccountInfo<'info>,
    recipient: &AccountInfo<'info>,
    amount: u64,
) -> Result<()> {
    let rent_floor = Rent::get()?.minimum_balance(escrow.data_len());
    let available = escrow.lamports().saturating_sub(rent_floor);
    require!(available >= amount, EscrowError::VaultUnderfunded);

    **escrow.try_borrow_mut_lamports()? -= amount;
    **recipient.try_borrow_mut_lamports()? += amount;
    Ok(())
}

#[derive(Accounts)]
#[instruction(nonce: u64)]
pub struct InitializeEscrow<'info> {
    #[account(
        init,
        payer = buyer,
        space = EscrowAccount::LEN,
        seeds = [
            EscrowAccount::SEED_PREFIX,
            seller.key().as_ref(),
            buyer.key().as_ref(),
            &nonce.to_le_bytes(),
        ],
        bump,
    )]
    pub escrow: Account<'info, EscrowAccount>,

    #[account(mut)]
    pub buyer: Signer<'info>,

    /// Read from the QR code and only ever recorded, never signed against.
    /// CHECK: no data is read from this account; it is stored as the payout
    /// destination and enforced by `has_one` on every instruction that pays.
    pub seller: UncheckedAccount<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Deposit<'info> {
    #[account(
        mut,
        has_one = buyer,
        seeds = [
            EscrowAccount::SEED_PREFIX,
            escrow.seller.as_ref(),
            buyer.key().as_ref(),
            &escrow.nonce.to_le_bytes(),
        ],
        bump = escrow.bump,
    )]
    pub escrow: Account<'info, EscrowAccount>,

    #[account(mut)]
    pub buyer: Signer<'info>,

    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct ConfirmReceipt<'info> {
    #[account(
        mut,
        has_one = buyer,
        has_one = seller,
        seeds = [
            EscrowAccount::SEED_PREFIX,
            seller.key().as_ref(),
            buyer.key().as_ref(),
            &escrow.nonce.to_le_bytes(),
        ],
        bump = escrow.bump,
    )]
    pub escrow: Account<'info, EscrowAccount>,

    /// Only the buyer can release. The seller cannot pay themselves.
    pub buyer: Signer<'info>,

    /// CHECK: constrained by `has_one = seller` to the key recorded at
    /// initialization, so the funds can only go where the buyer agreed.
    #[account(mut)]
    pub seller: UncheckedAccount<'info>,
}

#[derive(Accounts)]
pub struct Refund<'info> {
    #[account(
        mut,
        has_one = buyer,
        seeds = [
            EscrowAccount::SEED_PREFIX,
            escrow.seller.as_ref(),
            buyer.key().as_ref(),
            &escrow.nonce.to_le_bytes(),
        ],
        bump = escrow.bump,
    )]
    pub escrow: Account<'info, EscrowAccount>,

    #[account(mut)]
    pub buyer: Signer<'info>,
}

#[event]
pub struct EscrowInitialized {
    pub escrow: Pubkey,
    pub seller: Pubkey,
    pub buyer: Pubkey,
    pub amount: u64,
    pub nonce: u64,
}

#[event]
pub struct EscrowFunded {
    pub escrow: Pubkey,
    pub amount: u64,
}

#[event]
pub struct EscrowReleased {
    pub escrow: Pubkey,
    pub seller: Pubkey,
    pub amount: u64,
}

#[event]
pub struct EscrowRefunded {
    pub escrow: Pubkey,
    pub buyer: Pubkey,
    pub amount: u64,
}
