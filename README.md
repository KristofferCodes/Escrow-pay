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

Deployed on devnet at `5pY9AH8qYE6u17MYknPeoy9HufpguEAt9Lj1vnoXqzNC`.

### Program

```bash
cd program
anchor build                    # generates the program keypair on first run
cd .. && ./scripts/sync_program_id.sh
cd program && anchor build      # rebuild so the binary carries the synced id

anchor test --validator legacy  # tests/escrow_pay.ts on a local validator
anchor deploy --provider.cluster devnet
```

If the deploy fails with `Max retries exceeded`, that is the public devnet RPC
dropping write transactions, not a problem with the program. `solana program
deploy` sends them to validator TPUs by default; route them through the RPC
instead and resume the partial buffer it left behind:

```bash
solana program deploy target/deploy/escrow_pay.so \
  --program-id target/deploy/escrow_pay-keypair.json \
  --buffer target/deploy/escrow_pay-upgrade-buffer.json \
  --url devnet --use-rpc --max-sign-attempts 200 --with-compute-unit-price 5000
```

A 152 KB program is a few hundred write transactions. Avoid polling the same
RPC for status while it runs — that competes for the same rate limit.

Check nothing was stranded afterwards, since an abandoned buffer holds its
rent: `solana program show --buffers --url devnet`.

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

### Platform support

**Android is the only platform where this app actually works.** Mobile Wallet
Adapter has no iOS equivalent — the plugin compiles on iOS and then does
nothing — and the Solana dApp Store is Android-only, so Android is also the
only place the app can ship.

An `ios/` target exists anyway, because the UI is worth iterating on in the
simulator:

| | Android | iOS |
| --- | --- | --- |
| Screens, motion, theming | works | works |
| QR generation (`qr_flutter`) | works | works |
| QR scanning (`mobile_scanner`) | works | works |
| Connect wallet | works | **no-op** |
| Fund / release / refund | works | **no-op** |

On iOS every wallet call is refused up front by `assertMwaSupported()` and the
app says why, rather than hanging on a connection that will never arrive. That
means no funding, no release and no refund — the entire escrow flow. Treat the
iOS build as a design surface, not a testable app.

Do the happy-path testing on an Android device or the Solana Mobile emulator.

## Distributing a build

The app is Android-only, so distribution means an APK.

A universal release APK is ~69 MB because it carries three CPU architectures,
one of which (`x86_64`) only ever runs on emulators. Split it and send the
`arm64-v8a` one — ~25 MB, and it covers every Android phone of the last
several years:

```bash
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Firebase App Distribution needs no code change and no Firebase SDK — only an
App ID from registering the Android package in the console:

```bash
firebase login
firebase appdistribution:distribute \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --app <FIREBASE_APP_ID> \
  --testers "someone@example.com" \
  --release-notes "Escrow Pay — devnet"
```

For one or two testers, sending the APK directly works just as well.

### What a tester needs

Without all four, the app fails in ways that look like bugs:

1. An Android phone, API 23 or newer.
2. A wallet app — Solflare or Phantom.
3. **That wallet switched to devnet.** Both default to mainnet. This is the
   one people miss.
4. A little devnet SOL in it. The buyer funds the escrow, so the tester pays.

They also need the program deployed to devnet, and the seller QR — generate
one with `tool/make_test_offer.dart` and send them the HTML file or a
screenshot.

### Release signing

Flutter's scaffold signs release builds with the **debug** key. Firebase
accepts that, but it is not acceptable for the dApp Store, and a debug-signed
build cannot be upgraded over by a properly signed one — testers would have to
uninstall first. Worth doing before handing builds around.

```bash
keytool -genkey -v -keystore ~/escrow-pay-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias escrow-pay
```

Then write `android/key.properties` (gitignored — never commit it):

```properties
storePassword=<the password you chose>
keyPassword=<the password you chose>
keyAlias=escrow-pay
storeFile=/Users/you/escrow-pay-release.jks
```

The Gradle config picks it up automatically and falls back to the debug key
when the file is absent, so a fresh clone still builds.

**Back up the keystore.** Losing it means losing the ability to ship an update
to anyone who installed a build signed with it.

## Testing the escrow flow

**One Android device is enough.** The seller side never signs anything — it
reads a wallet address, puts it in a QR code and stops. Only the buyer
transacts. So the "seller" can be a throwaway keypair and a QR on your laptop
screen.

The program does reject `seller == buyer` (`SameParty`), so the two addresses
have to differ.

### 1. A seller to pay

```bash
solana-keygen new --no-bip39-passphrase --silent --outfile .seller-test.json
solana address -k .seller-test.json
```

Nothing is deployed for this key and it holds nothing — it is just somewhere
for the escrow to pay, and something whose balance you can watch.

### 2. Put the offer on screen

```bash
dart run tool/make_test_offer.dart <seller-address> 0.05 "Pixel 8 Pro"
open build/test-offer.html
```

The QR is built with the app's own `EscrowOffer.encode`, so it cannot drift
from what the scanner accepts.

### 3. Fund the buyer

Connect the wallet on the device, then airdrop to the address it shows. The
public faucet rate limits by IP; [faucet.solana.com](https://faucet.solana.com)
is the fallback.

```bash
solana airdrop 1 <buyer-address> --url devnet
```

### 4. Run the app and walk the flow

```bash
flutter run          # device connected over USB with debugging on
```

Scan → confirm the amount → **Fund the escrow** → approve in the wallet. The
ring moves to Funded. Then **Confirm receipt & release**, and it settles.

### 5. Check the chain agrees

```bash
solana balance $(solana address -k .seller-test.json) --url devnet
```

The seller should be up by exactly the escrowed amount. The escrow PDA keeps
its rent, so the settled record stays readable — tap the escrow address in the
app to copy it and open it in the explorer.

Re-run from step 2 for the refund path: fund, then **Something is wrong —
refund me** instead, and confirm the buyer is made whole less fees.

### On emulators

An emulator works, with two wrinkles. Its camera is virtual, so feed it the QR
directly:

```bash
emulator -avd <name> -camera-back imagefile:/absolute/path/to/qr.png
```

And Solana Mobile's Mock MWA Wallet "does not store a persistent keypair and
the wallet is reset each time the app is exited" — fine for one pass, painful
for repeats, since the buyer address changes and needs a fresh airdrop every
time. Installing Solflare on the emulator avoids that. A physical device avoids
both wrinkles and is what the demo gets recorded on anyway.

## Testing

`flutter test` covers everything that does not need a chain:

- lamport rounding, so `0.1 SOL` is never 99999999 lamports
- QR encode/decode, including tampered and cross-cluster codes
- `EscrowAccount` byte layout, field by field
- Anchor discriminators, pinned to the bytes Anchor itself emits
- PDA derivation, including that swapping buyer and seller changes the address

`node program/scripts/devnet-smoke.js` proves the **deployed** program works,
not just a local build of it: it opens, funds and releases a real escrow on
devnet using the same PDA seeds and instruction layout the Flutter client
builds by hand, and asserts the seller received exactly the escrowed amount.
Run it after every deploy — a mismatch between the app and the live program
surfaces here instead of in someone's hands.

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
