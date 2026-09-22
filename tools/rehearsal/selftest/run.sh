# malli-rehearsal-selftest SCRATCH_DIR
#
# Runs the harness against SYNTHETIC fixtures only (make-fixture.sh), as the
# root of an unprivileged user namespace and pid 1 of a pid namespace of its
# own, so it needs no sudo and touches nothing real. Every case must end
# with the expected checks, an intact wipe, and none of the planted secret
# markers in the output.
#
#   good            every check PASS (identity on stdin)
#   tty             every check PASS, identity typed at the hidden prompt
#   wrong-count     --expected-count one too high: the two count checks FAIL
#   corrupt         one byte of the encrypted archive flipped: decrypt FAIL
#   v06-unreadable  a v0.9 that leaves the store in a form v0.6 cannot
#                   read: v09.unchanged and v06.read FAIL
#   bad-migration   deus.db with a table the new schema cannot build on:
#                   deus-server -migrate-only exits 1, deus.migrate FAIL
#   unhealthy       deus.db with a dangling foreign key: the upgrade applies,
#                   deus-server -migrate-only exits 2, deus.integrity FAIL
#   swap-token, swap-token-expected-count
#                   one Mac lost since the baseline and one new, so the
#                   counts agree (also with --expected-count): bootstraptokens
#                   FAIL and prints the lost Mac's ID, and no other ID
#   omit-scep, omit-scep-key, omit-nanodep, omit-pushcert
#                   the backup lacks the scep directory, scep/ca.key, every
#                   NanoDEP file, or the push certificate: layout FAIL
#   empty-deus      deus.db is the empty database a mistyped .backup source
#                   makes: deus.migrate, deus.integrity and deus.rollback FAIL
#   no-heartbeats   deus.db has the old schema but no heartbeats rows: the
#                   same three FAIL
#   drifted-v09     step 3's entrypoint no longer passes -storage-options
#                   enable_deprecated=1, but the harness still would:
#                   v09.start FAIL, and v0.9 is never started
#   old-is-new      a harness whose old Deus is the new one, as build.sh's
#                   default would give once the live lock is bumped:
#                   deus.rollback FAIL, and neither Deus is run as the old one
#   no-migrate-only a new Deus whose deus-server has no -migrate-only (the
#                   old Deus's stands in): deus.migrate FAIL, and it is never
#                   run on the copy
#   stage-ns-direct, stage-ns-shared-net
#                   --stage ns given by hand in pid 1's mount namespace, or
#                   in a private one that shares pid 1's network: exit 2
#                   before anything is mounted
#   interrupted     SIGINT (Ctrl-C) mid-run, as the v0.9 phase begins:
#                   exit 130, and still wiped
#   reader-gone     the reader of the output dies (a dead `| tee`), then
#                   Ctrl-C at the prompt: exit 130, mountpoint removed
#   second-interrupt
#                   a second Ctrl-C to the process group while the cleanup
#                   waits for the sandbox: exit 130, and still wiped
#   killed          kill -9 mid-run: no trap runs, and the tmpfs is still gone
export LC_ALL=C

# The harness refuses to mount anything unless its mount and network
# namespaces differ from pid 1's, as they must on vista. So the self-test
# re-runs itself as pid 1 of a pid namespace with its own /proc, as root of
# an unprivileged user namespace: pid 1 is then this script, and its
# namespaces are the ones the harness must leave.
if [ "$$" != 1 ]; then
  exec unshare --user --map-root-user --pid --fork --mount-proc --kill-child -- "$(readlink -f "$0")" "$@"
fi
# As pid 1 no signal ends it by default; these do.
trap 'exit 130' INT
trap 'exit 143' TERM

