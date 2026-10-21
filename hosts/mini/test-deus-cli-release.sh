#!/usr/bin/env bash
# Offline test of the pinned pipeline's logic (no network, no Keychain, no nix
# shellcheck disable=SC2329,SC2154,SC2034,SC2030,SC2031
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
[ -z "$(printf '%s\n' "$ls" | pick_tag '' "$work/failed")" ] || fail "failed highest tag: timer must pick nothing, not fall back lower (N-2)"
grep -q 'waiting: highest candidate cli-v0.10.0' "$DCR_LOG" || fail "waiting not logged"
printf '%s\n' "$ls" | pick_tag '' "$work/failed" >/dev/null
[ "$(grep -c 'waiting: highest' "$DCR_LOG")" = 1 ] || fail "waiting must be logged once"
ls3="$(printf '%s\n' 'a refs/tags/cli-v1.1.0' 'b refs/tags/cli-v1.2.0')"
printf 'cli-v1.2.0 b\n' >"$work/failed3"
[ -z "$(printf '%s\n' "$ls3" | pick_tag 1.0.0 "$work/failed3")" ] || fail "failed 1.2.0 with 1.1.0 unpublished must pick nothing"
ls4="$(printf '%s\n' "$ls3" 'c refs/tags/cli-v1.2.1')"
[ "$(printf '%s\n' "$ls4" | pick_tag 1.0.0 "$work/failed3")" = "cli-v1.2.1 c" ] || fail "fixed higher tag must still be picked"
printf 'cli-v0.10.0 other\n' >"$work/failed"
[ "$(printf '%s\n' "$ls" | pick_tag '' "$work/failed")" = "cli-v0.10.0 ddd" ] || fail "same tag at a new commit must be retried"
# fail() records the failure; dry runs and transient stages do not
(notify() { :; }; dry=0; cur_tag=cli-v9.9.9; cur_sha=abc; stage=build; dcr_fail "x" 2>/dev/null) || true
grep -qxF 'cli-v9.9.9 abc' "$DCR_STATE_DIR/failed" || fail "failure not recorded"
(notify() { :; }; dry=0; cur_tag=cli-v9.9.8; cur_sha=abc; stage=publish; dcr_fail "x" 2>/dev/null) || true
grep -q 'cli-v9.9.8' "$DCR_STATE_DIR/failed" && fail "publish failure must stay retryable"
(notify() { :; }; dry=1; cur_tag=cli-v9.9.7; cur_sha=abc; stage=build; dcr_fail "x" 2>/dev/null) || true
grep -q 'cli-v9.9.7' "$DCR_STATE_DIR/failed" && fail "dry run must not record"

# --- lock_ok: only pinned github sources (review P1-2)
cat >"$work/lock-ok.json" <<'J'
{"root":"root","version":7,"nodes":{"root":{"inputs":{"a":"a"}},"a":{"locked":{"type":"github","owner":"o","repo":"r","rev":"1","narHash":"sha256-x"}},"b":{"locked":{"type":"git","url":"ssh://git@github.com/o/r","rev":"1","narHash":"sha256-y"}}}}
J
lock_ok "$work/lock-ok.json" || fail "good lock refused"
jq '.nodes.a.locked={"type":"path","path":"/Users/daniel/.ssh","narHash":"sha256-x"}' "$work/lock-ok.json" >"$work/lock-path.json"
lock_ok "$work/lock-path.json" && fail "path input accepted"
jq '.nodes.a.locked={"type":"tarball","url":"https://evil/x.tgz","narHash":"sha256-x"}' "$work/lock-ok.json" >"$work/lock-tar.json"
lock_ok "$work/lock-tar.json" && fail "tarball input accepted"
jq '.nodes.b.locked.url="git+file:///Users/daniel/.ssh"' "$work/lock-ok.json" >"$work/lock-gf.json"
lock_ok "$work/lock-gf.json" && fail "git file url accepted"
jq 'del(.nodes.a.locked.narHash)' "$work/lock-ok.json" >"$work/lock-nh.json"
lock_ok "$work/lock-nh.json" && fail "missing narHash accepted"
jq '.nodes.c={}' "$work/lock-ok.json" >"$work/lock-nl.json"
lock_ok "$work/lock-nl.json" && fail "node without locked accepted"
lock_ok "$repo/flake.lock" || fail "the real malli-deus flake.lock is refused"

# --- unexpected exits still log, notify and record (review P2-1)
: >"$DCR_LOG"
( fail() { dcr_fail "$@"; }; notify() { echo notified >>"$work/notified.rec"; }; trap on_exit EXIT; dry=0; cur_tag=cli-v8.8.8; cur_sha=def; stage=manifest; exit 7 ) 2>/dev/null || true
grep -q 'FAIL \[manifest\] cli-v8.8.8 exited unexpectedly with status 7' "$DCR_LOG" || fail "unexpected exit not logged"
[ -s "$work/notified.rec" ] || fail "unexpected exit not notified"
( fail() { dcr_fail "$@"; }; notify() { :; }; trap on_exit EXIT; exit 0 ) || fail "exit 0 must stay quiet"
( fail() { dcr_fail "$@"; }; notify() { :; }; trap on_exit EXIT; dry=0; cur_tag=cli-v8.8.7; cur_sha=def; stage=manifest; dcr_fail "once" ) 2>/dev/null || true
[ "$(grep -c 'cli-v8.8.7' "$DCR_LOG")" -le 2 ] || fail "fail() then exit must not double-report"

