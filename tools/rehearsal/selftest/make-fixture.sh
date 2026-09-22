# malli-rehearsal-fixture DIR [--count N] [--broken-deus] [--dangling-fk]
#                             [--empty-deus] [--no-heartbeats]
#                             [--omit scep|scep-key|nanodep|pushcert]
#
# Writes a SYNTHETIC stand-in for the pre-upgrade backup into DIR. Nothing
# in it comes from production: a NanoMDM file store of N made-up
# enrollments (Authenticate, TokenUpdate, BootstrapToken, one queued command
# on every third, one user channel), a made-up push certificate, a dummy
# SCEP CA and NanoDEP directory, and a deus.db created by the OLD Deus's own
# store.Open with a few made-up rows. Then it tars and age-encrypts it to a
# throwaway key, and writes a baseline TSV in the production format.
#
#   DIR/identity            the throwaway age identity (synthetic data only)
#   DIR/backup.tar.zst.age  the encrypted archive
#   DIR/baseline.tsv        enrollment-id, BootstrapToken.dat size, date
#   DIR/markers             strings planted in the data that the harness
#                           must never print
#
# --broken-deus plants a table the new Deus's schema cannot build on (an
# mdm_enrollments without its columns, so schema.sql's index on
# mdm_enrollments(serial_number) fails), so its migration fails.
#
# --dangling-fk plants a rack_slots row whose rack_units parent does not
# exist. The new Deus's migration succeeds, but its foreign_key_check finds
# the row, so deus-server -migrate-only reports unhealthy and exits 2.
#
# --empty-deus replaces deus.db with what a mistyped source in step 0's
# `sqlite3 <source> ".backup deus.db"` makes: a valid database with no table.
#
# --no-heartbeats leaves the heartbeats table empty; every other row goes in.
#
# --omit leaves one piece out of the archive: the scep directory, scep/ca.key,
# every file in nanodep (the directory stays, empty), or the push certificate.
umask 077
export LC_ALL=C

dir=${1:?usage: malli-rehearsal-fixture DIR [--count N] [--broken-deus] [--dangling-fk] [--empty-deus] [--no-heartbeats] [--omit PIECE]}
shift
count=12
broken_deus=0
dangling_fk=0
empty_deus=0
no_heartbeats=0
omit=""
while [ $# -gt 0 ]; do
  case $1 in
    --count) count=$2; shift 2 ;;
    --broken-deus) broken_deus=1; shift ;;
    --dangling-fk) dangling_fk=1; shift ;;
    --empty-deus) empty_deus=1; shift ;;
    --no-heartbeats) no_heartbeats=1; shift ;;
    --omit) omit=$2; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
