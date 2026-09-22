#!/usr/bin/env bash
# Build the rehearsal harness and every binary it runs, as your normal user.
# Touches no data, key or service, and needs no sudo. Everything is built
# from committed git trees (fetchGit by revision), never from a worktree:
#
#   harness   this repository's HEAD, tools/rehearsal as committed
#   v0.6      the nanomdm binary vista's configuration at that HEAD runs
#   v0.9      the same configuration with the step-3 NanoMDM pin, fed from
#             the new Deus's vendored third_party/nanomdm
#   new Deus  --new-deus-rev (default: the committed head of
#             feature/macos-updates in --new-deus-repo)
#   old Deus  --old-deus-rev, a full or short revision (default: the deus
#             input locked in /home/daniel/nix/flake.lock; name it, since
#             that lock moves to the new Deus). It must not be the new Deus.
#
# Prints the harness store path and the command the owner runs.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(git -C "$here" rev-parse --show-toplevel)
new_deus_repo=/home/daniel/Projects/malli-deus-macos-updates
new_deus_ref=feature/macos-updates
new_deus_rev=""
old_deus_repo=/home/daniel/Projects/malli-deus
old_deus_rev=""
live_lock=/home/daniel/nix/flake.lock
pin_deus_rev=""
out=${XDG_CACHE_HOME:-$HOME/.cache}/malli-rehearsal
selftest=0

while [ $# -gt 0 ]; do
  case $1 in
    --new-deus-repo) new_deus_repo=$2; shift 2 ;;
    --new-deus-ref) new_deus_ref=$2; shift 2 ;;
    --new-deus-rev) new_deus_rev=$2; shift 2 ;;
    --old-deus-repo) old_deus_repo=$2; shift 2 ;;
    --old-deus-rev) old_deus_rev=$2; shift 2 ;;
    --live-lock) live_lock=$2; shift 2 ;;
    --pin-deus-rev) pin_deus_rev=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --selftest) selftest=1; shift ;;
    -h | --help) sed -n '2,16p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "build.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

vista_rev=$(git -C "$repo" rev-parse HEAD)
if [ -n "$(git -C "$repo" status --porcelain -- tools/rehearsal)" ]; then
  echo "build.sh: tools/rehearsal has uncommitted changes; the build uses HEAD ($vista_rev), not them" >&2
fi
[ -n "$new_deus_rev" ] || new_deus_rev=$(git -C "$new_deus_repo" rev-parse "refs/heads/$new_deus_ref")
if [ -z "$old_deus_rev" ]; then
  old_deus_rev=$(jq -r '.nodes.deus.locked.rev' "$live_lock")
  echo "build.sh: old Deus from $live_lock: $old_deus_rev; pass --old-deus-rev if vista runs another" >&2
fi
# A short revision (--old-deus-rev 410a695) names the commit in its repository.
full_rev() { git -C "$1" rev-parse --verify --quiet "$2^{commit}" || { echo "build.sh: $2 is not a commit in $1" >&2; exit 2; }; }
new_deus_rev=$(full_rev "$new_deus_repo" "$new_deus_rev")
old_deus_rev=$(full_rev "$old_deus_repo" "$old_deus_rev")
for r in "$vista_rev" "$new_deus_rev" "$old_deus_rev"; do
  [[ $r =~ ^[0-9a-f]{40}$ ]] || { echo "build.sh: not a full revision: $r" >&2; exit 2; }
done
# deus.rollback would test the new Deus against itself. (default.nix also
# refuses two Deus of the same version, and inner.sh checks both again.)
if [ "$new_deus_rev" = "$old_deus_rev" ]; then
  echo "build.sh: the old and the new Deus are the same revision, $new_deus_rev; pass --old-deus-rev with the Deus vista runs today" >&2
  exit 2
fi

# A Nix string literal: escape backslash, double quote and dollar.
nixstr() { printf '"%s"' "$(printf '%s' "$1" | sed 's/[\\"$]/\\&/g')"; }
params="vistaRepo = $(nixstr "$repo"); vistaRev = $(nixstr "$vista_rev");"
params+=" newDeusRepo = $(nixstr "$new_deus_repo"); newDeusRev = $(nixstr "$new_deus_rev"); newDeusRef = $(nixstr "$new_deus_ref");"
params+=" oldDeusRepo = $(nixstr "$old_deus_repo"); oldDeusRev = $(nixstr "$old_deus_rev");"
[ -z "$pin_deus_rev" ] || params+=" pinDeusRev = $(nixstr "$pin_deus_rev");"
# tools/rehearsal itself comes from the committed tree too.
expr="import ((builtins.fetchGit { url = $(nixstr "file://$repo"); rev = $(nixstr "$vista_rev"); }) + \"/tools/rehearsal\") { $params }"
mkdir -p "$out"
attrs=(harness)
[ "$selftest" = 0 ] || attrs+=(selftest)
for a in "${attrs[@]}"; do
  nix build --impure --out-link "$out/$a" --expr "($expr).$a"
done
harness=$(readlink -f "$out/harness")

cat <<EOF
built from:
  vista config  $repo @ $vista_rev
  new deus      $new_deus_repo @ $new_deus_rev
  old deus      $old_deus_repo @ $old_deus_rev
harness: $harness
GC roots: $out

The owner runs (as root, on the machine that holds the backup):
  sudo $harness/bin/malli-rehearse \\
    --backup /path/to/backup.tar.zst.age \\
    --baseline /home/daniel/m1-5fro/bstoken-baseline-20260920.tsv
EOF
if [ "$selftest" = 1 ]; then
  echo "self-test (synthetic data, no sudo): $(readlink -f "$out/selftest")/bin/malli-rehearsal-selftest DIR"
fi
