# shellcheck shell=bash
# Before each CI VM boot, as root (ExecStartPre of ci-slot<N>). Refuses to boot
# unless the routing and firewall that contain the VM are in place, then makes
# the tap, a fresh jit disk with a single-use runner config, and the
# self-check targets. Env from ./default.nix: REPO, TABLE, TOKEN_FILE, BLOCKED.
n=$1
tap="ci$n"
dir="/var/lib/ci-vm/slot$n"
run="/run/ci-vm/slot$n"

die() {
  echo "ci-slot$n: $*" >&2
  exit 1
}

ip rule show | grep -q "iif $tap lookup $TABLE" || die "policy routing rule missing"
ip route show table "$TABLE" | grep -q '^unreachable default' || die "killswitch route missing"
iptables -t raw -C PREROUTING -i ci+ -j ci-raw 2>/dev/null || die "raw firewall missing"
iptables -C INPUT -i ci+ -j ci-in 2>/dev/null || die "input firewall missing"
iptables -C FORWARD -i ci+ -j ci-fwd 2>/dev/null || die "forward firewall missing"
ip6tables -t raw -C PREROUTING -i ci+ -j DROP 2>/dev/null || die "ipv6 drop missing"

install -d -m 0700 "$run"
rm -f "$dir/work.img" "$dir/jit.img"

ip link del "$tap" 2>/dev/null || true
ip tuntap add name "$tap" mode tap user ci-vm vnet_hdr multi_queue
echo 1 >"/proc/sys/net/ipv6/conf/$tap/disable_ipv6"
ip addr add "10.77.$n.1/30" dev "$tap"
ip link set "$tap" up
# resolved would otherwise announce vista over LLMNR/mDNS on the tap.
resolvectl llmnr "$tap" no 2>/dev/null || true
resolvectl mdns "$tap" no 2>/dev/null || true

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT

# The guest checks it cannot reach any of these, and is not leaving on the
# home IP (looked up here, over vista's own line).
lan_ip=$(ip -4 route get 1.1.1.1 | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')
gw=$(ip -4 route show default | awk '{print $3; exit}')
home_ip=$(curl -4fsS --max-time 10 https://api.ipify.org) || die "cannot look up the home IP"
printf '%s\n' "$BLOCKED" "10.77.$n.1:22" "$lan_ip:22" "$gw:80" >"$stage/blocked"
echo "$home_ip" >"$stage/home_ip"

# Single-use runner config: one job, on this VM only. The token never leaves
# the host; it reaches curl through a pipe, not argv.
body=$(jq -cn --arg name "vista-ci-$n-$(date +%s)" \
  '{name: $name, runner_group_id: 1, labels: ["self-hosted", "vista-ci"], work_folder: "_work"}')
resp=$(curl -fsS -X POST \
  -H @<(printf 'Authorization: Bearer %s\n' "$(cat "$TOKEN_FILE")") \
  -H 'Accept: application/vnd.github+json' \
  -d "$body" \
  "https://api.github.com/repos/$REPO/actions/runners/generate-jitconfig") ||
  die "could not mint a runner config"
jq -r .runner.id <<<"$resp" >"$run/runner-id"
(umask 077 && jq -r .encoded_jit_config <<<"$resp" >"$stage/jitconfig")

truncate -s 16M "$dir/jit.img"
mkfs.ext4 -q -L cijit -d "$stage" "$dir/jit.img"
chown ci-vm:ci-vm "$dir/jit.img"
chmod 0400 "$dir/jit.img"
