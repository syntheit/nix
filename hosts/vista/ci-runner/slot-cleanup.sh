# shellcheck shell=bash
# After each CI VM exits, as root (ExecStopPost of ci-slot<N>). Best effort:
# drop the runner registration if the VM never used it (after a job GitHub has
# removed it already and this 404s), the tap and both disks.
n=$1
run="/run/ci-vm/slot$n"

if [ -s "$run/runner-id" ]; then
  curl -fsS -o /dev/null -X DELETE \
    -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$TOKEN_FILE")") \
    -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$REPO/actions/runners/$(cat "$run/runner-id")" || true
fi
rm -rf "$run"
ip link del "ci$n" 2>/dev/null || true
rm -f "/var/lib/ci-vm/slot$n/work.img" "/var/lib/ci-vm/slot$n/jit.img"
