#!/usr/bin/env bash
#
# Keeps the program id consistent across the three places that need it.
#
# The Dart client hardcodes the program id instead of reading the IDL at
# runtime, so a fresh deploy leaves the app deriving PDAs for a program that no
# longer exists — which surfaces as ConstraintSeeds errors that look like a bug
# in the seeds. Run this after every `anchor build` that regenerates the
# keypair, and after any deploy to a new id.
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
#
# Each target is verified after rewriting rather than trusted: a pattern that
# silently stops matching (a formatter rewrapping a line, say) would otherwise
# leave a stale id behind and report success, which is the exact failure this
# script exists to prevent.
patch() {
  local label="$1" file="$2" pattern="$3" replacement="$4"

  if [[ ! -f "$file" ]]; then
    echo "  MISSING: ${file#"$root"/}" >&2
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  sed -E "s|$pattern|$replacement|" "$file" >"$tmp"
  mv "$tmp" "$file"

  if ! grep -q "$program_id" "$file"; then
    echo "  FAILED:  ${file#"$root"/} — $label pattern did not match" >&2
    return 1
  fi
  echo "  ok:      ${file#"$root"/}"
}

failed=0

patch "declare_id!" "$rust_program" \
  'declare_id!\("[A-Za-z0-9]+"\)' \
  "declare_id!(\"$program_id\")" || failed=1

# Matched by name, not by line shape: dart format moves the string on and off
# its own line depending on how long the id is.
patch "programIdBase58" "$dart_client" \
  "(programIdBase58 =[[:space:]]*)'[A-Za-z0-9]{32,44}'" \
  "\\1'$program_id'" || failed=1

patch "programs table" "$anchor_toml" \
  'escrow_pay = "[A-Za-z0-9]+"' \
  "escrow_pay = \"$program_id\"" || failed=1

if (( failed )); then
  echo >&2
  echo "Program id was NOT fully synced. Fix the patterns above before building." >&2
  exit 1
fi

echo
echo "Now rebuild so the binary carries the id:  (cd program && anchor build)"
