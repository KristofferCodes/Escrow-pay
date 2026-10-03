// Redeems a buyer's release code from the command line.
//
// The seller's phone normally scans the QR. This does the same thing from a
// laptop, which is what makes the handover testable when only one Android
// device is in the room — the tester plays buyer, taps "Copy link", sends you
// the link, and you play seller here.
//
// It also demonstrates the property the design rests on: the submitter needs
// no relationship to either party. This script pays the fee with whatever
// keypair the Solana CLI is configured with, and the money still goes to the
// seller recorded at funding. Nothing else is possible.
//
//   node scripts/redeem-release.js 'escrowpay:release:v1?e=...&k=...&c=devnet'

const anchor = require("@coral-xyz/anchor");
const {
  Keypair,
  PublicKey,
  Transaction,
  LAMPORTS_PER_SOL,
} = require("@solana/web3.js");
const fs = require("fs");
const os = require("os");

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

const redact = (url) => url.replace(/\/v2\/[^/?]+/, "/v2/***");

/// Mirrors ReleasePayload.decode in lib/core/release_code.dart.
function parseReleaseLink(raw) {
  const prefix = "escrowpay:release:v1?";
  const text = raw.trim();
  if (!text.startsWith(prefix)) {
    throw new Error(
      "Not a release link. It should start with 'escrowpay:release:v1?'.\n" +
        "  (A listing code starts 'escrowpay:v1?' — that is the other kind.)"
    );
  }

  const params = new URLSearchParams(text.slice(prefix.length));
  const escrow = params.get("e");
  const secretHex = params.get("k");
  const cluster = params.get("c");

  if (!escrow) throw new Error("Link has no escrow address.");
  if (!cluster) throw new Error("Link has no cluster.");
  if (!secretHex || !/^[0-9a-f]{64}$/i.test(secretHex)) {
    throw new Error("Link has no valid 32-byte secret.");
  }

  return {
    escrow: new PublicKey(escrow),
    secret: Buffer.from(secretHex, "hex"),
    cluster,
  };
}

/// Confirms over HTTP rather than a websocket subscription — not every
/// provider serves signatureSubscribe on its Solana endpoint.
async function sendAndConfirm(provider, tx) {
  const connection = provider.connection;
  const { blockhash, lastValidBlockHeight } =
    await connection.getLatestBlockhash("confirmed");

  tx.recentBlockhash = blockhash;
  tx.lastValidBlockHeight = lastValidBlockHeight;
  tx.feePayer = provider.wallet.publicKey;

  const signed = await provider.wallet.signTransaction(tx);
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
  const link = process.argv[2];
  if (!link) {
    console.error(
      "usage: node scripts/redeem-release.js '<escrowpay:release:v1 link>'\n\n" +
        "Get the link from the buyer's phone: Show release code -> Copy link.\n" +
        "Quote it — the shell will otherwise eat the & characters."
    );
    process.exit(64);
  }

  const { escrow, secret, cluster } = parseReleaseLink(link);

  process.env.ANCHOR_PROVIDER_URL = configuredRpcUrl();
  process.env.ANCHOR_WALLET ||= `${os.homedir()}/.config/solana/id.json`;

  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);

  const idl = JSON.parse(
    fs.readFileSync(`${__dirname}/../target/idl/escrow_pay.json`, "utf8")
  );
  const program = new anchor.Program(idl, provider);

  console.log("rpc     :", redact(process.env.ANCHOR_PROVIDER_URL));
  console.log("escrow  :", escrow.toBase58());
  console.log("cluster :", cluster);
  console.log("payer   :", provider.wallet.publicKey.toBase58(), "(fee only)");
  console.log("");

  const account = await program.account.escrowAccount.fetch(escrow);
  const state = Object.keys(account.state)[0];
  const seller = account.seller;

  console.log("seller  :", seller.toBase58());
  console.log("amount  :", account.amount.toNumber() / LAMPORTS_PER_SOL, "SOL");
  console.log("state   :", state);
  console.log("");

  if (state !== "funded") {
    console.error(`Cannot release: this escrow is already ${state}.`);
    process.exit(1);
  }

  const before = await provider.connection.getBalance(seller);

  const tx = await program.methods
    .releaseWithCode([...secret])
    .accounts({
      escrow,
      seller,
      payer: provider.wallet.publicKey,
    })
    .transaction();

  const signature = await sendAndConfirm(provider, tx);
  const after = await provider.connection.getBalance(seller);

  const settled = await program.account.escrowAccount.fetch(escrow);
  console.log("released:", Object.keys(settled.state)[0], "|", signature);
  console.log(
    "seller received:",
    (after - before) / LAMPORTS_PER_SOL,
    "SOL"
  );
  console.log(
    "explorer:",
    `https://explorer.solana.com/tx/${signature}?cluster=devnet`
  );
})().catch((e) => {
  const code = e?.error?.errorCode?.code;
  console.error("\nFAILED:", code ?? e.message);
  if (code === "BadReleaseCode") {
    console.error("  The secret does not match this escrow's stored hash.");
  }
  process.exit(1);
});
