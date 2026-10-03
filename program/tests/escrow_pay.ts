import * as anchor from "@coral-xyz/anchor";
import { Program, BN } from "@coral-xyz/anchor";
import {
  Keypair,
  LAMPORTS_PER_SOL,
  PublicKey,
  SystemProgram,
} from "@solana/web3.js";
import { assert, expect } from "chai";
import { createHash, randomBytes } from "crypto";
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

  // The program's own bounds. A hostile seller writes the timeout into the QR,
  // so the floor is what guarantees the buyer a window to dispute at all.
  //
  // Run with `--features test-timeouts`, which lowers the floor to one second
  // so a deadline can actually pass inside a test. In production it is an
  // hour, asserted by a Rust unit test.
  const MIN_TIMEOUT = new BN(1);

  /// For tests that must act *inside* the window before waiting it out. A
  /// one-second window closes before a transaction can land, so the refund
  /// would be rejected for the wrong reason.
  const ACTIONABLE_WINDOW = new BN(10);
  const MAX_TIMEOUT = new BN(60 * 60 * 24 * 30); // 30 days
  const DAY = new BN(60 * 60 * 24);

  /// Waits until the validator's clock is past `deadline`.
  ///
  /// solana-test-validator has no clock warp, so this really does sleep —
  /// which is why the test timeouts are seconds, not hours. Polling the chain
  /// rather than the host clock keeps it honest about which clock matters.
  async function warpPast(deadline: BN) {
    // Generous enough to outlast ACTIONABLE_WINDOW with room to spare; the
    // loop exits as soon as the chain clock passes, so this costs nothing in
    // the common case.
    for (let i = 0; i < 90; i++) {
      const slot = await connection.getSlot();
      const chainTime = await connection.getBlockTime(slot);
      if (chainTime !== null && new BN(chainTime).gt(deadline)) return;
      await new Promise((r) => setTimeout(r, 500));
    }
    throw new Error(`chain clock never passed ${deadline.toString()}`);
  }

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

  /// Mirrors what the buyer's phone does: keep 32 random bytes, publish only
  /// the hash.
  function newReleaseCode() {
    const secret = randomBytes(32);
    return { secret, hash: createHash("sha256").update(secret).digest() };
  }

  const NO_CODE = Buffer.alloc(32);

  let nonceCounter = 0;
  const nextNonce = () => new BN(++nonceCounter);

  /** Opens and funds an escrow, the way the app does it: one transaction. */
  async function openFunded(
    seller: PublicKey,
    buyer: Keypair,
    timeout: BN = DAY,
    releaseHash: Buffer = NO_CODE
  ) {
    const nonce = nextNonce();
    const escrow = escrowPda(seller, buyer.publicKey, nonce);

    await program.methods
      .initializeEscrow(nonce, AMOUNT, timeout, [...releaseHash])
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

  /// Opens a funded escrow that carries a release code, and hands back the
  /// secret the way the buyer's phone would hold it.
  async function openWithCode(seller: PublicKey, buyer: Keypair) {
    const code = newReleaseCode();
    const { escrow } = await openFunded(seller, buyer, DAY, code.hash);
    return { escrow, ...code };
  }

  describe("initialize_escrow", () => {
    it("records the terms and starts in Created", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const nonce = nextNonce();
      const escrow = escrowPda(seller, buyer.publicKey, nonce);

      await program.methods
        .initializeEscrow(nonce, AMOUNT, DAY, [...NO_CODE])
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
      // The deadline is the clock at init plus the timeout, not the timeout.
      expect(account.deadline.sub(account.createdAt).toString()).to.equal(
        DAY.toString()
      );
    });

    it("rejects a zero amount", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const nonce = nextNonce();

      try {
        await program.methods
          .initializeEscrow(nonce, new BN(0), DAY, [...NO_CODE])
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
          .initializeEscrow(nonce, AMOUNT, DAY, [...NO_CODE])
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

  describe("timeout bounds", () => {
    // The seller chooses the timeout, so the program has to defend the buyer
    // against a seller who picks a hostile one.
    async function openWith(timeout: BN) {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const nonce = nextNonce();

      return program.methods
        .initializeEscrow(nonce, AMOUNT, timeout, [...NO_CODE])
        .accounts({
          escrow: escrowPda(seller, buyer.publicKey, nonce),
          buyer: buyer.publicKey,
          seller,
          systemProgram: SystemProgram.programId,
        })
        .signers([buyer])
        .rpc();
    }

    it("rejects a timeout below the floor", async () => {
      // Without this, a seller sets one second and claims the funds before
      // the buyer has left the car park.
      try {
        await openWith(MIN_TIMEOUT.subn(1));
        assert.fail("expected TimeoutOutOfRange");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("TimeoutOutOfRange");
      }
    });

    it("rejects zero and negative timeouts", async () => {
      for (const timeout of [new BN(0), new BN(-1), new BN(-100000)]) {
        try {
          await openWith(timeout);
          assert.fail(`expected TimeoutOutOfRange for ${timeout}`);
        } catch (err) {
          expect(err.error.errorCode.code).to.equal("TimeoutOutOfRange");
        }
      }
    });

    it("rejects a timeout beyond the ceiling", async () => {
      // Funds should not be parkable indefinitely either.
      try {
        await openWith(MAX_TIMEOUT.addn(1));
        assert.fail("expected TimeoutOutOfRange");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("TimeoutOutOfRange");
      }
    });

    it("accepts both ends of the allowed range", async () => {
      await openWith(MIN_TIMEOUT);
      await openWith(MAX_TIMEOUT);
    });
  });

  describe("claim", () => {
    it("is refused while the refund window is open", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const { escrow } = await openFunded(seller.publicKey, buyer, DAY);

      try {
        await program.methods
          .claim()
          .accounts({ escrow, seller: seller.publicKey })
          .signers([seller])
          .rpc();
        assert.fail("expected DeadlineNotReached");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("DeadlineNotReached");
      }
    });

    it("pays the seller once the deadline passes", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        MIN_TIMEOUT
      );

      // Jump the validator past the deadline rather than waiting an hour.
      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      const before = await connection.getBalance(seller.publicKey);
      await program.methods
        .claim()
        .accounts({ escrow, seller: seller.publicKey })
        .signers([seller])
        .rpc();
      const after = await connection.getBalance(seller.publicKey);

      // Net of the claim's own fee, the seller is up by the escrowed amount.
      expect(after - before).to.be.greaterThan(AMOUNT.toNumber() - 100000);

      const settled = await program.account.escrowAccount.fetch(escrow);
      expect(settled.state).to.deep.equal({ released: {} });
    });

    it("cannot be claimed by anyone but the seller", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const attacker = await fundedKeypair();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        MIN_TIMEOUT
      );

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      try {
        await program.methods
          .claim()
          .accounts({ escrow, seller: attacker.publicKey })
          .signers([attacker])
          .rpc();
        assert.fail("expected the seller constraint to reject this");
      } catch (err) {
        expect(err.error.errorCode.code).to.be.oneOf([
          "ConstraintHasOne",
          "ConstraintSeeds",
        ]);
      }
    });

    it("cannot be claimed twice", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        MIN_TIMEOUT
      );

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      const claim = () =>
        program.methods
          .claim()
          .accounts({ escrow, seller: seller.publicKey })
          .signers([seller])
          .rpc();

      await claim();
      try {
        await claim();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });

    it("cannot be claimed after the buyer already refunded", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        ACTIONABLE_WINDOW
      );

      await program.methods
        .refund()
        .accounts({ escrow, buyer: buyer.publicKey })
        .signers([buyer])
        .rpc();

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      try {
        await program.methods
          .claim()
          .accounts({ escrow, seller: seller.publicKey })
          .signers([seller])
          .rpc();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });
  });

  describe("the refund window", () => {
    it("closes once the deadline passes", async () => {
      // This is the whole point of the change: a buyer can no longer take the
      // goods and sit on the refund option forever.
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const { escrow } = await openFunded(seller, buyer, MIN_TIMEOUT);

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      try {
        await program.methods
          .refund()
          .accounts({ escrow, buyer: buyer.publicKey })
          .signers([buyer])
          .rpc();
        assert.fail("expected RefundWindowClosed");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("RefundWindowClosed");
      }
    });

    it("still lets the buyer release after the deadline", async () => {
      // Paying the seller is never harmful, so it stays available.
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        MIN_TIMEOUT
      );

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      const before = await connection.getBalance(seller.publicKey);
      await program.methods
        .confirmReceipt()
        .accounts({ escrow, buyer: buyer.publicKey, seller: seller.publicKey })
        .signers([buyer])
        .rpc();
      const after = await connection.getBalance(seller.publicKey);

      expect(after - before).to.equal(AMOUNT.toNumber());
    });
  });

  describe("release_with_code", () => {
    it("pays the seller when the correct secret is presented", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow, secret } = await openWithCode(seller.publicKey, buyer);

      const before = await connection.getBalance(seller.publicKey);
      await program.methods
        .releaseWithCode([...secret])
        .accounts({ escrow, seller: seller.publicKey, payer: buyer.publicKey })
        .signers([buyer])
        .rpc();
      const after = await connection.getBalance(seller.publicKey);

      expect(after - before).to.equal(AMOUNT.toNumber());

      const account = await program.account.escrowAccount.fetch(escrow);
      expect(account.state).to.deep.equal({ released: {} });
    });

    it("rejects a wrong secret", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openWithCode(seller.publicKey, buyer);

      try {
        await program.methods
          .releaseWithCode([...randomBytes(32)])
          .accounts({
            escrow,
            seller: seller.publicKey,
            payer: buyer.publicKey,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected BadReleaseCode");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("BadReleaseCode");
      }
    });

    it("rejects an escrow opened without a code", async () => {
      // An all-zero hash must not be releasable by whoever hashes 32 zeroes.
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow } = await openFunded(seller.publicKey, buyer);

      try {
        await program.methods
          .releaseWithCode([...NO_CODE])
          .accounts({
            escrow,
            seller: seller.publicKey,
            payer: buyer.publicKey,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected NoReleaseCode");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("NoReleaseCode");
      }
    });

    it("rejects release before the escrow is funded", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate().publicKey;
      const nonce = nextNonce();
      const escrow = escrowPda(seller, buyer.publicKey, nonce);
      const code = newReleaseCode();

      // Initialized but never deposited into.
      await program.methods
        .initializeEscrow(nonce, AMOUNT, DAY, [...code.hash])
        .accounts({
          escrow,
          buyer: buyer.publicKey,
          seller,
          systemProgram: SystemProgram.programId,
        })
        .signers([buyer])
        .rpc();

      try {
        await program.methods
          .releaseWithCode([...code.secret])
          .accounts({ escrow, seller, payer: buyer.publicKey })
          .signers([buyer])
          .rpc();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });

    it("cannot be released twice", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow, secret } = await openWithCode(seller.publicKey, buyer);

      const release = () =>
        program.methods
          .releaseWithCode([...secret])
          .accounts({
            escrow,
            seller: seller.publicKey,
            payer: buyer.publicKey,
          })
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

    it("is refused once the buyer has refunded", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow, secret } = await openWithCode(seller.publicKey, buyer);

      await program.methods
        .refund()
        .accounts({ escrow, buyer: buyer.publicKey })
        .signers([buyer])
        .rpc();

      try {
        await program.methods
          .releaseWithCode([...secret])
          .accounts({
            escrow,
            seller: seller.publicKey,
            payer: buyer.publicKey,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });

    it("is refused once the seller has claimed", async () => {
      const buyer = await fundedKeypair();
      const seller = await fundedKeypair();
      const code = newReleaseCode();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        MIN_TIMEOUT,
        code.hash
      );

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      await program.methods
        .claim()
        .accounts({ escrow, seller: seller.publicKey })
        .signers([seller])
        .rpc();

      try {
        await program.methods
          .releaseWithCode([...code.secret])
          .accounts({
            escrow,
            seller: seller.publicKey,
            payer: buyer.publicKey,
          })
          .signers([buyer])
          .rpc();
        assert.fail("expected InvalidState");
      } catch (err) {
        expect(err.error.errorCode.code).to.equal("InvalidState");
      }
    });

    it("cannot redirect the payout to another wallet", async () => {
      // The secret authorises a payment, never a destination.
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const attacker = Keypair.generate();
      const { escrow, secret } = await openWithCode(seller.publicKey, buyer);

      try {
        await program.methods
          .releaseWithCode([...secret])
          .accounts({
            escrow,
            seller: attacker.publicKey,
            payer: buyer.publicKey,
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

    it("lets an unrelated third party submit it, and still pays the seller", async () => {
      // This is what makes a courier handover possible: the scanner needs no
      // relationship to either party, and gains nothing by scanning.
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const courier = await fundedKeypair();
      const { escrow, secret } = await openWithCode(seller.publicKey, buyer);

      const sellerBefore = await connection.getBalance(seller.publicKey);
      const courierBefore = await connection.getBalance(courier.publicKey);

      await program.methods
        .releaseWithCode([...secret])
        .accounts({
          escrow,
          seller: seller.publicKey,
          payer: courier.publicKey,
        })
        .signers([courier])
        .rpc();

      const sellerAfter = await connection.getBalance(seller.publicKey);
      const courierAfter = await connection.getBalance(courier.publicKey);

      expect(sellerAfter - sellerBefore).to.equal(AMOUNT.toNumber());
      // The security property: scanning earns the courier nothing. (Anchor's
      // provider wallet pays the fee here, so the courier's balance is
      // unchanged rather than slightly down.)
      expect(courierAfter).to.be.at.most(courierBefore);
    });

    it("still works after the deadline, paying the same address as claim", async () => {
      // Documented behaviour: past the deadline the seller could claim
      // anyway, so refusing the code would only break a late delivery.
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const code = newReleaseCode();
      const { escrow } = await openFunded(
        seller.publicKey,
        buyer,
        MIN_TIMEOUT,
        code.hash
      );

      const account = await program.account.escrowAccount.fetch(escrow);
      await warpPast(account.deadline);

      const before = await connection.getBalance(seller.publicKey);
      await program.methods
        .releaseWithCode([...code.secret])
        .accounts({ escrow, seller: seller.publicKey, payer: buyer.publicKey })
        .signers([buyer])
        .rpc();
      const after = await connection.getBalance(seller.publicKey);

      expect(after - before).to.equal(AMOUNT.toNumber());
    });

    it("records the hash the buyer set", async () => {
      const buyer = await fundedKeypair();
      const seller = Keypair.generate();
      const { escrow, hash } = await openWithCode(seller.publicKey, buyer);

      const account = await program.account.escrowAccount.fetch(escrow);
      expect(Buffer.from(account.releaseHash)).to.deep.equal(hash);
    });

    it("hashes the shared test vector the same way Rust and Dart do", async () => {
      const secret = Buffer.from(
        "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
        "hex"
      );
      expect(createHash("sha256").update(secret).digest("hex")).to.equal(
        "630dcd2966c4336691125448bbb25b4ff412a49c732db2c8abc1b8581bd710dd"
      );
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
