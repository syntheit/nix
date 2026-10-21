#!/usr/bin/env bash
# Run ON MINI. Signs and notarizes each given binary.
# Note: bare Mach-O binaries cannot be stapled; Gatekeeper checks the ticket online.
# Usage: sign-and-notarize.sh <binary>...
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 <binary>..." >&2; exit 2; }

IDENT="Developer ID Application: Daniel Miller (6NHZWHQX37)"
KC="$HOME/Library/Keychains/deus-signing.keychain-db"
PWFILE="$HOME/.config/deus-signing/keychain-pass"

[ -f "$PWFILE" ] || { echo "error: missing $PWFILE" >&2; exit 1; }
security unlock-keychain -p "$(cat "$PWFILE")" "$KC"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for bin in "$@"; do
  [ -f "$bin" ] || { echo "error: not a file: $bin" >&2; exit 1; }
  name="$(basename "$bin")"
  echo "== $name: signing"
  codesign --force --options runtime --timestamp --keychain "$KC" -s "$IDENT" "$bin"
  codesign --verify --strict --verbose=2 "$bin"

  echo "== $name: notarizing"
  zip="$tmp/$name.zip"
  ditto -c -k --keepParent "$bin" "$zip"
  out="$(xcrun notarytool submit "$zip" --keychain-profile deus-notary --keychain "$KC" --wait --timeout 30m 2>&1)" || {
    echo "$out" >&2
    exit 1
  }
  echo "$out"
  if ! grep -q 'status: Accepted' <<<"$out"; then
    id="$(awk '/^ *id:/ {print $2; exit}' <<<"$out")"
    echo "error: notarization not accepted for $name" >&2
    if [ -n "$id" ]; then
      xcrun notarytool log "$id" --keychain-profile deus-notary --keychain "$KC" >&2 || true
    fi
    exit 1
  fi
  echo "== $name: accepted"
done
