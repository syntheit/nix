# malli-rehearse: the isolated rehearsal of the NanoMDM v0.9 upgrade, its
# rollback and the new Deus's migrations, on a decrypted copy of the
# pre-upgrade backup. Run as root. See tools/rehearsal/README.md.
#
# What this outer script does, and nothing more:
#   1. refuses unless it is root;
#   2. re-runs itself in a private mount namespace, so the tmpfs it mounts
#      is invisible to every other process and disappears with it;
#   3. mounts a fresh 0700 tmpfs (noswap) with a random source tag, and
#      refuses to go on unless /proc/self/mountinfo shows exactly that;
#   4. reads the age identity from the terminal with echo off (or one line
#      of stdin when stdin is not a terminal) into a shell variable;
#   5. starts the sandbox (bubblewrap: no network but loopback, no host
#      paths but /nix/store read-only, the tmpfs and the backup, no
#      capabilities) and hands it the identity on its stdin;
#   6. on any exit, error or signal: kills the sandbox, zeroes and removes
#      every file on the tmpfs, unmounts it and removes the mountpoint.
#
# (writeShellApplication supplies the shebang and errexit/nounset/pipefail;
# the prelude supplies the binary paths and INNER.)
umask 077
ulimit -c 0
export LC_ALL=C

usage() {
  cat <<'EOF'
usage: malli-rehearse --backup FILE.age [options]

  --backup FILE          the age-encrypted backup archive (tar, optionally
                         gzip/zstd/xz compressed) - required
  --baseline FILE        stat-only baseline TSV (enrollment-id, size, date);
                         its row count is the expected enrollment count
  --expected-count N     expected device enrollments and bootstrap tokens
                         (overrides the baseline's row count)
  --recipient age1...    refuse unless the identity typed is this recipient's
  --nanomdm-path REL     the NanoMDM store inside the archive, if not found
  --deus-db-path REL     deus.db inside the archive, if not found
  --tmpfs-size SIZE      cap of the private tmpfs (default 12g); it holds the
                         extracted backup plus one copy of deus.db
  --memory-max SIZE      memory cap of the whole run, as a transient systemd
                         scope, when run as real root (default 14G)
  --work-parent DIR      where the mountpoint is created (default /run)
  --show-errors          print the last lines of a failing tool's own error
                         log; they can name a file, a table or a constraint
EOF
}

self=$(readlink -f -- "$0")
stage=host
backup=""
baseline=""
expected=""
recipient=""
nanomdm_path=""
deus_db_path=""
tmpfs_size=12g
memory_max=14G
work_parent=/run
show_errors=0
args=("$@")
while [ $# -gt 0 ]; do
  case $1 in
    --stage) stage=$2; shift 2 ;;
    --backup) backup=$2; shift 2 ;;
    --baseline) baseline=$2; shift 2 ;;
    --expected-count) expected=$2; shift 2 ;;
    --recipient) recipient=$2; shift 2 ;;
    --nanomdm-path) nanomdm_path=$2; shift 2 ;;
    --deus-db-path) deus_db_path=$2; shift 2 ;;
    --tmpfs-size) tmpfs_size=$2; shift 2 ;;
    --work-parent) work_parent=$2; shift 2 ;;
    --memory-max) memory_max=$2; shift 2 ;;
    --show-errors) show_errors=1; shift ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

die() { printf 'malli-rehearse: %s\n' "$*" >&2; exit 2; }

