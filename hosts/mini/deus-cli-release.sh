# Pinned deus CLI release pipeline (runs on mini as a launchd user agent).
#
# SECURITY BOUNDARY: this file and the deus-release signer live in ~/nix, not
# in the release tag. Code from the tag runs only inside `nix build` (nixbld
# build users, no access to the login Keychain or our temp files). The tag's
# scripts/cli-release.sh is never executed. The release key exists only as a
# 0700 temp file read by the pinned signer.
#
# Usage: deus-cli-release [--dry-run] [--tag cli-vX.Y.Z] [--skip-apple]
#   (no flags)   look for a new cli-v* tag and publish it
#   --dry-run    every gate, build, Apple signing, manifest and signature;
#                no rsync, no state update. Output stays under work/dry-<ver>.
#   --tag T      run exactly that tag instead of picking the highest new one
#   --skip-apple dry-run only: skip codesign/notarization
#
# Config comes from the environment (set by the nix wrapper); defaults below.
set -euo pipefail

export PATH="${PATH:-}:/usr/bin:/bin:/usr/sbin:/sbin:/nix/var/nix/profiles/default/bin"

: "${DCR_REPO_URL:=git@github-malli-deus:NRE-Product/malli-deus.git}"
: "${DCR_STATE_DIR:=$HOME/Library/Application Support/deus-cli-release}"
: "${DCR_LOG:=$HOME/Library/Logs/deus-cli-release.log}"
: "${DCR_PUBLISH_HOST:=vista}"
: "${DCR_PUBLISH_USER:=deus-release}"
: "${DCR_SSH_KEY:=$HOME/.ssh/deus-release_ed25519}"
: "${DCR_KEYCHAIN_SERVICE:=deus-cli-release}"
: "${DCR_KEYCHAIN_ACCOUNT:=release-key}"
: "${DCR_MIN_SUPPORTED:=}"
# Pinned tools (nix wrapper sets these; bare names work for manual runs).
: "${DCR_RELEASE_BIN:=deus-release}"
: "${DCR_SIGN_BIN:=deus-cli-sign-and-notarize}"
: "${DCR_STORE_PREFIX:=/nix/store/}"

tag_re='^cli-v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
ver_re='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
platforms="linux-amd64 linux-arm64 darwin-arm64 darwin-amd64"

dry=0
only_tag=""
skip_apple=0
tmp=""
lockdir=""
cur_tag=""
cur_sha=""
stage="start"

log() {
  mkdir -p "$(dirname "$DCR_LOG")"
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$*" >>"$DCR_LOG"
  printf '%s\n' "$*" >&2
}

notify() {
  # Best effort; the message never contains secrets.
  osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title "deus CLI release"' \
    -e 'end run' "$1" >/dev/null 2>&1 || true
}

fail() {
  log "FAIL [$stage] ${cur_tag:+$cur_tag }$*"
  # One notification per tag+commit+stage, not one every 5 minutes.
  marker="$DCR_STATE_DIR/notified"
  key="$cur_tag $cur_sha $stage"
  if [ "$dry" = 0 ] && ! grep -qxF "$key" "$marker" 2>/dev/null; then
    printf '%s\n' "$key" >>"$marker"
    notify "FAILED at $stage: ${cur_tag:-no tag}. See ~/Library/Logs/deus-cli-release.log"
  fi
  # Timer runs skip a tag+commit that failed deterministically (review P1-1):
  # no notarization storm, and a broken high tag does not block a fixed higher
  # tag. Only `--tag` retries it. Transient stages (network, Keychain, vista
  # upload) are not recorded; those retry on the next timer run.
  if [ "$dry" = 0 ] && [ -n "$cur_tag" ] && [ -n "$cur_sha" ]; then
    case "$stage" in
      start | ls-remote | clone | keychain | publish-*) ;;
      *)
        if ! grep -qxF "$cur_tag $cur_sha" "$DCR_STATE_DIR/failed" 2>/dev/null; then
          printf '%s %s\n' "$cur_tag" "$cur_sha" >>"$DCR_STATE_DIR/failed"
          log "$cur_tag at $cur_sha is recorded as failed; timer runs skip it until a new commit or --tag"
        fi
        ;;
    esac
  fi
  exit 1
}

cleanup() {
  [ -z "$tmp" ] || rm -rf "$tmp"
  [ -z "$lockdir" ] || rm -rf "$lockdir"
}

