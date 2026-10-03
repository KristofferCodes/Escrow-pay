// End-to-end smoke test against the DEPLOYED devnet program.
//
// `anchor test` proves the program works on a local validator. This proves the
// thing that is actually deployed works, using the same PDA seeds and
// instruction layout the Flutter client builds by hand — so a mismatch between
// the app and the live program shows up here rather than in someone's hands.
//
//   node scripts/devnet-smoke.js
//
// Spends a few thousand lamports of the deployer's devnet SOL as the buyer.

const anchor = require("@coral-xyz/anchor");
const {
  Keypair,
  PublicKey,
  SystemProgram,
  Transaction,
  LAMPORTS_PER_SOL,
} = require("@solana/web3.js");
const fs = require("fs");
const os = require("os");
const { createHash, randomBytes } = require("crypto");

const AMOUNT = Math.floor(0.01 * LAMPORTS_PER_SOL);

// The deployed program's floor. Nothing here changes it — the claim path is
// verified by its refusals, not by waiting an hour for a window to close.
const HOUR = 60 * 60;
const NO_CODE = Buffer.alloc(32);

function loadKeypair(path) {
  const secret = JSON.parse(fs.readFileSync(path.replace("~", os.homedir()), "utf8"));
  return Keypair.fromSecretKey(Uint8Array.from(secret));
}

/// Prefers the endpoint the app itself is built with, so the smoke test
/// exercises the same RPC the APK will use. config/local.json is gitignored.
function configuredRpcUrl() {
  if (process.env.ANCHOR_PROVIDER_URL) return process.env.ANCHOR_PROVIDER_URL;
  try {
    const cfg = JSON.parse(
      fs.readFileSync(`${__dirname}/../../config/local.json`, "utf8")
    );
    if (cfg.DEVNET_RPC_URL) return cfg.DEVNET_RPC_URL;
  } catch {
    // No local config — fall through to the public endpoint.
  }
  return "https://api.devnet.solana.com";
}

/// Never print the key itself.
function redact(url) {
  return url.replace(/\/v2\/[^/?]+/, "/v2/***");
}

