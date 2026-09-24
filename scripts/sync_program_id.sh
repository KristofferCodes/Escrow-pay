#!/usr/bin/env bash
#
# Keeps the program id consistent across the three places that need it.
#
# The Dart client hardcodes the program id instead of reading the IDL at
# runtime, so a fresh deploy leaves the app deriving PDAs for a program that no
# longer exists — which surfaces as ConstraintSeeds errors that look like a bug
# in the seeds. Run this after every `anchor keys sync` or deploy to a new id.
#
#   ./scripts/sync_program_id.sh

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
keypair="$root/program/target/deploy/escrow_pay-keypair.json"
dart_client="$root/lib/solana/escrow_program.dart"
rust_program="$root/program/programs/escrow_pay/src/lib.rs"
anchor_toml="$root/program/Anchor.toml"

if [[ ! -f "$keypair" ]]; then
  echo "No program keypair at $keypair" >&2
  echo "Run 'anchor build' in ./program first." >&2
  exit 1
fi

if ! command -v solana >/dev/null 2>&1; then
  echo "The solana CLI is not on PATH." >&2
  exit 1
fi

program_id="$(solana address -k "$keypair")"
echo "Program id: $program_id"

# BSD and GNU sed disagree about -i, so write through a temp file instead.
patch() {
  local file="$1" pattern="$2" replacement="$3"
  if [[ ! -f "$file" ]]; then
    echo "  skipped (missing): ${file#$root/}"
    return
  fi
  local tmp
  tmp="$(mktemp)"
  sed -E "s|$pattern|$replacement|" "$file" >"$tmp"
  if cmp -s "$file" "$tmp"; then
    echo "  unchanged: ${file#$root/}"
    rm -f "$tmp"
  else
    mv "$tmp" "$file"
    echo "  updated:   ${file#$root/}"
  fi
}

patch "$rust_program" \
  'declare_id!\("[A-Za-z0-9]+"\)' \
  "declare_id!(\"$program_id\")"

# Matches the lone quoted base58 line under `programIdBase58`.
patch "$dart_client" \
  "^( +)'[A-Za-z0-9]{32,44}';$" \
  "\\1'$program_id';"

patch "$anchor_toml" \
  'escrow_pay = "[A-Za-z0-9]+"' \
  "escrow_pay = \"$program_id\""

echo
echo "Now rebuild so the binary carries the id:  (cd program && anchor build)"
