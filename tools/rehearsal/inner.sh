# malli-rehearsal-inner: every check, run inside the sandbox rehearse.sh
# builds. It sees /nix/store read-only, /work (the private tmpfs),
# /in/backup.age and /in/baseline.tsv read-only, and nothing else of the
# host: no /run, /var, /etc or /home, so no host Unix socket either. It runs
# as uid 0 with every capability dropped, in a network namespace whose only
# interface is loopback. The age identity arrives as the first line of
# stdin and never touches a file, argv or the environment.
#
# Output rule: counts, sizes, durations, exit codes, version strings,
# relative paths of the backup's components, and PASS/FAIL. Never a file's
# contents, an enrollment ID, a database row, or a tool's error text unless
# --show-errors asks for it: the last lines of that tool's own error log,
# which can name a file, a table or a constraint.
#
# (writeShellApplication supplies the shebang and errexit/nounset/pipefail;
# the prelude supplies the binary paths.)
umask 077
export LC_ALL=C

expected_count=""
recipient=""
nanomdm_rel=""
deus_rel=""
show_errors=0
while [ $# -gt 0 ]; do
  case $1 in
    --expected-count) expected_count=$2; shift 2 ;;
    --recipient) recipient=$2; shift 2 ;;
    --nanomdm-path) nanomdm_rel=$2; shift 2 ;;
    --deus-db-path) deus_rel=$2; shift 2 ;;
    --show-errors) show_errors=1; shift ;;
    *) echo "inner: unknown argument" >&2; exit 2 ;;
  esac
done

readonly W=/work
readonly R=$W/restore
readonly LOG=$W/logs
mkdir -p "$R" "$LOG" "$W/tmp" "$W/home" "$W/lists"

CHECKS=(isolation decrypt layout enrollments bootstraptokens
  v09.start v09.version v09.read v09.unchanged
  v06.start v06.version v06.read v06.unchanged
  deus.migrate deus.integrity deus.rollback)
declare -A RESULT NOTE
for c in "${CHECKS[@]}"; do RESULT[$c]=SKIP; NOTE[$c]="not reached"; done

record() {
  RESULT[$1]=$2
  NOTE[$1]=$3
  printf '  %-4s %-16s %s\n' "$2" "$1" "$3"
}
say() { printf '       %s\n' "$*"; }
phase() { printf '\n== %s\n' "$*"; }
now_ms() { date +%s%3N; }
secs() { awk -v ms="$1" 'BEGIN { printf "%.1fs", ms / 1000 }'; }
# The last few lines of a tool's own log, only when asked for.
show_log() {
  if [ "$show_errors" = 1 ] && [ -s "$1" ]; then
    say "--- last lines of $(basename "$1") (--show-errors) ---"
    tail -n 5 "$1" | cut -c1-200 | sed 's/^/       | /'
  fi
}

summary() {
  local failed=0 c
  printf '\n==== REHEARSAL SUMMARY ====\n'
  printf '%s\n' "$BUILD_INFO" | sed 's/^/  /'
  printf '\n'
  for c in "${CHECKS[@]}"; do
    printf '  %-4s %-16s %s\n' "${RESULT[$c]}" "$c" "${NOTE[$c]}"
    [ "${RESULT[$c]}" = PASS ] || failed=$((failed + 1))
  done
  if [ "$failed" = 0 ]; then
    printf '\nRESULT: PASS (%d of %d checks)\n' "${#CHECKS[@]}" "${#CHECKS[@]}"
    exit 0
  fi
  printf '\nRESULT: FAIL (%d of %d checks not PASS)\n' "$failed" "${#CHECKS[@]}"
  exit 1
}

# ── 1. isolation ──────────────────────────────────────────────────────────
phase "isolation"
# Interfaces in this network namespace other than loopback.
ifaces=$(awk -F: 'NR > 2 { gsub(/ /, "", $1); if ($1 != "lo") n++ } END { print n + 0 }' /proc/net/dev)
# Outbound connects that must fail: vista's NanoMDM and the Deus webhook
# over WireGuard, an Apple address (APNs/Apple anycast) and the internet.
targets="10.100.0.4/9990 10.100.0.1/8086 17.253.144.10/443 1.1.1.1/443"
attempted=0
refused=0
for t in $targets; do
  attempted=$((attempted + 1))
  if timeout 3 bash -c "exec 3<>/dev/tcp/$t" 2>/dev/null; then
    say "connect to ${t/\//:} SUCCEEDED"
  else
    refused=$((refused + 1))
  fi
