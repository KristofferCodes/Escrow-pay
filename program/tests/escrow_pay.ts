import * as anchor from "@coral-xyz/anchor";
import { Program, BN } from "@coral-xyz/anchor";
import {
  Keypair,
  LAMPORTS_PER_SOL,
  PublicKey,
  SystemProgram,
} from "@solana/web3.js";
import { assert, expect } from "chai";
import { EscrowPay } from "../target/types/escrow_pay";

/**
 * These tests are the program's real specification. The Flutter app trusts the
 * four transitions below and nothing else, so anything that changes here has
 * to change in `lib/solana/escrow_program.dart` too.
 */
describe("escrow_pay", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const program = anchor.workspace.escrowPay as Program<EscrowPay>;
  const connection = provider.connection;

  const AMOUNT = new BN(0.5 * LAMPORTS_PER_SOL);

  /** Each test gets fresh wallets so ordering never matters. */
  async function fundedKeypair(sol = 2): Promise<Keypair> {
    const kp = Keypair.generate();
    const sig = await connection.requestAirdrop(
      kp.publicKey,
      sol * LAMPORTS_PER_SOL
    );
    const bh = await connection.getLatestBlockhash();
    await connection.confirmTransaction({ signature: sig, ...bh }, "confirmed");
    return kp;
  }

  function escrowPda(seller: PublicKey, buyer: PublicKey, nonce: BN) {
    return PublicKey.findProgramAddressSync(
      [
        Buffer.from("escrow"),
        seller.toBuffer(),
        buyer.toBuffer(),
        nonce.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    )[0];
  }

  let nonceCounter = 0;
  const nextNonce = () => new BN(++nonceCounter);

  /** Opens and funds an escrow, the way the app does it: one transaction. */
  async function openFunded(seller: PublicKey, buyer: Keypair) {
    const nonce = nextNonce();
    const escrow = escrowPda(seller, buyer.publicKey, nonce);

    await program.methods
      .initializeEscrow(nonce, AMOUNT)
      .accounts({
        escrow,
        buyer: buyer.publicKey,
        seller,
        systemProgram: SystemProgram.programId,
      })
      .postInstructions([
        await program.methods
          .deposit()
          .accounts({
            escrow,
            buyer: buyer.publicKey,
            systemProgram: SystemProgram.programId,
          })
          .instruction(),
      ])
      .signers([buyer])
      .rpc();

    return { escrow, nonce };
  }

  describe("initialize_escrow", () => {
    it("records the terms and starts in Created", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const nonce = nextNonce();
      const escrow = escrowPda(seller, buyer.publicKey, nonce);

      await program.methods
        .initializeEscrow(nonce, AMOUNT)
        .accounts({
          escrow,
          buyer: buyer.publicKey,
          seller,
          systemProgram: SystemProgram.programId,
        })
        .signers([buyer])
        .rpc();

      const account = await program.account.escrowAccount.fetch(escrow);
      expect(account.seller.toBase58()).to.equal(seller.toBase58());
      expect(account.buyer.toBase58()).to.equal(buyer.publicKey.toBase58());
      expect(account.amount.toString()).to.equal(AMOUNT.toString());
      expect(account.nonce.toString()).to.equal(nonce.toString());
      expect(account.state).to.deep.equal({ created: {} });
      expect(account.createdAt.toNumber()).to.be.greaterThan(0);
    });

    it("rejects a zero amount", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const nonce = nextNonce();

      try {
        await program.methods
          .initializeEscrow(nonce, new BN(0))
          .accounts({
            escrow: escrowPda(seller, buyer.publicKey, nonce),
            buyer: buyer.publicKey,
            seller,
            systemProgram: SystemProgram.programId,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected ZeroAmount");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("ZeroAmount");
      }
    });

    it("refuses to escrow with yourself", async () => {
      const buyer = await fundedKeypair();
      const nonce = nextNonce();

      try {
        await program.methods
          .initializeEscrow(nonce, AMOUNT)
          .accounts({
            escrow: escrowPda(buyer.publicKey, buyer.publicKey, nonce),
            buyer: buyer.publicKey,
            seller: buyer.publicKey,
            systemProgram: SystemProgram.programId,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected SameParty");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("SameParty");
      }
    });
  });

  describe("deposit", () => {
    it("moves the amount into the PDA and flips to Funded", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;

      const before = await connection.getBalance(buyer.publicKey);
      const { escrow } = await openFunded(seller, buyer);

      const account = await program.account.escrowAccount.fetch(escrow);
      expect(account.state).to.deep.equal({ funded: {} });

      // The PDA holds the escrowed amount on top of its rent deposit.
      const held = await connection.getBalance(escrow);
      expect(held).to.be.greaterThan(AMOUNT.toNumber());

      // The buyer paid the amount, plus rent and fees.
      const after = await connection.getBalance(buyer.publicKey);
      expect(before - after).to.be.greaterThan(AMOUNT.toNumber());
    });

    it("cannot be funded twice", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const { escrow } = await openFunded(seller, buyer);

      try {
        await program.methods
          .deposit()
          .accounts({
            escrow,
            buyer: buyer.publicKey,
            systemProgram: SystemProgram.programId,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });
  });

  describe("confirm_receipt", () => {
    it("pays the seller exactly the escrowed amount", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      const before = await connection.getBalance(seller.publicKey);

      await program.methods
        .confirmReceipt()
        .accounts({ escrow, buyer: buyer.publicKey, seller: seller.publicKey })
        .signers([buyer])
        .rpc();

      const after = await connection.getBalance(seller.publicKey);
      expect(after - before).to.equal(AMOUNT.toNumber());

      const account = await program.account.escrowAccount.fetch(escrow);
      expect(account.state).to.deep.equal({ released: {} });
    });

    it("leaves the rent behind so the record survives", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      await program.methods
        .confirmReceipt()
        .accounts({ escrow, buyer: buyer.publicKey, seller: seller.publicKey })
        .signers([buyer])
        .rpc();

      // The app reads settled escrows to show history, so the account must
      // still be rent exempt after payout.
      const info = await connection.getAccountInfo(escrow);
      expect(info).to.not.be.null;
      const rent = await connection.getMinimumBalanceForRentExemption(
        info.data.length
      );
      expect(info.lamports).to.be.at.least(rent);
    });

    it("cannot be released by the seller", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      try {
        await program.methods
          .confirmReceipt()
          .accounts({
            escrow,
            buyer: seller.publicKey,
            seller: seller.publicKey,
          })
          .signers([seller])
          .rpc();
        assert.fail("expected the buyer constraint to reject this");
      } catch (err) {
        expect(err.error.errorCode.code).to.be.oneOf([
          "ConstraintHasOne",
          "ConstraintSeeds",
        ]);
      }
    });

    it("cannot redirect the payout to another wallet", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const attacker = Keypair.generate();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      try {
        await program.methods
          .confirmReceipt()
          .accounts({
            escrow,
            buyer: buyer.publicKey,
            seller: attacker.publicKey,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected the seller constraint to reject this");
      } catch (err) {
        expect(err.error.errorCode.code).to.be.oneOf([
          "ConstraintHasOne",
          "ConstraintSeeds",
        ]);
      }
    });

    it("cannot release twice", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      const release = () =>
        program.methods
          .confirmReceipt()
          .accounts({ escrow, buyer: buyer.publicKey, seller: seller.publicKey })
          .signers([buyer])
          .rpc();

      await release();
      try {
        await release();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });
  });

  describe("refund", () => {
    it("returns the amount to the buyer", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const { escrow } = await openFunded(seller, buyer);

      const before = await connection.getBalance(buyer.publicKey);

      await program.methods
        .refund()
        .accounts({ escrow, buyer: buyer.publicKey })
        .signers([buyer])
        .rpc();

      // Net of the transaction fee, the buyer is up by the escrowed amount.
      const after = await connection.getBalance(buyer.publicKey);
      expect(after - before).to.be.greaterThan(AMOUNT.toNumber() - 100000);

      const account = await program.account.escrowAccount.fetch(escrow);
      expect(account.state).to.deep.equal({ refunded: {} });
    });

    it("is closed off once the escrow is released", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      await program.methods
        .confirmReceipt()
        .accounts({ escrow, buyer: buyer.publicKey, seller: seller.publicKey })
        .signers([buyer])
        .rpc();

      try {
        await program.methods
          .refund()
          .accounts({ escrow, buyer: buyer.publicKey })
          .signers([buyer])
          .rpc();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });

    it("cannot be triggered by anyone but the buyer", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      try {
        await program.methods
          .refund()
          .accounts({ escrow, buyer: seller.publicKey })
          .signers([seller])
          .rpc();
        assert.fail("expected the buyer constraint to reject this");
      } catch (err) {
        expect(err.error.errorCode.code).to.be.oneOf([
          "ConstraintHasOne",
          "ConstraintSeeds",
        ]);
      }
    });
  });

  describe("pda derivation", () => {
    it("separates repeat trades between the same two wallets", async () => {
      const buyer = await fundedKeypair(3);
      const seller = Keypair.generate().publicKey;

      const first = await openFunded(seller, buyer);
      const second = await openFunded(seller, buyer);

      expect(first.escrow.toBase58()).to.not.equal(second.escrow.toBase58());

      for (const { escrow } of [first, second]) {
        const account = await program.account.escrowAccount.fetch(escrow);
        expect(account.state).to.deep.equal({ funded: {} });
      }
    });
  });
});