scratch=${1:?usage: malli-rehearsal-selftest SCRATCH_DIR}
case $scratch in /nix/store/*) echo "not in the store" >&2; exit 2 ;; esac
mkdir -p "$scratch"
scratch=$(realpath -e "$scratch")
run=$scratch/run
out=$scratch/out
rm -rf "$run" "$out"
mkdir -p "$run" "$out"

"$FIXTURE" "$scratch/good" --count 12
"$FIXTURE" "$scratch/broken-deus" --count 12 --broken-deus
"$FIXTURE" "$scratch/dangling-fk" --count 12 --dangling-fk
"$FIXTURE" "$scratch/empty-deus" --count 12 --empty-deus
"$FIXTURE" "$scratch/no-heartbeats" --count 12 --no-heartbeats
"$FIXTURE" "$scratch/swap-token" --count 12 --swap-token
omitted_pieces="scep scep-key nanodep pushcert"
for piece in $omitted_pieces; do
  "$FIXTURE" "$scratch/omit-$piece" --count 12 --omit "$piece"
done
cp "$scratch/good/backup.tar.zst.age" "$scratch/corrupt.age"
size=$(stat -c %s "$scratch/corrupt.age")
printf '\x5a' | dd of="$scratch/corrupt.age" bs=1 seek=$((size / 2)) conv=notrunc status=none

failures=0
results=()

# harness fixture-dir output-file extra-args... -> exit code of the harness
rehearse() {
  local harness=$1 fx=$2 log=$3 rc=0
  shift 3
  grep AGE-SECRET-KEY "$fx/identity" \
    | env --default-signal=INT "$harness" \
        --work-parent "$run" --tmpfs-size 1g --backup "$fx/backup.tar.zst.age" \
        --baseline "$fx/baseline.tsv" "$@" \
    > "$log" 2>&1 || rc=$?
  return "$rc"
}

status_of() { awk -v c="$2" '/^==== REHEARSAL SUMMARY/ { s = 1 } s && $2 == c { print $1 }' "$1"; }

# case-name log expected-exit actual-exit fixture-dir "check=STATUS ..."
#   [an extended regex some line of the log must match]
judge() {
  local name=$1 log=$2 want_rc=$3 got_rc=$4 fx=$5 expect=$6 must=${7:-} problems="" pair c want got mp
  [ "$got_rc" = "$want_rc" ] || problems+=" exit=$got_rc(want $want_rc)"
  if [ -n "$must" ] && ! grep -Eq -- "$must" "$log"; then problems+=" no-line-matching[$must]"; fi
  for pair in $expect; do
    c=${pair%%=*}
    want=${pair#*=}
    got=$(status_of "$log" "$c")
    [ "$got" = "$want" ] || problems+=" $c=${got:-none}(want $want)"
  done
  # The wipe: reported complete, mountpoint gone, nothing left behind.
  grep -Eq '^WIPE: [0-9]+ files zeroed and unlinked, 0 entries left before unmount; tmpfs unmounted: yes; mountpoint .* removed: yes$' "$log" \
    || problems+=" wipe-line"
  mp=$(sed -n 's/^WIPE: .*; mountpoint \(.*\) removed: .*$/\1/p' "$log")
  if [ -z "$mp" ] || [ -e "$mp" ]; then problems+=" mountpoint-still-exists"; fi
  if [ -n "$(find "$run" -mindepth 1 -print -quit)" ]; then problems+=" leftovers-in-work-parent"; fi
  if grep -sq 'malli-rehearsal-[0-9a-f]\{16\}' /proc/[0-9]*/mountinfo; then problems+=" tmpfs-still-mounted-somewhere"; fi
  # No planted secret, identity, enrollment ID or row value in the output.
  if grep -F -q -f "$fx/markers" "$log"; then problems+=" LEAK"; fi
  if [ -z "$problems" ]; then
    results+=("PASS  $name")
  else
    results+=("FAIL  $name:$problems")
    failures=$((failures + 1))
  fi
}

all_pass="isolation=PASS decrypt=PASS layout=PASS enrollments=PASS bootstraptokens=PASS
  v09.start=PASS v09.version=PASS v09.read=PASS v09.unchanged=PASS
  v06.start=PASS v06.version=PASS v06.read=PASS v06.unchanged=PASS
  deus.migrate=PASS deus.integrity=PASS deus.rollback=PASS"

rc=0; rehearse "$HARNESS" "$scratch/good" "$out/good.log" || rc=$?
judge good "$out/good.log" 0 "$rc" "$scratch/good" "$all_pass" \
  '^ +deus-server -migrate-only: exit 0 in '

rc=0; rehearse "$HARNESS" "$scratch/good" "$out/wrong-count.log" --expected-count 13 || rc=$?
judge wrong-count "$out/wrong-count.log" 1 "$rc" "$scratch/good" \
  "isolation=PASS decrypt=PASS enrollments=FAIL bootstraptokens=FAIL v09.read=PASS v06.read=PASS deus.migrate=PASS"