done
host_paths=0
for p in /run /var /etc /home /root /mnt /srv; do
  if [ -e "$p" ]; then host_paths=$((host_paths + 1)); fi
done
capeff=$(awk '/^CapEff:/ { print $2 }' /proc/self/status)
work_fs=$(awk '{ for (i = 7; i <= NF; i++) if ($i == "-") break; if ($5 == "/work") print $(i + 1) }' /proc/self/mountinfo | tail -n 1)
say "non-loopback interfaces: $ifaces; outbound connects refused: $refused/$attempted ($targets)"
say "host paths visible (/run /var /etc /home /root /mnt /srv): $host_paths; effective capabilities: $capeff; /work is $work_fs; uid $EUID"
if [ "$ifaces" = 0 ] && [ "$refused" = "$attempted" ] && [ "$host_paths" = 0 ] \
  && [ "$capeff" = 0000000000000000 ] && [ "$work_fs" = tmpfs ]; then
  record isolation PASS "loopback only; $refused/$attempted outbound connects refused; no host paths or sockets; no capabilities"
else
  record isolation FAIL "sandbox is not isolated as required; nothing was decrypted"
  exec 0</dev/null
  summary
fi

# ── 2. decrypt and extract ────────────────────────────────────────────────
phase "decrypt"
key=""
IFS= read -r key || true
exec 0</dev/null
if ! [[ $key =~ ^AGE-SECRET-KEY-1[0-9A-Z]{58}$ ]]; then
  key=""
  record decrypt FAIL "no age X25519 identity arrived on stdin"
  summary
fi
derived=$(printf '%s\n' "$key" | age-keygen -y 2>/dev/null || true)
say "identity's public recipient: ${derived:-unreadable}"
if [ -n "$recipient" ] && [ "$derived" != "$recipient" ]; then
  key=""
  record decrypt FAIL "identity does not match --recipient $recipient"
  summary
fi
t0=$(now_ms)
set +e
printf '%s\n' "$key" \
  | age --decrypt --identity - /in/backup.age 2>"$LOG/age.err" \
  | bsdtar -x -f - -C "$R" --no-same-owner --no-same-permissions \
      --no-xattrs --no-acls --no-fflags 2>"$LOG/bsdtar.err"
st=("${PIPESTATUS[@]}")
set -e
key=""
unset key
dt=$(( $(now_ms) - t0 ))
files=$(find "$R" -type f | wc -l)
bytes=$(du -sb "$R" | cut -f1)
say "age exit ${st[1]}, bsdtar exit ${st[2]}; $files files, $((bytes / 1048576)) MiB, $(secs "$dt")"
if [ "${st[1]}" != 0 ]; then
  say "age: $(head -n 1 "$LOG/age.err" | cut -c1-160)"
  record decrypt FAIL "age could not decrypt the backup (exit ${st[1]})"
  summary
fi
if [ "${st[2]}" != 0 ] || [ "$files" = 0 ]; then
  say "bsdtar reported $(grep -c . "$LOG/bsdtar.err" || true) error lines"
  show_log "$LOG/bsdtar.err"
  record decrypt FAIL "decrypted, but the archive did not extract cleanly (bsdtar exit ${st[2]})"
  summary
fi
record decrypt PASS "age decrypted; $files files, $((bytes / 1048576)) MiB extracted in $(secs "$dt")"

# ── 3. layout ─────────────────────────────────────────────────────────────
phase "layout"
# Names only when they look like directory names (var, mdm, deus...): never
# anything shaped like an enrollment ID, and never more than eight.
safe_name() { [[ $1 =~ ^[A-Za-z._-][A-Za-z0-9._-]{0,31}$ ]] && ! [[ $1 =~ ^[0-9A-Fa-f]{8}- ]]; }
top=()
others=0
while IFS= read -r n; do
  if safe_name "$n" && [ "${#top[@]}" -lt 8 ]; then top+=("$n"); else others=$((others + 1)); fi
done < <(find "$R" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)
if [ "$others" -gt 0 ]; then
  say "top-level entries: ${top[*]:-none} (and $others more, not named here)"
else
  say "top-level entries: ${top[*]:-none}"
