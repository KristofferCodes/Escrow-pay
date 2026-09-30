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
const { Keypair, PublicKey, SystemProgram, LAMPORTS_PER_SOL } = require("@solana/web3.js");
const fs = require("fs");
const os = require("os");

const AMOUNT = Math.floor(0.01 * LAMPORTS_PER_SOL);

function loadKeypair(path) {
  const secret = JSON.parse(fs.readFileSync(path.replace("~", os.homedir()), "utf8"));
  return Keypair.fromSecretKey(Uint8Array.from(secret));
}

(async () => {
  process.env.ANCHOR_PROVIDER_URL ||= "https://api.devnet.solana.com";
  process.env.ANCHOR_WALLET ||= `${os.homedir()}/.config/solana/id.json`;

  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const idl = JSON.parse(fs.readFileSync("target/idl/escrow_pay.json", "utf8"));
  const program = new anchor.Program(idl, provider);
  const connection = provider.connection;

  const buyer = loadKeypair(process.env.ANCHOR_WALLET);
  const seller = Keypair.generate();
  const nonce = new anchor.BN(Date.now());

  console.log("program :", program.programId.toBase58());
  console.log("buyer   :", buyer.publicKey.toBase58());
  console.log("seller  :", seller.publicKey.toBase58(), "(fresh, 0 SOL)");
  console.log("amount  :", AMOUNT / LAMPORTS_PER_SOL, "SOL\n");

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

  // 1. open + fund, in one transaction, the way the app does it.
  const sigFund = await program.methods
    .initializeEscrow(nonce, new anchor.BN(AMOUNT))
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
    .rpc();

  let account = await program.account.escrowAccount.fetch(escrow);
  console.log("fund    :", Object.keys(account.state)[0], "|", sigFund);
  if (!("funded" in account.state)) throw new Error("expected Funded");

  // 2. release to the seller.
  const before = await connection.getBalance(seller.publicKey);
  const sigRelease = await program.methods
    .confirmReceipt()
    .accounts({ escrow, buyer: buyer.publicKey, seller: seller.publicKey })
    .rpc();

  account = await program.account.escrowAccount.fetch(escrow);
  const after = await connection.getBalance(seller.publicKey);
  console.log("release :", Object.keys(account.state)[0], "|", sigRelease);

  if (!("released" in account.state)) throw new Error("expected Released");
  if (after - before !== AMOUNT) {
    throw new Error(`seller received ${after - before}, expected ${AMOUNT}`);
  }

  console.log("\nseller received exactly", (after - before) / LAMPORTS_PER_SOL, "SOL");
  console.log("explorer:",
    `https://explorer.solana.com/tx/${sigRelease}?cluster=devnet`);
  console.log("\nDEVNET SMOKE TEST PASSED");
})().catch((e) => {
  console.error("\nFAILED:", e.message);
  if (e.logs) console.error(e.logs.slice(-8).join("\n"));
  process.exit(1);
});