mkdir -p "$scratch/corrupt"
cp "$scratch/good/identity" "$scratch/good/baseline.tsv" "$scratch/good/markers" "$scratch/corrupt/"
mv "$scratch/corrupt.age" "$scratch/corrupt/backup.tar.zst.age"
rc=0; rehearse "$HARNESS" "$scratch/corrupt" "$out/corrupt.log" || rc=$?
judge corrupt "$out/corrupt.log" 1 "$rc" "$scratch/corrupt" \
  "isolation=PASS decrypt=FAIL layout=SKIP v09.start=SKIP deus.migrate=SKIP"

rc=0; rehearse "$HARNESS_FAULTY_V09" "$scratch/good" "$out/v06-unreadable.log" || rc=$?
judge v06-unreadable "$out/v06-unreadable.log" 1 "$rc" "$scratch/good" \
  "decrypt=PASS v09.start=PASS v09.version=PASS v09.read=PASS v09.unchanged=FAIL v06.start=PASS v06.read=FAIL v06.unchanged=FAIL deus.migrate=PASS"

rc=0; rehearse "$HARNESS" "$scratch/broken-deus" "$out/bad-migration.log" || rc=$?
judge bad-migration "$out/bad-migration.log" 1 "$rc" "$scratch/broken-deus" \
  "decrypt=PASS enrollments=PASS v09.read=PASS v06.read=PASS deus.migrate=FAIL deus.integrity=FAIL deus.rollback=FAIL" \
  '^ +FAIL +deus\.migrate +deus-server -migrate-only exited 1 after '

rc=0; rehearse "$HARNESS" "$scratch/dangling-fk" "$out/unhealthy.log" || rc=$?
judge unhealthy "$out/unhealthy.log" 1 "$rc" "$scratch/dangling-fk" \
  "decrypt=PASS enrollments=PASS v09.read=PASS v06.read=PASS deus.migrate=PASS deus.integrity=FAIL" \
  '^ +FAIL +deus\.integrity +deus-server -migrate-only exit 2; its report: 0 integrity_check problems, 1 foreign_key_check rows;'

# One Mac lost since the baseline and one new: the counts agree, the IDs do
# not. Only the lost Mac's ID may appear (the markers hold every other ID).
lost_id=5E1F7E57-0001-4000-8000-000000000001
for name in swap-token swap-token-expected-count; do
  extra=()
  [ "$name" = swap-token ] || extra=(--expected-count 12)
  rc=0; rehearse "$HARNESS" "$scratch/swap-token" "$out/$name.log" "${extra[@]}" || rc=$?
  judge "$name" "$out/$name.log" 1 "$rc" "$scratch/swap-token" \
    "decrypt=PASS layout=PASS enrollments=PASS bootstraptokens=FAIL v09.read=PASS v06.read=PASS deus.migrate=PASS deus.rollback=PASS" \
    "^ +FAIL +bootstraptokens +1 bootstrap tokens in the baseline are not in the backup \(IDs above\); 12 BootstrapToken\.dat, expected 12; vs baseline \(12 rows\): 1 missing, 1 new, 0 resized$"
  if [ "$(grep -c "^ \+missing: $lost_id$" "$out/$name.log")" != 1 ]; then
    if [[ ${results[-1]} == PASS* ]]; then failures=$((failures + 1)); fi
    results[-1]="FAIL  $name: lost-id-not-printed-once (${results[-1]})"
  fi
done

for piece in $omitted_pieces; do
  case $piece in
    scep) gap='no single scep directory' ;;
    scep-key) gap='scep/ca\.key is missing' ;;
    nanodep) gap='nanodep holds no non-empty file' ;;
    pushcert) gap='no push certificate in the store' ;;
  esac
  rc=0; rehearse "$HARNESS" "$scratch/omit-$piece" "$out/omit-$piece.log" || rc=$?
  judge "omit-$piece" "$out/omit-$piece.log" 1 "$rc" "$scratch/omit-$piece" \
    "decrypt=PASS layout=FAIL enrollments=PASS bootstraptokens=PASS v09.start=PASS v09.read=PASS v06.start=PASS v06.read=PASS deus.migrate=PASS deus.rollback=PASS" \
    "^ +FAIL +layout +$gap\$"
done

rc=0; rehearse "$HARNESS" "$scratch/empty-deus" "$out/empty-deus.log" || rc=$?
judge empty-deus "$out/empty-deus.log" 1 "$rc" "$scratch/empty-deus" \
  "decrypt=PASS enrollments=PASS v09.read=PASS v06.read=PASS deus.migrate=FAIL deus.integrity=FAIL deus.rollback=FAIL" \
  "^ +FAIL +deus\.migrate +the copy of deus\.db is not one vista's Deus wrote: it has 0 of the old Deus [^ ]+'s [1-9][0-9]* tables, and heartbeats rows: unreadable "