fi
# Exactly one of each, or the path given on the command line.
find_one() { # type name -> relative path, or empty unless exactly one
  local found
  found=$(find "$R" -maxdepth 6 -type "$1" -name "$2" -printf '%P\n')
  [ "$(printf '%s' "$found" | grep -c .)" = 1 ] && printf '%s\n' "$found"
  return 0
}
[ -n "$nanomdm_rel" ] || nanomdm_rel=$(find_one d nanomdm)
[ -n "$deus_rel" ] || deus_rel=$(find_one f deus.db)
scep_rel=$(find_one d scep)
nanodep_rel=$(find_one d nanodep)
S=""
DB=""
if [ -n "$nanomdm_rel" ] && [ -d "$R/$nanomdm_rel" ]; then S=$R/$nanomdm_rel; fi
if [ -n "$deus_rel" ] && [ -f "$R/$deus_rel" ]; then DB=$R/$deus_rel; fi
yn() { if [ -e "$1" ]; then echo yes; else echo no; fi; }
if [ -n "$S" ]; then say "nanomdm store: $nanomdm_rel"; else say "nanomdm store: MISSING"; fi
if [ -n "$DB" ]; then
  say "deus.db:       $deus_rel (wal: $(yn "$DB-wal"), shm: $(yn "$DB-shm"))"
else
  say "deus.db:       MISSING"
fi
if [ -n "$scep_rel" ]; then
  say "scep:          $scep_rel (ca.pem: $(yn "$R/$scep_rel/ca.pem"))"
else
  say "scep:          absent"
fi
say "nanodep:       ${nanodep_rel:-absent}"
if [ -n "$S" ] && [ -n "$DB" ]; then
  record layout PASS "nanomdm store and deus.db found; scep: ${scep_rel:-absent}; nanodep: ${nanodep_rel:-absent}"
else
  missing_parts=""
  [ -n "$S" ] || missing_parts="the nanomdm store"
  [ -n "$DB" ] || missing_parts="${missing_parts:+$missing_parts and }deus.db"
  record layout FAIL "no single $missing_parts in the archive (name it with --nanomdm-path / --deus-db-path)"
  summary
fi

# ── 4. counts, by stat only ───────────────────────────────────────────────
phase "counts (stat only)"
L=$W/lists
find "$S" -mindepth 2 -maxdepth 2 -type f -name Authenticate.plist -printf '%h\n' | sed 's|.*/||' | sort > "$L/device"
find "$S" -mindepth 2 -maxdepth 2 -type f -name TokenUpdate.plist -printf '%h\n' | sed 's|.*/||' | sort > "$L/token"
find "$S" -mindepth 2 -maxdepth 2 -type f -name BootstrapToken.dat -printf '%h\t%s\n' \
  | sed 's|^.*/||' | sort > "$L/bst"
devices=$(grep -c . "$L/device" || true)
bstokens=$(grep -c . "$L/bst" || true)
user_channels=$(comm -13 "$L/device" "$L/token" | grep -c . || true)
disabled=$(find "$S" -mindepth 2 -maxdepth 2 -type f -name Disabled | wc -l)
# A push certificate is a <topic>.pem beside its <topic>.key, as the storage
# reads it.
pushcerts=0
while IFS= read -r pem; do
  if [ -f "${pem%.pem}.key" ]; then pushcerts=$((pushcerts + 1)); fi
done < <(find "$S" -mindepth 1 -maxdepth 1 -type f -name '*.pem')
say "device enrollments (Authenticate.plist): $devices; user channels: $user_channels; disabled: $disabled; push certs: $pushcerts"
say "BootstrapToken.dat files: $bstokens"
baseline_note=""
if [ -f /in/baseline.tsv ]; then
  awk -F'\t' 'NF >= 2 { print $1 "\t" $2 }' /in/baseline.tsv | sort > "$L/baseline"
  base_n=$(grep -c . "$L/baseline" || true)
  [ -n "$expected_count" ] || expected_count=$base_n
  missing=$(comm -23 <(cut -f1 "$L/baseline") <(cut -f1 "$L/bst") | grep -c . || true)
  extra=$(comm -13 <(cut -f1 "$L/baseline") <(cut -f1 "$L/bst") | grep -c . || true)
  resized=$(join -t "$(printf '\t')" "$L/baseline" "$L/bst" | awk -F'\t' '$2 != $3' | grep -c . || true)
  baseline_note="; vs baseline ($base_n rows): $missing missing, $extra new, $resized resized"
  say "baseline: $base_n rows; token IDs missing from backup: $missing; new since baseline: $extra; size differs: $resized"