# --- signals are interrupts, not failures (review N-1)
: >"$DCR_LOG"; rm -f "$work/notified.rec" "$DCR_STATE_DIR/failed"
( fail() { dcr_fail "$@"; }; notify() { echo notified >>"$work/notified.rec"; }; trap on_exit EXIT; trap 'signalled=1; exit 143' TERM INT HUP; dry=0; cur_tag=cli-v7.7.7; cur_sha=abc; stage=build; kill -TERM "$BASHPID" ) 2>/dev/null || true
grep -q 'interrupted' "$DCR_LOG" || fail "interrupt not logged"
[ ! -e "$work/notified.rec" ] || fail "interrupt must not notify"
grep -q 'cli-v7.7.7' "$DCR_STATE_DIR/failed" 2>/dev/null && fail "interrupt must not record failed"
( fail() { dcr_fail "$@"; }; notify() { echo notified >>"$work/notified.rec"; }; trap on_exit EXIT; dry=0; cur_tag=cli-v7.7.6; cur_sha=abc; stage=build; exit 143 ) 2>/dev/null || true
[ ! -e "$work/notified.rec" ] || fail "rc 143 must not notify"

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

# --- publish: one rsync --delay-updates call, binaries then sig then manifest, right destination
fakebin="$work/fakebin"; mkdir "$fakebin"
cat >"$fakebin/rsync" <<'R'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RSYNC_REC"
R
chmod +x "$fakebin/rsync"
export RSYNC_REC="$work/rsync.rec"; : >"$RSYNC_REC"
rel2="$work/rel2"; mkdir "$rel2"
(PATH="$fakebin:$PATH" DCR_PUBLISH_USER=u DCR_PUBLISH_HOST=h publish "$rel2") || fail "publish failed"
[ "$(wc -l <"$RSYNC_REC")" = 1 ] || fail "publish: expected one rsync call"
grep -q -- "--delay-updates" "$RSYNC_REC" || fail "publish: --delay-updates missing"
grep -q "$rel2/deus-linux-amd64 .*deus-darwin-amd64 $rel2/manifest.json.sig $rel2/manifest.json u@h:./\$" "$RSYNC_REC" || fail "publish: order binaries, sig, manifest"
# --- lock_too_old: a lock with a live (reused) pid still goes stale (review P2-6)
mkdir "$work/lk"
lock_too_old "$work/lk" && fail "fresh lock reported old"
touch -d '7 hours ago' "$work/lk" 2>/dev/null || touch -t "$(date -v-7H +%Y%m%d%H%M)" "$work/lk"
lock_too_old "$work/lk" || fail "7 h old lock not reported old"

# --- verify_release: runs only when the pinned signer has `verify` (review P2-3)
DCR_RELEASE_BIN="$work/deus-release" verify_release "$rel" "$pub" 2>/dev/null && fail "tampered dir passed verify_release"
rel3="$work/rel3"; mkdir "$rel3"; for p in $platforms; do printf 'b %s\n' "$p" >"$rel3/deus-$p"; done
make_manifest "$rel3" 7.7.7 "$work/key" || fail "make_manifest rel3"
verify_release "$rel3" "$pub" || fail "good dir failed verify_release"
printf '#!/usr/bin/env bash\necho "usage: deus-release keygen|pubkey|manifest" >&2; exit 1\n' >"$fakebin/old-signer"; chmod +x "$fakebin/old-signer"
DCR_RELEASE_BIN="$fakebin/old-signer" signer_has_verify && fail "old signer reported verify"
DCR_RELEASE_BIN="$fakebin/old-signer" verify_release "$rel3" "$pub" 2>/dev/null || fail "old signer must skip verify, not fail"
signer_has_verify || fail "new signer should report verify"

# --- read_key: key file only exists while read (review P2-2)
printf '#!/usr/bin/env bash\nprintf "seedseed\\n"\n' >"$fakebin/security"; chmod +x "$fakebin/security"
( PATH="$fakebin:$PATH"; read_key "$work/k1" ) || fail "read_key failed"
[ "$(stat -c %a "$work/k1" 2>/dev/null || stat -f %Lp "$work/k1")" = 600 ] || fail "key file mode"
printf '#!/usr/bin/env bash\nexit 44\n' >"$fakebin/security"
( PATH="$fakebin:$PATH"; read_key "$work/k2" ) && fail "read_key succeeded without a key"
[ ! -e "$work/k2" ] || fail "failed read_key left a file"
rm -f "$fakebin/security"

echo "all ok"