rc=0; rehearse "$HARNESS" "$scratch/no-heartbeats" "$out/no-heartbeats.log" || rc=$?
judge no-heartbeats "$out/no-heartbeats.log" 1 "$rc" "$scratch/no-heartbeats" \
  "decrypt=PASS enrollments=PASS v09.read=PASS v06.read=PASS deus.migrate=FAIL deus.integrity=FAIL deus.rollback=FAIL" \
  "^ +FAIL +deus\.migrate +the copy of deus\.db is not one vista's Deus wrote: it has ([1-9][0-9]*) of the old Deus [^ ]+'s \1 tables, and heartbeats rows: 0 "

rc=0; rehearse "$HARNESS_DRIFTED_V09" "$scratch/good" "$out/drifted-v09.log" || rc=$?
judge drifted-v09 "$out/drifted-v09.log" 1 "$rc" "$scratch/good" \
  "decrypt=PASS layout=PASS v09.start=FAIL v09.version=SKIP v09.read=SKIP v09.unchanged=PASS v06.start=PASS v06.read=PASS deus.migrate=PASS deus.rollback=PASS" \
  '^ +FAIL +v09\.start +v09 runs with "-storage file -storage-options enable_deprecated=1", but its entrypoint passes "-storage file"; not started$'

rc=0; rehearse "$HARNESS_OLD_IS_NEW" "$scratch/good" "$out/old-is-new.log" || rc=$?
judge old-is-new "$out/old-is-new.log" 1 "$rc" "$scratch/good" \
  "decrypt=PASS enrollments=PASS v09.read=PASS v06.read=PASS deus.migrate=PASS deus.integrity=PASS deus.rollback=FAIL" \
  '^ +FAIL +deus\.rollback +the old Deus is not another Deus: old ([^ ]+) \(rev ([0-9a-f]{40})\), new \1 \(rev \2\);'

rc=0; rehearse "$HARNESS_NO_MIGRATE_ONLY" "$scratch/good" "$out/no-migrate-only.log" || rc=$?
judge no-migrate-only "$out/no-migrate-only.log" 1 "$rc" "$scratch/good" \
  "decrypt=PASS enrollments=PASS v09.read=PASS v06.read=PASS deus.migrate=FAIL deus.integrity=FAIL deus.rollback=FAIL" \
  '^ +FAIL +deus\.migrate +new Deus .*: deus-server is missing or has no -migrate-only flag \(-help exit 0\)'

# --stage ns given by hand: from pid 1's own namespaces (stage-ns-direct),
# and from a private mount namespace that still shares pid 1's network
# (stage-ns-shared-net). Both must refuse before mounting anything.
for name in stage-ns-direct stage-ns-shared-net; do
  prefix=()
  shared=mnt
  if [ "$name" = stage-ns-shared-net ]; then
    prefix=(unshare --mount --propagation private --)
    shared=net
  fi
  log=$out/$name.log
  rc=0
  grep AGE-SECRET-KEY "$scratch/good/identity" \
    | "${prefix[@]}" "$HARNESS" --stage ns --work-parent "$run" --tmpfs-size 1g \
        --backup "$scratch/good/backup.tar.zst.age" --baseline "$scratch/good/baseline.tsv" \
    > "$log" 2>&1 || rc=$?
  problems=""
  [ "$rc" = 2 ] || problems+=" exit=$rc(want 2)"
  want="malli-rehearse: this is pid 1's $shared namespace, not a private one"
  if ! grep -qF "$want" "$log"; then problems+=" no-line[$want]"; fi
  if grep -q '^tmpfs: \|^== isolation' "$log"; then problems+=" went-on"; fi
  if [ -n "$(find "$run" -mindepth 1 -print -quit)" ]; then problems+=" leftovers-in-work-parent"; fi
  if grep -sq 'malli-rehearsal-[0-9a-f]\{16\}' /proc/[0-9]*/mountinfo; then problems+=" tmpfs-still-mounted-somewhere"; fi
  if grep -F -q -f "$scratch/good/markers" "$log"; then problems+=" LEAK"; fi
  if [ -z "$problems" ]; then
    results+=("PASS  $name")
  else
    results+=("FAIL  $name:$problems")
    failures=$((failures + 1))
  fi