fi
if [ -z "$expected_count" ]; then
  record enrollments FAIL "no expected count: pass --baseline or --expected-count"
  record bootstraptokens FAIL "no expected count"
else
  if [ "$devices" = "$expected_count" ]; then
    record enrollments PASS "$devices device enrollments = $expected_count expected"
  else
    record enrollments FAIL "$devices device enrollments, expected $expected_count"
  fi
  if [ "$bstokens" = "$expected_count" ]; then
    record bootstraptokens PASS "$bstokens BootstrapToken.dat = $expected_count expected$baseline_note"
  else
    record bootstraptokens FAIL "$bstokens BootstrapToken.dat, expected $expected_count$baseline_note"
  fi
fi

# ── 5 and 6. NanoMDM v0.9, then v0.6, on the same copy ────────────────────
# A stat-only manifest: path, type, mode, size, mtime. Never contents.
manifest() { (cd "$S" && find . -printf '%p\t%y\t%m\t%s\t%T@\n' | sort) > "$1"; }
manifest "$L/manifest.before"
say "store manifest: $(grep -c . "$L/manifest.before") entries"

# -ca only verifies device identity certificates on check-in, which cannot
# happen here. Use the backup's public SCEP CA certificate; ca.key is never
# read. Without one, a throwaway self-signed certificate.
if [ -n "$scep_rel" ] && [ -f "$R/$scep_rel/ca.pem" ]; then
  CA=$R/$scep_rel/ca.pem
  ca_note="the backup's SCEP ca.pem"
else
  CA=$W/throwaway-ca.pem
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 1 \
    -subj /CN=rehearsal-throwaway-ca -keyout "$W/throwaway-ca.key" -out "$CA" 2>/dev/null
  ca_note="a throwaway CA (the backup has no scep/ca.pem)"
fi

SERVER_PID=""
stop_server() {
  if [ -n "$SERVER_PID" ]; then
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    SERVER_PID=""
  fi
}
trap stop_server EXIT
# start_server label binary port args... ; sets SERVER_PID and VERSION_SEEN.
# No -api and no -api-key-file: the server registers no API routes, so
# nothing can push, enqueue or upload. No -webhook-url and no -dm.
start_server() {
  local label=$1 bin=$2 port=$3 body
  shift 3
  VERSION_SEEN=""
  "$bin" -listen "127.0.0.1:$port" "$@" >"$LOG/$label.log" 2>&1 &
  SERVER_PID=$!
  for _ in $(seq 1 100); do
    if body=$(curl -fsS --max-time 1 "http://127.0.0.1:$port/version" 2>/dev/null); then
      VERSION_SEEN=$(printf '%s' "$body" | jq -r '.version // empty' 2>/dev/null || true)
      return 0
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      wait "$SERVER_PID" 2>/dev/null || true
      SERVER_PID=""
      return 1
    fi
    sleep 0.2
  done
  return 1
}
probe_value() { awk -F= -v k="$2" '$1 == k { print $2 }' "$1"; }
# Keys that must agree between the stat counts and each version's reads.
check_probe() { # label probe-output probe-exit
  local label=$1 out=$2 rc=$3 dev auth pushok bstp errs
  dev=$(probe_value "$out" enrollments.device)
  auth=$(probe_value "$out" enumerate.authenticate)
  pushok=$(probe_value "$out" pushinfo.ok)
  bstp=$(probe_value "$out" bootstraptoken.present)
  errs=$(awk -F= '$1 ~ /errors$/ { s += $2 } END { print s + 0 }' "$out")
  say "$label probe: device enrollments ${dev:-?}, Authenticate decoded ${auth:-?}, push info ${pushok:-?}, bootstrap tokens ${bstp:-?}, queued commands $(probe_value "$out" queue.pending), push certs $(probe_value "$out" pushcert.ok)/$(probe_value "$out" pushcert.found) (expires $(probe_value "$out" pushcert.notafter)), read errors $errs"
  if [ "$rc" = 0 ] && [ "$errs" = 0 ] && [ "$dev" = "$devices" ] && [ "$auth" = "$devices" ] \
    && [ "$bstp" = "$bstokens" ] && [ "$(probe_value "$out" pushcert.ok)" = "$pushcerts" ]; then
    record "$label.read" PASS "storage reads every enrollment: $auth Authenticate, $pushok push info, $bstp bootstrap tokens, 0 read errors"
    return 0
  fi
  record "$label.read" FAIL "storage read: exit $rc, $errs read errors, ${auth:-?}/$devices Authenticate, ${bstp:-?}/$bstokens bootstrap tokens"
  return 1
}
compare_manifest() { # label
  local label=$1 changed
  manifest "$L/manifest.after-$label"
  if cmp -s "$L/manifest.before" "$L/manifest.after-$label"; then
    record "$label.unchanged" PASS "store manifest identical ($(grep -c . "$L/manifest.before") entries: paths, types, modes, sizes, mtimes)"
  else
    changed=$(diff "$L/manifest.before" "$L/manifest.after-$label" | grep -c '^[<>]' || true)
    record "$label.unchanged" FAIL "store manifest differs: $changed manifest lines changed"
  fi
}