if [ "$stage" = host ]; then
  [ "$EUID" = 0 ] || die "run as root: it mounts a private tmpfs and builds namespaces"
  [ -n "$backup" ] || { usage >&2; exit 2; }
  [ -f "$backup" ] && [ -r "$backup" ] || die "--backup is not a readable file"
  backup=$(realpath -e -- "$backup")
  case $backup in
    /nix/store/*) die "the backup is in /nix/store, which every user can read; move it out first" ;;
  esac
  if [ -n "$baseline" ]; then
    [ -f "$baseline" ] && [ -r "$baseline" ] || die "--baseline is not a readable file"
  fi
  if [ -n "$expected" ] && ! [[ $expected =~ ^[0-9]+$ ]]; then die "--expected-count must be a number"; fi
  if [ -n "$recipient" ] && ! [[ $recipient =~ ^age1[0-9a-z]{58}$ ]]; then die "--recipient must be an age1... recipient"; fi
  [ -d "$work_parent" ] || die "--work-parent does not exist"
  [[ $memory_max =~ ^[0-9]+[KMGT]?$ ]] || die "--memory-max must look like 14G"
  [[ $tmpfs_size =~ ^[0-9]+[kmgKMG]?$ ]] || die "--tmpfs-size must look like 12g"
  printf 'malli-rehearse\n%s\n' "$BUILD_INFO" | sed '2,$s/^/  /'
  printf "  memory available now: %s MiB\n" "$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo)"
  # Production goes first: under memory pressure the kernel kills this run
  # before any service, and it yields CPU and I/O.
  echo 1000 > /proc/self/oom_score_adj 2>/dev/null || true
  renice -n 10 -p "$$" > /dev/null 2>&1 || true
  ionice -c 2 -n 7 -p "$$" > /dev/null 2>&1 || true
  # Everything from here runs in a mount namespace of its own. As real root
  # (not in a user namespace) it also runs in a transient systemd scope whose
  # memory, tmpfs pages included, is capped and never swapped.
  if [ -d /run/systemd/system ] \
    && [ "$(awk '{ print $1, $2, $3 }' /proc/self/uid_map)" = "0 0 4294967295" ]; then
    exec systemd-run --scope --quiet --collect \
      -p MemoryMax="$memory_max" -p MemorySwapMax=0 \
      -- unshare --mount --propagation private -- "$self" --stage ns "${args[@]}"
  fi
  exec unshare --mount --propagation private -- "$self" --stage ns "${args[@]}"
fi
[ "$stage" = ns ] || die "unknown stage"
[ "$EUID" = 0 ] || die "not root in the private namespace"
backup=$(realpath -e -- "$backup")

mnt=""
tag=""
sandbox_pid=""
key=""

mount_is_ours() {
  awk -v m="$mnt" -v t="$tag" '
    { for (i = 7; i <= NF; i++) if ($i == "-") break
      if ($5 == m && $(i + 1) == "tmpfs" && $(i + 2) == t) n++ }
    END { exit !(n == 1) }' /proc/self/mountinfo
}
# shellcheck disable=SC2329 # called from the EXIT trap, through wipe
mounted_at_all() {
  awk -v m="$mnt" '$5 == m { f = 1 } END { exit !f }' /proc/self/mountinfo
}

# shellcheck disable=SC2329 # called from the EXIT trap
wipe() {
  local files=0 left=0 unmounted=no removed=no
  [ -n "$mnt" ] || return 0
  if [ -d "$mnt" ] && mount_is_ours; then
    files=$(find "$mnt" -xdev -type f | wc -l)
    # Zero every file's bytes in place (tmpfs pages are the file), then
    # unlink; then remove the directories.
    find "$mnt" -xdev -type f -exec shred --force --iterations=0 --zero --remove=unlink -- {} + 2>/dev/null || true
    find "$mnt" -xdev -mindepth 1 -depth -delete 2>/dev/null || true
    left=$(find "$mnt" -xdev -mindepth 1 | wc -l)
    for _ in $(seq 1 40); do
      umount "$mnt" 2>/dev/null && break
      sleep 0.25
    done
    if mounted_at_all; then umount --lazy "$mnt" 2>/dev/null || true; fi
  fi
  if ! mounted_at_all; then unmounted=yes; fi
  if [ -d "$mnt" ] && [ "$unmounted" = yes ]; then rmdir "$mnt" 2>/dev/null || true; fi
  if [ ! -e "$mnt" ]; then removed=yes; fi
  printf '\nWIPE: %s files zeroed and unlinked, %s entries left before unmount; tmpfs unmounted: %s; mountpoint %s removed: %s\n' \
    "$files" "$left" "$unmounted" "$mnt" "$removed"
}

# shellcheck disable=SC2329 # the EXIT trap
cleanup() {
  local rc=$?
  trap - EXIT INT TERM HUP
  set +e
  case $rc in
    129 | 130 | 143) printf '\nmalli-rehearse: interrupted (exit %s); wiping\n' "$rc" >&2 ;;
  esac
  key=""
  unset key
  if [ -n "$sandbox_pid" ] && kill -0 "$sandbox_pid" 2>/dev/null; then
    kill -TERM "$sandbox_pid" 2>/dev/null
    for _ in $(seq 1 50); do
      kill -0 "$sandbox_pid" 2>/dev/null || break
      sleep 0.1
    done
    kill -KILL "$sandbox_pid" 2>/dev/null
    wait "$sandbox_pid" 2>/dev/null
  fi
  wipe
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# Swap that can only land in RAM: every active swap device is zram with no
# writeback backing device. Only consulted when noswap is refused.
swap_is_ram_only() {
  local dev b
  while read -r dev _; do
    [ "$dev" = Filename ] && continue
    case $dev in /dev/zram*) ;; *) return 1 ;; esac
    b=/sys/block/${dev#/dev/}/backing_dev
    if [ -e "$b" ] && [ "$(cat "$b")" != none ]; then return 1; fi
  done < /proc/swaps
  return 0
}

mnt=$(mktemp -d "$work_parent/malli-rehearsal.XXXXXXXX")
tag=malli-rehearsal-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')
opts="size=$tmpfs_size,mode=0700,uid=0,gid=0,nodev,nosuid,noexec"
if mount -t tmpfs -o "$opts,noswap" "$tag" "$mnt" 2>/dev/null; then
  swap_note="noswap: its pages can never be swapped"
elif swap_is_ram_only; then
  mount -t tmpfs -o "$opts" "$tag" "$mnt"
  swap_note="noswap refused here; all active swap is zram without a backing device, so its pages stay in RAM"
else
  die "cannot mount a noswap tmpfs, and swap here can reach a disk; refusing"
fi
mount_is_ours || die "the mount at $mnt is not the tmpfs this run created; refusing"
[ "$(stat -c '%u %a' "$mnt")" = "0 700" ] || die "the tmpfs is not root-only 0700; refusing"
[ -z "$(find "$mnt" -mindepth 1 -print -quit)" ] || die "the fresh tmpfs is not empty; refusing"
printf '\ntmpfs: %s (%s, %s); visible only in this mount namespace\n' "$mnt" "$tmpfs_size" "$swap_note"

if [ -t 0 ]; then
  printf 'Paste the age identity (AGE-SECRET-KEY-1...), then Enter. Nothing is echoed: ' > /dev/tty
  IFS= read -r -s key < /dev/tty || key=""
  printf '\n' > /dev/tty
else
  IFS= read -r key || true
fi
exec 0</dev/null
if ! [[ $key =~ ^AGE-SECRET-KEY-1[0-9A-Z]{58}$ ]]; then
  key=""
  die "that is not an age X25519 identity (AGE-SECRET-KEY-1 and 58 more characters)"
fi

inner_args=()
[ -n "$expected" ] && inner_args+=(--expected-count "$expected")
[ -n "$recipient" ] && inner_args+=(--recipient "$recipient")
[ -n "$nanomdm_path" ] && inner_args+=(--nanomdm-path "$nanomdm_path")
[ -n "$deus_db_path" ] && inner_args+=(--deus-db-path "$deus_db_path")
[ "$show_errors" = 1 ] && inner_args+=(--show-errors)

bwrap_args=(
  --unshare-ipc --unshare-pid --unshare-net --unshare-uts --unshare-cgroup-try
  --die-with-parent --new-session --cap-drop ALL
  --clearenv
  --setenv PATH "$SANDBOX_PATH"
  --setenv HOME /work/home
  --setenv TMPDIR /work/tmp
  --setenv LC_ALL C
  --hostname rehearsal
  --ro-bind /nix/store /nix/store
  --proc /proc
  --dev /dev
  --bind "$mnt" /work
  --ro-bind "$backup" /in/backup.age
  --chdir /work
)
[ -n "$baseline" ] && bwrap_args+=(--ro-bind "$(realpath -e -- "$baseline")" /in/baseline.tsv)

# The identity goes to the sandbox's stdin through a pipe from a builtin
# printf: no file, no argv, no environment.
bwrap "${bwrap_args[@]}" -- "$INNER" "${inner_args[@]}" < <(printf '%s\n' "$key") &
sandbox_pid=$!
key=""
unset key
rc=0
wait "$sandbox_pid" || rc=$?
sandbox_pid=""
exit "$rc"