case $dir in /nix/store/*) echo "not in the store" >&2; exit 2 ;; esac
mkdir -p "$dir"
src=$dir/src
rm -rf "$src"
store=$src/var/lib/mdm/nanomdm
mkdir -p "$store" "$src/var/lib/mdm/scep" "$src/var/lib/mdm/nanodep" "$src/var/lib/deus"

marker_bst=SYNTHETIC-BOOTSTRAP-TOKEN-MARKER-7f3a
marker_pw=SYNTHETIC-ADMIN-PASSWORD-MARKER-91c2
marker_vpn=SYNTHETIC-VPN-TOKEN-MARKER-44d0
marker_host=synthetic-host-marker-a8e1
topic=com.apple.mgmt.External.00000000-0000-4000-8000-5e1f7e570000

plist_head='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>'
plist_tail='</dict>
</plist>'

: > "$dir/baseline.tsv"
ids=()
for i in $(seq 1 "$count"); do
  id=$(printf '5E1F7E57-%04X-4000-8000-%012X' "$i" "$i")
  ids+=("$id")
  e=$store/$id
  mkdir -p "$e"
  serial=$(printf 'SYNTH%07d' "$i")
  printf '%s\n<key>MessageType</key><string>Authenticate</string>\n<key>Topic</key><string>%s</string>\n<key>UDID</key><string>%s</string>\n<key>SerialNumber</key><string>%s</string>\n%s\n' \
    "$plist_head" "$topic" "$id" "$serial" "$plist_tail" > "$e/Authenticate.plist"
  token=$(head -c 32 /dev/urandom | base64 -w0)
  printf '%s\n<key>MessageType</key><string>TokenUpdate</string>\n<key>Topic</key><string>%s</string>\n<key>UDID</key><string>%s</string>\n<key>PushMagic</key><string>%s</string>\n<key>Token</key><data>%s</data>\n<key>AwaitingConfiguration</key><false/>\n%s\n' \
    "$plist_head" "$topic" "$id" "$(printf 'PUSHMAGIC-%04d' "$i")" "$token" "$plist_tail" > "$e/TokenUpdate.plist"
  printf '%s' "$serial" > "$e/SerialNumber.txt"
  printf '1' > "$e/TokenUpdate.tally.txt"
  printf '%s-%04d' "$marker_bst" "$i" > "$e/BootstrapToken.dat"
  if [ $((i % 3)) = 0 ]; then
    mkdir -p "$e/Queue"
    cuuid=$(printf '00000000-0000-4000-8000-%012d' "$i")
    printf '%s\n<key>CommandUUID</key><string>%s</string>\n<key>Command</key><dict><key>RequestType</key><string>DeviceInformation</string><key>Queries</key><array><string>UDID</string></array></dict>\n%s\n' \
      "$plist_head" "$cuuid" "$plist_tail" > "$e/Queue/$cuuid.plist"
  fi
  printf '%s\t%s\t%s\n' "$id" "$(stat -c %s "$e/BootstrapToken.dat")" 2026-09-20 >> "$dir/baseline.tsv"
done
# One user channel: a TokenUpdate and no Authenticate.
u=$store/${ids[0]}:5E1F7E57-0000-4000-8000-00000000USER
mkdir -p "$u"
printf '%s\n<key>MessageType</key><string>TokenUpdate</string>\n<key>Topic</key><string>%s</string>\n<key>UDID</key><string>%s</string>\n<key>UserID</key><string>5E1F7E57-0000-4000-8000-00000000USER</string>\n<key>PushMagic</key><string>PUSHMAGIC-USER</string>\n<key>Token</key><data>%s</data>\n%s\n' \
  "$plist_head" "$topic" "${ids[0]}" "$(head -c 32 /dev/urandom | base64 -w0)" "$plist_tail" > "$u/TokenUpdate.plist"

# A made-up APNs push certificate and key, stored under the topic.
openssl req -x509 -newkey rsa:2048 -nodes -days 400 -subj "/CN=APSP:synthetic/UID=$topic" \
  -keyout "$store/$topic.key" -out "$store/$topic.pem" 2>/dev/null
# A dummy SCEP CA and NanoDEP store. The harness checks that ca.pem, ca.key
# and a NanoDEP file exist and are not empty, and reads only ca.pem.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 400 \
  -subj /CN=synthetic-scep-ca -keyout "$src/var/lib/mdm/scep/ca.key" \
  -out "$src/var/lib/mdm/scep/ca.pem" 2>/dev/null
printf 'synthetic\n' > "$src/var/lib/mdm/nanodep/placeholder"
case $omit in
  "") ;;
  scep) rm -rf "$src/var/lib/mdm/scep" ;;
  scep-key) rm -f "$src/var/lib/mdm/scep/ca.key" ;;
  nanodep) rm -f "$src/var/lib/mdm/nanodep/"* ;;
  pushcert) rm -f "$store/$topic.pem" "$store/$topic.key" ;;
  *) echo "unknown --omit $omit" >&2; exit 2 ;;
esac

# deus.db made by the OLD Deus's own store.Open, then a few made-up rows.
db=$src/var/lib/deus/deus.db
mkdir -p "$dir/xlsx/xl/_rels"
printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets/></workbook>' > "$dir/xlsx/xl/workbook.xml"
printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>' > "$dir/xlsx/xl/_rels/workbook.xml.rels"
(cd "$dir/xlsx" && bsdtar --format zip -cf "$dir/empty.xlsx" xl)
"$DEUS_OLD" -db "$db" -xlsx "$dir/empty.xlsx" -dry-run > /dev/null
now=$(date +%s)
{
  # The sqlite3 shell's default, spelled out: the dangling row below must go in.
  if [ "$dangling_fk" = 1 ]; then echo "PRAGMA foreign_keys = OFF;"; fi
  echo "BEGIN;"
  for i in $(seq 1 "$count"); do
    [ "$no_heartbeats" = 1 ] || printf "INSERT INTO heartbeats (host_name, rev, uptime_s, disk_free_gb, mem_free_gb, containers, tailscale, updated_at) VALUES ('%s-%d', 'rev', 100, 10.5, 2.5, '{}', '{}', %d);\n" "$marker_host" "$i" "$now"
    printf "INSERT INTO ade_devices (enrollment_id, udid, serial_number, state, admin_username, admin_password, created_at, updated_at) VALUES ('%s', '%s', 'SYNTH%07d', 'done', 'admin', '%s-%d', %d, %d);\n" \
      "${ids[$((i - 1))]}" "${ids[$((i - 1))]}" "$i" "$marker_pw" "$i" "$now" "$now"
  done
  printf "INSERT INTO users (name, vm_admin_password, vpn_token, created_at, updated_at) VALUES ('synthetic-user', '%s', '%s', %d, %d);\n" "$marker_pw" "$marker_vpn" "$now" "$now"
  if [ "$broken_deus" = 1 ]; then
    echo "CREATE TABLE mdm_enrollments (legacy_blob TEXT);"
  fi
  if [ "$dangling_fk" = 1 ]; then
    printf "INSERT INTO rack_slots (cabinet, unit, position, host_name) VALUES ('synthetic-cabinet', 99, 1, '%s-slot');\n" "$marker_host"
  fi
  echo "COMMIT;"
} | sqlite3 -batch -bail "$db"
sqlite3 "$db" 'PRAGMA wal_checkpoint(TRUNCATE);' > /dev/null
rm -f "$db-wal" "$db-shm"
if [ "$empty_deus" = 1 ]; then
  rm -f "$db"
  sqlite3 "$src/deus.db.typo" ".backup $db"
  rm -f "$src/deus.db.typo"
fi

# The identity is throwaway and guards synthetic data only.
rm -f "$dir/identity"
age-keygen -o "$dir/identity" 2>/dev/null
recipient=$(age-keygen -y "$dir/identity")
rm -f "$dir/backup.tar.zst.age"
# GNU tar piped through zstd, the way a backup is usually cut. (libarchive
# 3.8.9's own `bsdtar --zstd -cf -` writes a truncated stream; the harness
# reads either, and reports such a stream as an extraction failure.)
tar -cf - -C "$src" var | zstd -q -c | age -r "$recipient" -o "$dir/backup.tar.zst.age"
printf '%s\n' "$recipient" > "$dir/recipient"
printf '%s\n' "$marker_bst" "$marker_pw" "$marker_vpn" "$marker_host" "5E1F7E57-" "PRIVATE KEY" "PUSHMAGIC" > "$dir/markers"
grep -h AGE-SECRET-KEY "$dir/identity" >> "$dir/markers"
rm -rf "$src" "$dir/xlsx" "$dir/empty.xlsx"
printf 'fixture: %s enrollments, %s bytes encrypted, recipient %s%s\n' \
  "$count" "$(stat -c %s "$dir/backup.tar.zst.age")" "$recipient" \
  "$([ "$broken_deus" = 1 ] && echo ', deus.db with a table the new schema cannot build on')$([ "$dangling_fk" = 1 ] && echo ', deus.db with a dangling rack_slots foreign key')$([ "$empty_deus" = 1 ] && echo ', an empty deus.db')$([ "$no_heartbeats" = 1 ] && echo ', deus.db without heartbeats rows')${omit:+, without $omit}"
