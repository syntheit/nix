#!/usr/bin/env bash
# Offline test of the pinned pipeline's logic (no network, no Keychain, no nix
# build): tag selection, version ordering, and manifest generation, then the
# result is checked by `deus-release verify`, which uses the same
# internal/cli/release code as the CLI and the web console.
#
# Usage: test-deus-cli-release.sh <malli-deus checkout>
# Needs: go, jq, coreutils. Run on Linux or macOS.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${1:?usage: $0 <malli-deus checkout>}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

(cd "$repo" && GOFLAGS=-buildvcs=false go build -o "$work/deus-release" ./cmd/deus-release)
export DCR_SOURCE_ONLY=1 DCR_RELEASE_BIN="$work/deus-release" DCR_LOG="$work/log" DCR_STATE_DIR="$work/state"
# shellcheck source=/dev/null
source "$here/deus-cli-release.sh"

eval "$(declare -f fail | sed "1s/^fail/dcr_fail/")"
fail() { echo "FAIL: $*" >&2; exit 1; }

# --- version ordering and tag picking
version_gt 0.10.0 0.9.9 || fail "0.10.0 > 0.9.9"
version_gt 1.0.0 1.0.0 && fail "equal is not greater"
version_gt 0.9.9 0.10.0 && fail "0.9.9 < 0.10.0"
ls="$(printf '%s\n' \
  'aaa refs/tags/cli-v0.1.0' \
  'bbb refs/tags/cli-v0.2.0' 'ccc refs/tags/cli-v0.2.0^{}' \
  'ddd refs/tags/cli-v0.10.0' \
  'eee refs/tags/cli-v1.0.0-rc1' \
  'fff refs/tags/cli-vX.Y.Z' \
  'ggg refs/tags/other')"
[ "$(printf '%s\n' "$ls" | pick_tag '')" = "cli-v0.10.0 ddd" ] || fail "pick highest"
[ "$(printf '%s\n' "$ls" | pick_tag 0.10.0)" = "" ] || fail "nothing newer than 0.10.0"
[ "$(printf '%s\n' "$ls" | pick_tag 0.1.0)" = "cli-v0.10.0 ddd" ] || fail "pick above last"
ls2="$(printf '%s\n' 'bbb refs/tags/cli-v0.2.0' 'ccc refs/tags/cli-v0.2.0^{}')"
[ "$(printf '%s\n' "$ls2" | pick_tag '')" = "cli-v0.2.0 ccc" ] || fail "annotated tag must use the peeled commit"

# --- manifest from 4 fake binaries, signed with a throwaway key
rel="$work/rel"
mkdir "$rel"
# shellcheck disable=SC2154
for p in $platforms; do printf 'fake binary %s\n' "$p" >"$rel/deus-$p"; chmod 0755 "$rel/deus-$p"; done
pub="$("$work/deus-release" keygen "$work/key")"
make_manifest "$rel" 4.5.6 "$work/key" || fail "make_manifest"
"$work/deus-release" verify -pubkey "$pub" -dir "$rel" | grep -qx 'ok 4.5.6' || fail "verify"
[ "$("$work/deus-release" pubkey "$work/key")" = "$pub" ] || fail "pubkey"
[ "$(jq -r '.files["darwin-arm64"].url' "$rel/manifest.json")" = deus-darwin-arm64 ] || fail "url is a bare file name"
# tamper after signing must fail verify
echo x >>"$rel/deus-linux-arm64"
"$work/deus-release" verify -pubkey "$pub" -dir "$rel" 2>/dev/null && fail "tampered binary accepted"
# --- leading zeros are not tags (the Go signer rejects them), failed tags are skipped (review P1-1)
mkdir -p "$DCR_STATE_DIR"
lz="$(printf '%s\n' 'a1 refs/tags/cli-v01.2.0' 'a2 refs/tags/cli-v1.02.0' 'a3 refs/tags/cli-v1.2.00' 'a4 refs/tags/cli-v0.0.1')"
[ "$(printf '%s\n' "$lz" | pick_tag '')" = "cli-v0.0.1 a4" ] || fail "leading-zero tags must be ignored"
[[ "cli-v01.2.0" =~ $tag_re ]] && fail "tag_re accepts leading zero"
printf 'cli-v0.10.0 ddd\n' >"$work/failed"
[ "$(printf '%s\n' "$ls" | pick_tag '' "$work/failed")" = "cli-v0.2.0 bbb" ] || [ "$(printf '%s\n' "$ls" | pick_tag '' "$work/failed")" = "cli-v0.2.0 ccc" ] || fail "failed tag+sha must be skipped, next highest picked"
printf 'cli-v0.10.0 other\n' >"$work/failed"
[ "$(printf '%s\n' "$ls" | pick_tag '' "$work/failed")" = "cli-v0.10.0 ddd" ] || fail "same tag at a new commit must be retried"
# fail() records the failure; dry runs and transient stages do not
(notify() { :; }; dry=0; cur_tag=cli-v9.9.9; cur_sha=abc; stage=build; dcr_fail "x" 2>/dev/null) || true
grep -qxF 'cli-v9.9.9 abc' "$DCR_STATE_DIR/failed" || fail "failure not recorded"
(notify() { :; }; dry=0; cur_tag=cli-v9.9.8; cur_sha=abc; stage=publish-binaries; dcr_fail "x" 2>/dev/null) || true
grep -q 'cli-v9.9.8' "$DCR_STATE_DIR/failed" && fail "publish failure must stay retryable"
(notify() { :; }; dry=1; cur_tag=cli-v9.9.7; cur_sha=abc; stage=build; dcr_fail "x" 2>/dev/null) || true
grep -q 'cli-v9.9.7' "$DCR_STATE_DIR/failed" && fail "dry run must not record"