phase "nanomdm v0.9 (patched, as step 3 would run it)"
say "binary: $NANOMDM_V09 ($("$NANOMDM_V09" -version 2>/dev/null || echo '?'))"
say "flags: -storage file -storage-options enable_deprecated=1 -storage-dsn <copy> -ca <$ca_note>; no -api, -webhook-url or -dm"
if start_server v09 "$NANOMDM_V09" 19000 -storage file -storage-options enable_deprecated=1 \
  -storage-dsn "$S" -ca "$CA"; then
  record v09.start PASS "listening on 127.0.0.1:19000 inside the sandbox"
  if [[ $VERSION_SEEN == "$V09_EXPECTED_PREFIX"* ]]; then
    record v09.version PASS "/version: $VERSION_SEEN"
  else
    record v09.version FAIL "/version: ${VERSION_SEEN:-none}, expected $V09_EXPECTED_PREFIX..."
  fi
  set +e
  "$PROBE_V09" -storage-dsn "$S" >"$L/probe-v09" 2>"$LOG/probe-v09.err"
  rc=$?
  set -e
  check_probe v09 "$L/probe-v09" "$rc" || true
  stop_server
else
  show_log "$LOG/v09.log"
  record v09.start FAIL "did not serve /version within 20s on the store copy"
fi
compare_manifest v09

phase "nanomdm v0.6.0 (rollback, as vista runs it today)"
say "binary: $NANOMDM_V06 ($("$NANOMDM_V06" -version 2>/dev/null || echo '?'))"
say "flags: -storage file -storage-dsn <same copy> -ca <$ca_note>; no -storage-options, -api, -webhook-url or -dm"
if start_server v06 "$NANOMDM_V06" 19001 -storage file -storage-dsn "$S" -ca "$CA"; then
  record v06.start PASS "listening on 127.0.0.1:19001 on the copy v0.9 opened"
  if [ "$VERSION_SEEN" = "$V06_EXPECTED" ]; then
    record v06.version PASS "/version: $VERSION_SEEN"
  else
    record v06.version FAIL "/version: ${VERSION_SEEN:-none}, expected $V06_EXPECTED"
  fi
  set +e
  "$PROBE_V06" -storage-dsn "$S" >"$L/probe-v06" 2>"$LOG/probe-v06.err"
  rc=$?
  set -e
  check_probe v06 "$L/probe-v06" "$rc" || true
  stop_server
else
  show_log "$LOG/v06.log"
  record v06.start FAIL "did not serve /version within 20s on the copy v0.9 opened"
fi
compare_manifest v06

# ── 7. Deus migrations on a copy of deus.db ───────────────────────────────
phase "deus migrations"
# Schema-level questions only: counts from sqlite_master and two PRAGMAs.
# No SELECT ever reads a row.
sql() { sqlite3 -batch -bail "$1" "$2"; }
copy_db() { # dest-dir source-db
  mkdir -p "$1"
  cp -- "$2" "$1/deus.db"
  for s in -wal -shm; do
    if [ -e "$2$s" ]; then cp -- "$2$s" "$1/deus.db$s"; fi
  done
}
# Sets INTEGRITY ("ok", "N problems" or "unreadable") and FK_ROWS (a count,
# or "unreadable"). A sqlite3 that fails is never read as a clean result.
integrity() { # db
  local out
  if out=$(sql "$1" 'PRAGMA integrity_check;' 2>/dev/null); then
    if [ "$out" = ok ]; then INTEGRITY=ok; else INTEGRITY="$(printf '%s\n' "$out" | grep -c .) problems"; fi
  else
    INTEGRITY=unreadable
  fi
  if out=$(sql "$1" 'PRAGMA foreign_key_check;' 2>/dev/null); then
    FK_ROWS=$(printf '%s' "$out" | grep -c . || true)
  else
    FK_ROWS=unreadable
  fi
}
tables() { sql "$1" "SELECT count(*) FROM sqlite_master WHERE type = 'table';" 2>/dev/null || echo "?"; }