done

# The owner's path: the identity typed at the prompt on a terminal (a
# pseudo-terminal here), sent only once the prompt is up, as a person would.
log=$out/tty.log
rm -f "$scratch/tty-in"
mkfifo "$scratch/tty-in"
script -qec "$HARNESS --work-parent $run --tmpfs-size 1g --backup $scratch/good/backup.tar.zst.age --baseline $scratch/good/baseline.tsv" \
  /dev/null < "$scratch/tty-in" > "$log" 2>&1 &
pid=$!
exec 7> "$scratch/tty-in"
for _ in $(seq 1 200); do
  grep -q 'Paste the age identity' "$log" && break
  sleep 0.05
done
sleep 0.3
grep AGE-SECRET-KEY "$scratch/good/identity" >&7
rc=0; wait "$pid" || rc=$?
exec 7>&-
rm -f "$scratch/tty-in"
# A terminal ends lines with CR LF.
tr -d '\r' < "$log" > "$log.lf" && mv "$log.lf" "$log"
judge tty "$log" 0 "$rc" "$scratch/good" "$all_pass"

# Ctrl-C mid-run, with the decrypted store on the tmpfs.
log=$out/interrupted.log
grep AGE-SECRET-KEY "$scratch/good/identity" \
  | env --default-signal=INT "$HARNESS" \
      --work-parent "$run" --tmpfs-size 1g --baseline "$scratch/good/baseline.tsv" \
      --backup "$scratch/good/backup.tar.zst.age" > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 600); do
  grep -q '^== nanomdm v0.9' "$log" && break
  sleep 0.05
done
kill -INT "$pid" 2>/dev/null || true
rc=0; wait "$pid" || rc=$?
if grep -q '^==== REHEARSAL SUMMARY' "$log"; then
  results+=("FAIL  interrupted: the run finished before the signal landed")
  failures=$((failures + 1))
else
  judge interrupted "$log" 130 "$rc" "$scratch/good" ""
  zeroed=$(sed -n 's/^WIPE: \([0-9]*\) files zeroed.*/\1/p' "$log")
  results[-1]="${results[-1]} (interrupted with ${zeroed:-?} decrypted files on the tmpfs)"
fi

# The reader of the harness's output dies (as `| tee` would), then Ctrl-C.
# The harness waits at the identity prompt, the tmpfs mounted, and has
# nowhere left to write: a message printed before the wipe would raise
# SIGPIPE and kill it before the wipe. The reader's death means no WIPE line
# can be seen, so the proof is the exit code and the mountpoint: a harness
# killed mid-cleanup leaves its mountpoint behind and exits 141.
log=$out/reader-gone.log
rm -f "$scratch/key-in" "$scratch/out-pipe"
mkfifo "$scratch/key-in" "$scratch/out-pipe"
cat "$scratch/out-pipe" > "$log" &
reader=$!
env --default-signal=INT "$HARNESS" --work-parent "$run" --tmpfs-size 1g \
  --baseline "$scratch/good/baseline.tsv" --backup "$scratch/good/backup.tar.zst.age" \
  < "$scratch/key-in" > "$scratch/out-pipe" 2>&1 &
pid=$!
exec 8> "$scratch/key-in"
for _ in $(seq 1 200); do
  grep -q '^tmpfs: ' "$log" && break
  sleep 0.05
done
kill -KILL "$reader" 2>/dev/null || true
{ wait "$reader"; } 2>/dev/null || true
kill -INT "$pid" 2>/dev/null || true
rc=0; { wait "$pid"; } 2>/dev/null || rc=$?
exec 8>&-
rm -f "$scratch/key-in" "$scratch/out-pipe"
problems=""
[ "$rc" = 130 ] || problems+=" exit=$rc(want 130)"
grep -q '^tmpfs: ' "$log" || problems+=" never-reached-the-prompt"
if [ -n "$(find "$run" -mindepth 1 -print -quit)" ]; then problems+=" mountpoint-left-in-work-parent"; fi
if grep -sq 'malli-rehearsal-[0-9a-f]\{16\}' /proc/[0-9]*/mountinfo; then problems+=" tmpfs-still-mounted-somewhere"; fi
if [ -z "$problems" ]; then
  results+=("PASS  reader-gone (output reader killed, then Ctrl-C: wiped, mountpoint removed, exit 130)")
else
  results+=("FAIL  reader-gone:$problems")
  failures=$((failures + 1))