# --- helpers (sourced by the test with DCR_SOURCE_ONLY=1) -------------------

# version_gt A B: true when A is strictly greater than B (plain X.Y.Z).
version_gt() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# repo_version FILE: first non-comment, non-empty line (same rule as go-common.nix).
repo_version() {
  grep -v '^#' "$1" | grep -v '^$' | head -n1 | tr -d '[:space:]'
}

# pick_tag: reads `git ls-remote --tags` output on stdin plus the last
# published version in $1 and an optional failed-list file in $2 ("<tag> <sha>"
# lines); prints "<tag> <sha>" for the highest valid, not-failed tag
# greater than it. Peeled (^{}) entries win over the tag object.
pick_tag() {
  local last="$1" failed="${2:-}" ref sha name peeled best="" bestsha="" v
  declare -A direct peel
  while read -r sha ref; do
    [ -n "$ref" ] || continue
    name="${ref#refs/tags/}"
    if [[ "$name" == *'^{}' ]]; then peel["${name%'^{}'}"]="$sha"; else direct["$name"]="$sha"; fi
  done
  for name in "${!direct[@]}"; do
    [[ "$name" =~ $tag_re ]] || continue
    v="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    if [ -n "$last" ] && ! version_gt "$v" "$last"; then continue; fi
    peeled="${peel[$name]:-${direct[$name]}}"
    if [ -n "$failed" ] && grep -qxF "$name $peeled" "$failed" 2>/dev/null; then continue; fi
    if [ -z "$best" ] || version_gt "$v" "${best#cli-v}"; then
      best="$name"
      bestsha="$peeled"
    fi
  done
  [ -n "$best" ] && printf '%s %s\n' "$best" "$bestsha"
  return 0
}

# make_manifest DIR VERSION KEYFILE: writes DIR/manifest.json and .sig with the
# pinned signer, then checks the result against the files on disk.
make_manifest() {
  local dir="$1" version="$2" keyfile="$3" p want got
  "$DCR_RELEASE_BIN" manifest -version "$version" -min-supported "$DCR_MIN_SUPPORTED" -dir "$dir" -key "$keyfile"
  [ -s "$dir/manifest.json" ] && [ -s "$dir/manifest.json.sig" ] || return 1
  [ "$(jq -r .version "$dir/manifest.json")" = "$version" ] || return 1
  for p in $platforms; do
    want="$(jq -r --arg p "$p" '.files[$p].sha256' "$dir/manifest.json")"
    got="$(sha256sum "$dir/deus-$p" | cut -d' ' -f1)"
    [ "$want" = "$got" ] || return 1
    [ "$(jq -r --arg p "$p" '.files[$p].url' "$dir/manifest.json")" = "deus-$p" ] || return 1
  done
}

# magic_ok PLATFORM FILE: first 4 bytes match the platform's executable format.
magic_ok() {
  local m
  m="$(head -c4 "$2" | od -An -tx1 | tr -d ' \n')"
  case "$1" in
    linux-*) [ "$m" = 7f454c46 ] ;;
    darwin-*) [ "$m" = cffaedfe ] || [ "$m" = feedfacf ] ;;
    *) return 1 ;;
  esac
}

# install_built OUTPATH DEST PLATFORM: copies OUTPATH/bin/deus to DEST only if it
# is a regular, non-symlink file that really lives in the nix store and has the
# right executable magic. Tag code controls the build output, so a symlink to
# ~/.ssh/... or a Keychain file must never be followed (review P0-2).
install_built() {
  local path="$1" dest="$2" plat="$3" f="$1/bin/deus" real realroot
  [ ! -L "$path" ] && [ ! -L "$path/bin" ] && [ ! -L "$f" ] || { log "refusing symlinked build output for $plat"; return 1; }
  real="$(realpath -e "$f" 2>/dev/null)" || { log "no bin/deus for $plat"; return 1; }
  realroot="$(realpath -e "$path")" || return 1
  case "$real" in "$DCR_STORE_PREFIX"*) ;; *) log "build output for $plat resolves outside the store"; return 1 ;; esac
  [ "$real" = "$realroot/bin/deus" ] || { log "build output for $plat is not at its own path"; return 1; }
  [ -f "$real" ] || { log "bin/deus for $plat is not a regular file"; return 1; }
  magic_ok "$plat" "$real" || { log "bin/deus for $plat has the wrong executable format"; return 1; }
  install -m 0755 "$real" "$dest"
}