# The new Deus upgrades the copy with `deus-server -migrate-only` (Deus
# c26640d). Right after flag parsing, before its logger, any token or
# secret, and any listener or socket, it opens <state-dir>/deus.db with the
# store.Open the service uses (the rounds rebuild, schema.sql and the ALTER
# list, in one transaction). It prints on stdout the table, index and
# trigger counts and SQLite's integrity_check and foreign_key_check, and
# exits 0 healthy, 1 when the open or the upgrade failed, 2 when it upgraded
# but a check found a problem. Its report can name tables and row ids, so it
# goes to the wiped log and only counts are printed here.
#
# A deus-server without the flag stops at flag parsing with exit 2, the same
# code as "unhealthy", and one given a state dir without deus.db creates a
# fresh database. So the flag is looked for in its -help before it runs, and
# a run counts only when its report names this copy, says it migrated it,
# and does not say it created it.
DEUS_NEW_DB=$W/deus-new/deus.db
# The values of one key of the report ("migrated", "integrity_check",
# "foreign_key_check"), one line per row.
report_lines() { sed -n "s/^$1: //p" "$LOG/deus-new.out"; }
count_not_ok() { grep -vc '^ok$' || true; }

# Two databases at most on the tmpfs: the extracted one and the migrated
# copy. The extracted one serves as the old Deus's control afterwards.
copy_db "$W/deus-new" "$DB"
pre_tables=$(tables "$DEUS_NEW_DB")
integrity "$DEUS_NEW_DB"
pre_integrity=$INTEGRITY
pre_fk=$FK_ROWS
say "before: $pre_tables tables; integrity_check $pre_integrity; foreign_key_check $pre_fk rows"
hrc=0
"$DEUS_NEW" -help >"$LOG/deus-new-help.out" 2>&1 || hrc=$?
if [ "$hrc" = 0 ] && grep -Eq '^ +-migrate-only( |$)' "$LOG/deus-new-help.out"; then
  has_flag=yes
else
  has_flag=no
fi
say "new deus $DEUS_NEW_VERSION: $DEUS_NEW (-help exit $hrc; -migrate-only flag: $has_flag)"
mrc=""
migrated=no
if [ "$has_flag" = no ]; then
  show_log "$LOG/deus-new-help.out"
  record deus.migrate FAIL "new Deus $DEUS_NEW_VERSION: deus-server is missing or has no -migrate-only flag (-help exit $hrc); it needs Deus c26640d or later. Nothing ran on the copy"
else
  t0=$(now_ms)
  mrc=0
  "$DEUS_NEW" -migrate-only -state-dir "$W/deus-new" >"$LOG/deus-new.out" 2>"$LOG/deus-new.err" || mrc=$?
  dt=$(( $(now_ms) - t0 ))
  post_tables=$(tables "$DEUS_NEW_DB")
  header=$(head -n 1 "$LOG/deus-new.out")
  shape=$(report_lines migrated | tail -n 1)
  rep_integrity=$(report_lines integrity_check | count_not_ok)
  rep_integrity_ok=$(report_lines integrity_check | grep -c '^ok$' || true)
  rep_fk=$(report_lines foreign_key_check | count_not_ok)
  rep_fk_ok=$(report_lines foreign_key_check | grep -c '^ok$' || true)
  created=$(grep -c '^database: did not exist' "$LOG/deus-new.out" || true)
  say "deus-server -migrate-only: exit $mrc in $(secs "$dt"); report: ${shape:-no migrated line}; integrity_check lines not ok: $rep_integrity; foreign_key_check rows: $rep_fk"
  if [ "$header" != "deus-server $DEUS_NEW_VERSION -migrate-only $DEUS_NEW_DB" ] || [ "$created" != 0 ]; then
    show_log "$LOG/deus-new.out"
    show_log "$LOG/deus-new.err"
    if [ -n "$header" ]; then header_note=mismatched; else header_note=missing; fi
    record deus.migrate FAIL "deus-server -migrate-only (exit $mrc) did not report upgrading this copy of deus.db (first line $header_note; created a new database: $created)"
  elif [ -n "$shape" ] && { [ "$mrc" = 0 ] || [ "$mrc" = 2 ]; }; then
    migrated=yes
    record deus.migrate PASS "new Deus $DEUS_NEW_VERSION upgraded the copy in $(secs "$dt") (deus-server -migrate-only exit $mrc); tables $pre_tables -> $post_tables"
  else
    show_log "$LOG/deus-new.out"
    show_log "$LOG/deus-new.err"
    record deus.migrate FAIL "deus-server -migrate-only exited $mrc after $(secs "$dt"): the open or the upgrade failed; tables $pre_tables -> $post_tables"
  fi
