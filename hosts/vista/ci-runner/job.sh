# shellcheck shell=bash
# Inside a CI VM, once per boot (./guest.nix): check the VM is contained, run
# exactly one GitHub Actions job, power off. Any failure powers off too, so a
# VM that fails its self-check never starts the runner.
set -euo pipefail
trap 'systemctl poweroff --no-block' EXIT

fail() {
  echo "ci-job: $*" >&2
  exit 1
}

for _ in $(seq 20); do
  [ -e /dev/disk/by-label/cijit ] && break
  sleep 0.5
done
mkdir -p /run/jit
mount -o ro,nosuid,nodev,noexec /dev/disk/by-label/cijit /run/jit

# 1. Self-check, before any job code runs. Every host:port in `blocked` (vista,
# the LAN, the tailnet, wg0) must time out (curl exit 28): vista drops these
# silently, so a refusal, an ICMP error or a connection means something changed.
pids=()
while read -r target; do
  [ -n "$target" ] || continue
  (
    rc=0
    err=$(curl -sS --connect-timeout 4 -o /dev/null "telnet://$target" </dev/null 2>&1) || rc=$?
    [ "$rc" = 28 ] || fail "isolation: $target did not time out (curl exit $rc: $err)"
  ) &
  pids+=("$!")
done </run/jit/blocked
for pid in "${pids[@]}"; do
  wait "$pid" || fail "isolation self-check failed"
done

exit_ip=$(curl -4fsS --max-time 15 https://api.ipify.org) || fail "no route out (tunnel down?)"
[ "$exit_ip" != "$(cat /run/jit/home_ip)" ] || fail "isolation: traffic leaves on the home IP"
echo "ci-job: isolation ok, exit IP $exit_ip"

# 2. One job, in GitHub's runner image. The VM's Docker socket goes in (root in
# the VM, which is the boundary), and the work dir is mounted at the same path
# so containers the job starts (services, run.sh's browser) see the checkout.
mkdir -p /var/lib/ci/work /home/runner/_work
chown 1001:1001 /var/lib/ci/work
mount --bind /var/lib/ci/work /home/runner/_work

image=ghcr.io/actions/actions-runner:latest
for _ in 1 2 3; do
  docker pull -q "$image" && break
  sleep 5
done

ACTIONS_RUNNER_INPUT_JITCONFIG=$(cat /run/jit/jitconfig)
export ACTIONS_RUNNER_INPUT_JITCONFIG
docker run --rm --name runner --network host --shm-size 2g \
  --group-add "$(stat -c %g /var/run/docker.sock)" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /home/runner/_work:/home/runner/_work \
  -e ACTIONS_RUNNER_INPUT_JITCONFIG \
  "$image" ./run.sh
