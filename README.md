# Escrow Pay

Mobile-first onchain escrow for in-person resale, built for **CLOCK IN**, the
Solana Mobile hackathon by RadiantsDAO.

A seller and a buyer settle a trade without trusting each other. The buyer's
funds sit in a program-derived account that neither party controls. When the
goods change hands the buyer confirms receipt and the program pays the seller;
if the buyer backs out first, the program pays the buyer back.

- **Mobile** — Flutter, Android, Solana Mobile Wallet Adapter
- **Onchain** — Anchor / Rust, four instructions, no backend
- **Network** — Devnet during development, mainnet for submission

## How it works

```
Seller                    Buyer                     Chain
  |                         |                         |
  |-- create listing ------>|                         |
  |   (QR: seller, amount,  |                         |
  |    nonce, cluster)      |                         |
  |                         |-- scan + approve ------>| initialize_escrow
  |                         |                         | deposit
  |                         |                         |   state: Funded
  |<---- item changes hands-|                         |
  |                         |-- confirm receipt ----->| confirm_receipt
  |<==== paid ==============|=========================|   state: Released
```

If something is wrong, the buyer calls `refund` instead and the funds come
back — `Funded -> Refunded`. Those four states are the whole lifecycle;
arbitration is deliberately out of scope for v1.

### Why the buyer opens the escrow

The scope document lists `initialize_escrow` as a seller action, but the user
flow has the buyer calling it when they scan. The buyer wins, because there is
no backend: the seller is offline at scan time and cannot co-sign, and the PDA
seeds need the buyer's key, which is unknown until the scan happens.

Nothing is lost by this. The seller's address is carried in the QR and written
into the account at initialization, and `confirm_receipt` will only ever pay
*that* address — enforced by `has_one = seller`. A buyer who tampers with the
QR just derives a different escrow and pays a different person.

## Layout

```
lib/
  core/        escrow model, lamport maths, QR payload codec
  solana/      program bindings, RPC repository, wallet adapter, controllers
  widgets/     status ring, scan frame, glass panels, particle burst
  features/    the four screens
  theme/       palette, type scale, ThemeData
program/
  programs/escrow_pay/src/   the Anchor program
  tests/                     the program's real specification
```

## Onchain program

PDA seeds — `[b"escrow", seller, buyer, nonce]`

```rust
EscrowAccount { seller, buyer, amount, state, created_at, nonce, bump }
```

| Instruction         | Signer | Effect                                  |
| ------------------- | ------ | --------------------------------------- |
| `initialize_escrow` | buyer  | Writes the terms. `-> Created`           |
| `deposit`           | buyer  | Moves lamports into the PDA. `-> Funded` |
| `confirm_receipt`   | buyer  | Pays the seller. `-> Released`           |
| `refund`            | buyer  | Pays the buyer back. `-> Refunded`       |

Payouts move only the escrowed amount and leave the rent deposit behind, so a
settled escrow stays readable and the app can still show what happened.

v1 settles in native SOL. `EscrowAccount` is laid out so an SPL/USDC vault can
be added without changing the PDA derivation — see [Not yet done](#not-yet-done).

## Getting set up

Prerequisites: Flutter 3.44+, Rust, the Solana CLI, Anchor 1.2, and an Android
device or emulator with a wallet app installed.

```bash
# Toolchain sanity check before anything else
npx solana-mobile@latest doctor
```

### Program

```bash
cd program
anchor build                    # generates the program keypair on first run
cd .. && ./scripts/sync_program_id.sh
cd program && anchor build      # rebuild so the binary carries the synced id

anchor test --validator legacy  # tests/escrow_pay.ts on a local validator
anchor deploy --provider.cluster devnet
```

[`scripts/sync_program_id.sh`](scripts/sync_program_id.sh) writes the program
id into all three places that need it: `declare_id!`, `Anchor.toml`, and
[`lib/solana/escrow_program.dart`](lib/solana/escrow_program.dart). The Dart
client hardcodes the id rather than reading the IDL at runtime, so a deploy to
a new id without running this leaves the app deriving PDAs for a program that
no longer exists — which surfaces as `ConstraintSeeds` errors that look like a
bug in the seeds.

Run it after every `anchor build` that regenerates the keypair, and after any
deploy to a new id.

Rust-side checks need no validator:

```bash
cd program && cargo test --lib   # pins the 98-byte EscrowAccount layout
```

### App

```bash
flutter pub get
flutter test              # pure logic: money, QR codec, account decoding, PDAs
flutter run               # Android device or Solana Mobile emulator
```

Mobile Wallet Adapter is Android-only. On iOS the plugin is a no-op and the app
shows a fallback message rather than pretending to connect.

## Testing

`flutter test` covers everything that does not need a chain:

- lamport rounding, so `0.1 SOL` is never 99999999 lamports
- QR encode/decode, including tampered and cross-cluster codes
- `EscrowAccount` byte layout, field by field
- Anchor discriminators, pinned to the bytes Anchor itself emits
- PDA derivation, including that swapping buyer and seller changes the address

`anchor test --validator legacy` covers the chain: every state transition, and
the ways each one can be abused — the seller releasing to themselves, a payout
redirected to a third wallet, double release, refund after release. 14 tests,
about 18 seconds.

The `--validator legacy` flag matters. Anchor 1.2 defaults to `surfpool` for
localnet, which is a separate install; `legacy` uses the `solana-test-validator`
that ships with the Solana CLI. Set `ANCHOR_TEST_VALIDATOR=legacy` to avoid
typing it.

`Anchor.toml` points `[provider]` at localnet on purpose. `anchor test` deploys
to whatever that says, so pointing it at devnet makes every test run depend on a
funded devnet wallet and the public faucet — which is rate limited. Deploy to
devnet explicitly with the flag above.

## Not yet done

- **USDC / SPL settlement.** v1 is SOL only. The account layout leaves room.
- **Persisted wallet sessions.** The MWA auth token lives in memory, so a
  relaunch means approving again.
- **Rive assets.** The status ring and scan frame are `CustomPainter`
  animations. They are the demo's centrepiece and worth replacing with Rive if
  time allows, but building those assets from scratch is not a good use of
  hackathon hours.
- **Seller-side status view.** The seller shows a QR and watches the buyer's
  screen; they cannot yet track the escrow from their own device.

Explicitly out of scope for v1: multi-item listings, ratings, in-app chat,
dispute arbitration beyond the buyer-triggered refund, and any offchain
backend.