# --- install_built: store-path, symlink and magic checks (review P0-2)
export DCR_STORE_PREFIX="$work/store/"
mkdir -p "$work/store/good/bin" "$work/store/sym/bin" "$work/store/bad/bin" "$work/store/mac/bin" "$work/outside"
printf '\x7fELFxxxx' >"$work/store/good/bin/deus"
printf '\xcf\xfa\xed\xfexxxx' >"$work/store/mac/bin/deus"
printf 'secret' >"$work/outside/secret"
ln -s "$work/outside/secret" "$work/store/sym/bin/deus"
printf 'MZxxxxxx' >"$work/store/bad/bin/deus"
install_built "$work/store/good" "$work/o1" linux-amd64 || fail "good ELF refused"
[ -x "$work/o1" ] || fail "install_built did not copy"
install_built "$work/store/mac" "$work/o2" darwin-arm64 || fail "good Mach-O refused"
install_built "$work/store/sym" "$work/o3" linux-arm64 && fail "symlinked output accepted"
[ ! -e "$work/o3" ] || fail "symlink target was copied"
install_built "$work/store/bad" "$work/o4" linux-amd64 && fail "wrong magic accepted"
install_built "$work/store/good" "$work/o5" darwin-arm64 && fail "ELF accepted for darwin"
install_built "$work/store/mac" "$work/o6" linux-amd64 && fail "Mach-O accepted for linux"
ln -s "$work/store/good" "$work/store/dirlink"
install_built "$work/store/dirlink" "$work/o7" linux-amd64 && fail "symlinked out dir accepted"
mkdir -p "$work/outside/bin"; printf '\x7fELFxxxx' >"$work/outside/bin/deus"
install_built "$work/outside" "$work/o8" linux-amd64 && fail "path outside the store accepted"
unset DCR_STORE_PREFIX

# --- publish: three rsync calls in order, right destination (fake rsync on PATH)
fakebin="$work/fakebin"; mkdir "$fakebin"
cat >"$fakebin/rsync" <<'R'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RSYNC_REC"
R
chmod +x "$fakebin/rsync"
export RSYNC_REC="$work/rsync.rec"; : >"$RSYNC_REC"
rel2="$work/rel2"; mkdir "$rel2"
(PATH="$fakebin:$PATH" DCR_PUBLISH_USER=u DCR_PUBLISH_HOST=h publish "$rel2") || fail "publish failed"
[ "$(wc -l <"$RSYNC_REC")" = 3 ] || fail "publish: expected 3 rsync calls"
sed -n 1p "$RSYNC_REC" | grep -q "$rel2/deus-linux-amd64 .*deus-darwin-amd64 u@h:./\$" || fail "publish: binaries first"
sed -n 2p "$RSYNC_REC" | grep -q "$rel2/manifest.json.sig u@h:./\$" || fail "publish: sig second"
sed -n 3p "$RSYNC_REC" | grep -q "$rel2/manifest.json u@h:./\$" || fail "publish: manifest last"
echo "all ok"