fi
find "$run" -mindepth 1 -maxdepth 1 -type d -empty -delete

# A second Ctrl-C while the harness waits for the sandbox to die. Ctrl-C on
# a terminal signals the whole foreground process group, so the harness gets
# a group of its own (setsid) and the signals go to the group. The sandbox
# (bwrap, in a session of its own) and everything in it are stopped first,
# so the harness's wait for it lasts the full 5 s before its kill -9, and
# the second Ctrl-C lands inside the cleanup.
stop_tree() { # pid: SIGSTOP it, then its descendants, top down
  local k kids=()
  kill -STOP "$1" 2>/dev/null || return 0
  read -ra kids < "/proc/$1/task/$1/children" || true
  for k in "${kids[@]}"; do stop_tree "$k"; done
}
log=$out/second-interrupt.log
grep AGE-SECRET-KEY "$scratch/good/identity" \
  | setsid env --default-signal=INT "$HARNESS" \
      --work-parent "$run" --tmpfs-size 1g --baseline "$scratch/good/baseline.tsv" \
      --backup "$scratch/good/backup.tar.zst.age" > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 600); do
  grep -q '^== nanomdm v0.9' "$log" && break
  sleep 0.05
done
sandbox=""
kids=()
read -ra kids < "/proc/$pid/task/$pid/children" || true
for c in "${kids[@]}"; do
  if [ "$(cat "/proc/$c/comm" 2>/dev/null)" = bwrap ]; then sandbox=$c; fi
done
if [ -n "$sandbox" ]; then stop_tree "$sandbox"; fi
kill -INT -- "-$pid" 2>/dev/null || true
sleep 1
kill -INT -- "-$pid" 2>/dev/null || true
rc=0; { wait "$pid"; } 2>/dev/null || rc=$?
if [ -z "$sandbox" ]; then
  results+=("FAIL  second-interrupt: no running sandbox to stop")
  failures=$((failures + 1))
elif grep -q '^==== REHEARSAL SUMMARY' "$log"; then
  results+=("FAIL  second-interrupt: the run finished before the signal landed")
  failures=$((failures + 1))
else
  judge second-interrupt "$log" 130 "$rc" "$scratch/good" ""
fi

# kill -9 mid-run: no trap can run, so the kernel must do the wipe. The
# sandbox dies with its parent, the private mount namespace with its last
# process, and the tmpfs with it. Only the empty mountpoint may remain.
log=$out/killed.log
grep AGE-SECRET-KEY "$scratch/good/identity" \
  | "$HARNESS" \
      --work-parent "$run" --tmpfs-size 1g --baseline "$scratch/good/baseline.tsv" \
      --backup "$scratch/good/backup.tar.zst.age" > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 600); do
  grep -q '^== nanomdm v0.9' "$log" && break
  sleep 0.05
done
kill -KILL "$pid" 2>/dev/null || true
# (Silences bash's own "Killed" job notice.)
rc=0; { wait "$pid"; } 2>/dev/null || rc=$?
problems=""
[ "$rc" = 137 ] || problems+=" exit=$rc(want 137)"
grep -q '^==== REHEARSAL SUMMARY' "$log" && problems+=" finished-before-the-kill"
for _ in $(seq 1 100); do
  grep -sq 'malli-rehearsal-[0-9a-f]\{16\}' /proc/[0-9]*/mountinfo || break
  sleep 0.05
done
if grep -sq 'malli-rehearsal-[0-9a-f]\{16\}' /proc/[0-9]*/mountinfo; then problems+=" tmpfs-still-mounted-somewhere"; fi
left=$(find "$run" -mindepth 1 | wc -l)
dirs=$(find "$run" -mindepth 1 -maxdepth 1 -type d -empty | wc -l)
[ "$left" = "$dirs" ] || problems+=" files-left-in-work-parent"
if grep -F -q -f "$scratch/good/markers" "$log"; then problems+=" LEAK"; fi
if [ -z "$problems" ]; then
  results+=("PASS  killed (kill -9 mid-run: tmpfs gone with the namespace; $dirs empty mountpoint left, removed now)")
else
  results+=("FAIL  killed:$problems")
  failures=$((failures + 1))
fi
find "$run" -mindepth 1 -maxdepth 1 -type d -empty -delete

printf '\n==== SELF-TEST (synthetic data only) ====\n'
printf '%s\n' "${results[@]}"
printf 'logs: %s\n' "$out"
[ "$failures" = 0 ]