fi
integrity "$DEUS_NEW_DB"
say "after:  $(tables "$DEUS_NEW_DB") tables; integrity_check $INTEGRITY; foreign_key_check $FK_ROWS rows"
if [ "$migrated" = no ]; then
  record deus.integrity FAIL "not judged: the migration did not run or failed (copy now: integrity $INTEGRITY, $FK_ROWS foreign-key rows)"
elif [ "$mrc" = 0 ] && [ "$rep_integrity" = 0 ] && [ "$rep_integrity_ok" = 1 ] && [ "$rep_fk" = 0 ] && [ "$rep_fk_ok" = 1 ] \
  && [ "$INTEGRITY" = ok ] && [ "$FK_ROWS" = 0 ]; then
  record deus.integrity PASS "deus-server reports healthy (exit 0); integrity_check ok; foreign_key_check 0 rows (before: $pre_integrity, $pre_fk rows)"
else
  record deus.integrity FAIL "deus-server -migrate-only exit $mrc; its report: $rep_integrity integrity_check problems, $rep_fk foreign_key_check rows; sqlite3 here: integrity_check $INTEGRITY, foreign_key_check $FK_ROWS rows (before: $pre_integrity, $pre_fk rows)"
fi

# The old Deus is the one vista runs, and it has no -migrate-only. Its
# smallest entry point that opens the database is `deus-rack-import
# -dry-run`: it calls the same store.Open its deus-server calls and then only
# plans an import. With an empty workbook and an empty -hosts-file it reads
# nothing else from the database and writes nothing else; its report
# (0 hosts, 0 cabinets) goes to the wiped log.
mkdir -p "$W/xlsx/xl/_rels"
printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets/></workbook>' > "$W/xlsx/xl/workbook.xml"
printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>' > "$W/xlsx/xl/_rels/workbook.xml.rels"
(cd "$W/xlsx" && bsdtar --format zip -cf "$W/empty.xlsx" xl)
: > "$W/no-hosts"
open_store() { # label binary db -> exit code
  local rc=0
  "$2" -db "$3" -xlsx "$W/empty.xlsx" -hosts-file "$W/no-hosts" -dry-run >"$LOG/$1.out" 2>"$LOG/$1.err" || rc=$?
  return "$rc"
}

say "old deus $DEUS_OLD_VERSION: $DEUS_OLD"
crc=0
open_store deus-old-control "$DEUS_OLD" "$DB" || crc=$?
if [ "$migrated" = no ]; then
  record deus.rollback FAIL "not judged: the migration did not run or failed (old Deus on the untouched copy: exit $crc)"
else
  orc=0
  open_store deus-old-rollback "$DEUS_OLD" "$DEUS_NEW_DB" || orc=$?
  integrity "$DEUS_NEW_DB"
  say "old deus on the untouched copy: exit $crc; on the migrated copy: exit $orc; then integrity_check $INTEGRITY, foreign_key_check $FK_ROWS rows"
  if [ "$crc" = 0 ] && [ "$orc" = 0 ] && [ "$INTEGRITY" = ok ]; then
    record deus.rollback PASS "old Deus $DEUS_OLD_VERSION opens the migrated copy (and the untouched one)"
  elif [ "$crc" != 0 ]; then
    show_log "$LOG/deus-old-control.err"
    record deus.rollback FAIL "old Deus $DEUS_OLD_VERSION cannot open even the untouched copy (exit $crc)"
  else
    show_log "$LOG/deus-old-rollback.err"
    record deus.rollback FAIL "old Deus $DEUS_OLD_VERSION cannot open the migrated copy (exit $orc): step 2 has no code-only rollback"
  fi
fi

summary