/// Sends and confirms without a websocket.
///
/// Anchor's `.rpc()` confirms via `signatureSubscribe`, and not every provider
/// serves that on its Solana websocket — Alchemy answered
/// "Method 'signatureSubscribe' not found" while its HTTP endpoint worked
/// perfectly. Polling `getSignatureStatuses` keeps this script working against
/// any endpoint the app itself can talk to.
async function sendAndConfirm(provider, tx, signers = []) {
  const connection = provider.connection;
  const { blockhash, lastValidBlockHeight } =
    await connection.getLatestBlockhash("confirmed");

  tx.recentBlockhash = blockhash;
  tx.lastValidBlockHeight = lastValidBlockHeight;
  tx.feePayer = provider.wallet.publicKey;

  const signed = await provider.wallet.signTransaction(tx);
  for (const signer of signers) signed.partialSign(signer);

  const signature = await connection.sendRawTransaction(signed.serialize(), {
    preflightCommitment: "confirmed",
  });

  const deadline = Date.now() + 60_000;
  while (Date.now() < deadline) {
    const { value } = await connection.getSignatureStatuses([signature]);
    const status = value[0];
    if (status?.err) {
      throw new Error(`transaction failed: ${JSON.stringify(status.err)}`);
    }
    if (
      status?.confirmationStatus === "confirmed" ||
      status?.confirmationStatus === "finalized"
    ) {
      return signature;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`not confirmed within 60s: ${signature}`);
}

(async () => {
  process.env.ANCHOR_PROVIDER_URL = configuredRpcUrl();
  process.env.ANCHOR_WALLET ||= `${os.homedir()}/.config/solana/id.json`;

  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const idl = JSON.parse(fs.readFileSync("target/idl/escrow_pay.json", "utf8"));
  const program = new anchor.Program(idl, provider);
  const connection = provider.connection;

  const buyer = loadKeypair(process.env.ANCHOR_WALLET);
  const seller = Keypair.generate();
  const nonce = new anchor.BN(Date.now());
  const failures = [];

  // What the buyer's phone does: keep 32 random bytes, publish only the hash.
  const secret = randomBytes(32);
  const releaseHash = createHash("sha256").update(secret).digest();

  /// Asserts an instruction is refused with a specific program error.
  async function expectRejected(label, expected, send) {
    try {
      await send();
      failures.push(`${label}: expected ${expected}, but it succeeded`);
      console.log(`  ✗ ${label} — expected ${expected}, succeeded`);
    } catch (e) {
      const code = e?.error?.errorCode?.code ?? e.message;
      if (code === expected) {
        console.log(`  ✓ ${label} — refused with ${expected}`);
      } else {
        failures.push(`${label}: expected ${expected}, got ${code}`);
        console.log(`  ✗ ${label} — expected ${expected}, got ${code}`);
      }
    }
  }

  console.log("rpc     :", redact(process.env.ANCHOR_PROVIDER_URL));
  console.log("program :", program.programId.toBase58());
  console.log("buyer   :", buyer.publicKey.toBase58());
  console.log("seller  :", seller.publicKey.toBase58(), "(fresh, 0 SOL)");
  console.log("amount  :", AMOUNT / LAMPORTS_PER_SOL, "SOL");
  console.log("code    : sha256(secret) =", releaseHash.toString("hex").slice(0, 16) + "…\n");

  // Derived exactly as lib/solana/escrow_program.dart does it.
  const [escrow] = PublicKey.findProgramAddressSync(
    [
      Buffer.from("escrow"),
      seller.publicKey.toBuffer(),
      buyer.publicKey.toBuffer(),
      nonce.toArrayLike(Buffer, "le", 8),
    ],
    program.programId
  );
  console.log("escrow  :", escrow.toBase58(), "\n");

  // The seller signs the claim attempts, so it needs enough for fees. A
  // transfer, not an airdrop: the devnet faucet is rate limited by IP.
  await sendAndConfirm(
    provider,
    new Transaction().add(
      SystemProgram.transfer({
        fromPubkey: buyer.publicKey,
        toPubkey: seller.publicKey,
        lamports: Math.floor(0.01 * LAMPORTS_PER_SOL),
      })
    )
  );

  // 1. The timeout floor is live. This is also what proves the upgraded
  // program is the one deployed: the old build had no timeout argument.
  console.log("timeout bounds");
  await expectRejected("one-second window", "TimeoutOutOfRange", () =>
    program.methods
      .initializeEscrow(nonce, new anchor.BN(AMOUNT), new anchor.BN(1), [
        ...NO_CODE,
      ])
      .accounts({
        escrow,
        buyer: buyer.publicKey,
        seller: seller.publicKey,
        systemProgram: SystemProgram.programId,
      })
      .rpc()
  );
  console.log("");

  // 2. open + fund, in one transaction, the way the app does it.
  const fundTx = await program.methods
    .initializeEscrow(nonce, new anchor.BN(AMOUNT), new anchor.BN(24 * HOUR), [
      ...releaseHash,
    ])
    .accounts({
      escrow,
      buyer: buyer.publicKey,
      seller: seller.publicKey,
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
    .transaction();
  const sigFund = await sendAndConfirm(provider, fundTx);

  let account = await program.account.escrowAccount.fetch(escrow);
  console.log("fund    :", Object.keys(account.state)[0], "|", sigFund);
  if (!("funded" in account.state)) throw new Error("expected Funded");

  // 3. The seller cannot claim while the buyer's window is open. Proves the
  // claim instruction is deployed and gated, without waiting out a deadline.
  console.log("");
  console.log("claim gating");
  await expectRejected("claim before deadline", "DeadlineNotReached", () =>
    program.methods
      .claim()
      .accounts({ escrow, seller: seller.publicKey })
      .signers([seller])
      .rpc()
  );
  console.log("");

  // 4. A wrong secret buys nothing.
  console.log("release code");
  await expectRejected("wrong secret", "BadReleaseCode", () =>
    program.methods
      .releaseWithCode([...randomBytes(32)])
      .accounts({ escrow, seller: seller.publicKey, payer: buyer.publicKey })
      .rpc()
  );

  // 5. The real one releases — this is the handover scan.
  const before = await connection.getBalance(seller.publicKey);
  const releaseTx = await program.methods
    .releaseWithCode([...secret])
    .accounts({ escrow, seller: seller.publicKey, payer: buyer.publicKey })
    .transaction();
  const sigRelease = await sendAndConfirm(provider, releaseTx);

  account = await program.account.escrowAccount.fetch(escrow);
  const after = await connection.getBalance(seller.publicKey);
  console.log("release :", Object.keys(account.state)[0], "| by code |", sigRelease);

  if (!("released" in account.state)) throw new Error("expected Released");
  if (after - before !== AMOUNT) {
    throw new Error(`seller received ${after - before}, expected ${AMOUNT}`);
  }

  // 6. A settled escrow is closed to everyone, claim included.
  console.log("");
  await expectRejected("claim after release", "InvalidState", () =>
    program.methods
      .claim()
      .accounts({ escrow, seller: seller.publicKey })
      .signers([seller])
      .rpc()
  );

  console.log("\nseller received exactly", (after - before) / LAMPORTS_PER_SOL, "SOL");
  console.log("explorer:",
    `https://explorer.solana.com/tx/${sigRelease}?cluster=devnet`);
  if (failures.length) {
    throw new Error(`\n  - ${failures.join("\n  - ")}`);
  }
  console.log("\nDEVNET SMOKE TEST PASSED");
})().catch((e) => {
  console.error("\nFAILED:", e.message);
  if (e.logs) console.error(e.logs.slice(-8).join("\n"));
  process.exit(1);
});