publish() {
  local dir="$1" ssh_cmd dest
  ssh_cmd="ssh -i $DCR_SSH_KEY -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"
  dest="$DCR_PUBLISH_USER@$DCR_PUBLISH_HOST:./"
  stage="publish-binaries"
  # rrsync on the other side pins the destination directory. Sources are
  # regular files with the exact modes (install -m); -p keeps them.
  rsync -t -p -e "$ssh_cmd" "$dir"/deus-linux-amd64 "$dir"/deus-linux-arm64 \
    "$dir"/deus-darwin-arm64 "$dir"/deus-darwin-amd64 "$dest" || fail "rsync of the binaries failed"
  log "published binaries"
  stage="publish-sig"
  rsync -t -p -e "$ssh_cmd" "$dir/manifest.json.sig" "$dest" || fail "rsync of manifest.json.sig failed"
  log "published manifest.json.sig"
  stage="publish-manifest"
  rsync -t -p -e "$ssh_cmd" "$dir/manifest.json" "$dest" || fail "rsync of manifest.json failed"
  log "published manifest.json"
}

main() {
  local arg
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --dry-run) dry=1 ;;
      --skip-apple) skip_apple=1 ;;
      --tag) [ $# -ge 2 ] || { echo "--tag needs a value" >&2; exit 2; }; only_tag="$2"; shift ;;
      -h | --help) sed -n '/^# Pinned deus CLI/,/^# Config comes/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
    shift
  done
  if [ "$skip_apple" = 1 ] && [ "$dry" = 0 ]; then echo "--skip-apple is only allowed with --dry-run" >&2; exit 2; fi
  if [ -n "$only_tag" ] && ! [[ "$only_tag" =~ $tag_re ]]; then echo "bad --tag: $only_tag" >&2; exit 2; fi

  umask 077
  mkdir -p "$DCR_STATE_DIR/work" "$DCR_STATE_DIR/releases"

  # Lock: mkdir is atomic. A leftover lock whose pid is gone is stale.
  lockdir="$DCR_STATE_DIR/lock"
  if ! mkdir "$lockdir" 2>/dev/null; then
    oldpid="$(cat "$lockdir/pid" 2>/dev/null || true)"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      lockdir=""
      exit 0
    fi
    log "removing stale lock (pid ${oldpid:-unknown})"
    rm -rf "$lockdir"
    mkdir "$lockdir" || { lockdir=""; exit 0; }
  fi
  echo $$ >"$lockdir/pid"
  trap cleanup EXIT

  last=""
  [ ! -f "$DCR_STATE_DIR/published-version" ] || last="$(tr -d '[:space:]' <"$DCR_STATE_DIR/published-version")"

  stage="ls-remote"
  if ! remote="$(git ls-remote --tags "$DCR_REPO_URL" 'refs/tags/cli-v*' 2>/dev/null)"; then
    # GitHub or network down: quiet, the next run tries again.
    exit 0
  fi
  if [ -n "$only_tag" ]; then
    sha="$(printf '%s\n' "$remote" | awk -v t="refs/tags/$only_tag^{}" '$2==t{print $1}')"
    [ -n "$sha" ] || sha="$(printf '%s\n' "$remote" | awk -v t="refs/tags/$only_tag" '$2==t{print $1}')"
    [ -n "$sha" ] || { cur_tag="$only_tag"; fail "tag not found on $DCR_REPO_URL"; }
    pick="$only_tag $sha"
  else
    pick="$(printf '%s\n' "$remote" | pick_tag "$last" "$DCR_STATE_DIR/failed")"
    [ -n "$pick" ] || exit 0
  fi
  cur_tag="${pick% *}"
  cur_sha="${pick#* }"
  version="${cur_tag#cli-v}"
  log "start $([ "$dry" = 1 ] && echo "(dry run) ")$cur_tag at $cur_sha (last published: ${last:-none})"

  # --- gates -----------------------------------------------------------------
  stage="gate-version-order"
  if [ -n "$last" ] && ! version_gt "$version" "$last"; then
    fail "version $version is not greater than the last published $last"
  fi

  stage="clone"
  repo="$DCR_STATE_DIR/work/repo"
  if [ -d "$repo/.git" ]; then
    git -C "$repo" fetch -q --force --tags origin '+refs/heads/main:refs/remotes/origin/main' || fail "git fetch failed"
  else
    rm -rf "$repo"
    git clone -q "$DCR_REPO_URL" "$repo" || fail "git clone failed"
    git -C "$repo" fetch -q --force --tags origin || fail "git fetch failed"
  fi
  git -C "$repo" cat-file -e "$cur_sha^{commit}" 2>/dev/null || fail "commit $cur_sha is not in the clone"

  stage="gate-ancestor"
  git -C "$repo" merge-base --is-ancestor "$cur_sha" origin/main || fail "tag commit is not an ancestor of origin/main"

  stage="gate-version-file"
  file_version="$(git -C "$repo" show "$cur_sha:VERSION" | grep -v '^#' | grep -v '^$' | head -n1 | tr -d '[:space:]')"
  [[ "$version" =~ $ver_re ]] || fail "bad version $version"
  [ "$file_version" = "$version" ] || fail "VERSION at the tag is '$file_version', tag says '$version'"

  tmp="$(mktemp -d)"
  chmod 700 "$tmp"
  keyfile="$tmp/release.key"

  stage="keychain"
  if ! security find-generic-password -s "$DCR_KEYCHAIN_SERVICE" -a "$DCR_KEYCHAIN_ACCOUNT" -w >"$keyfile" 2>/dev/null || [ ! -s "$keyfile" ]; then
    fail "release key not readable from the login Keychain ($DCR_KEYCHAIN_SERVICE/$DCR_KEYCHAIN_ACCOUNT; locked or missing)"
  fi
  chmod 600 "$keyfile"

  stage="gate-pubkey"
  derived="$("$DCR_RELEASE_BIN" pubkey "$keyfile" 2>/dev/null)" || fail "Keychain item is not a valid release key"
  embedded="$(git -C "$repo" show "$cur_sha:internal/cli/release/pubkey.txt" | tr -d '[:space:]')"
  [ "$derived" = "$embedded" ] || fail "tag's pubkey.txt does not match the Keychain key (key gives $derived)"
  log "gates passed"

  # --- build (tag code runs only here, under nixbld) ------------------------
  stage="checkout"
  src="$DCR_STATE_DIR/work/$version"
  [ "$dry" = 0 ] || src="$DCR_STATE_DIR/work/dry-$version"
  rm -rf "$src"
  git clone -q --no-hardlinks "$repo" "$src" || fail "local clone failed"
  git -C "$src" checkout -q --detach "$cur_sha" || fail "checkout failed"
  [ -z "$(git -C "$src" status --porcelain)" ] || fail "checkout is not clean"

  out="$src/out"
  mkdir -p "$out"
  stage="build"
  for p in $platforms; do
    path="$(cd "$src" && nix build --no-link --print-out-paths --no-write-lock-file \
      --option allow-import-from-derivation false ".#deus-cli-$p")" || fail "nix build deus-cli-$p failed"
    install_built "$path" "$out/deus-$p" "$p" || fail "build output of deus-cli-$p refused (see log)"
    log "built $p"
  done

  stage="apple-sign"
  if [ "$skip_apple" = 1 ]; then
    log "dry run: Apple signing skipped (--skip-apple)"
  else
    "$DCR_SIGN_BIN" "$out/deus-darwin-arm64" "$out/deus-darwin-amd64" >>"$DCR_LOG" 2>&1 || fail "sign/notarize failed (see log)"
    chmod 0755 "$out/deus-darwin-arm64" "$out/deus-darwin-amd64"
    log "darwin binaries signed and notarized"
  fi

  stage="manifest"
  make_manifest "$out" "$version" "$keyfile" || fail "manifest generation or self-check failed"
  chmod 0755 "$out"/deus-*
  chmod 0644 "$out/manifest.json" "$out/manifest.json.sig"
  log "manifest signed (version $version)"

  if [ "$dry" = 1 ]; then
    log "dry run complete: nothing published, state unchanged; output in $out"
    exit 0
  fi

  rel="$DCR_STATE_DIR/releases/$version"
  rm -rf "$rel"
  cp -R "$out" "$rel"
  publish "$rel"

  stage="state"
  printf '%s\n' "$version" >"$DCR_STATE_DIR/published-version.new"
  mv "$DCR_STATE_DIR/published-version.new" "$DCR_STATE_DIR/published-version"
  rm -rf "$src"
  log "DONE published $version ($cur_tag)"
  notify "Published $version"
}

if [ "${DCR_SOURCE_ONLY:-0}" != 1 ]; then main "$@"; fi
