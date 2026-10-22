{ vars, ... }:

# Encrypted NextDNS plus Tailscale MagicDNS on the Macs, the same split the
# NixOS hosts get from systemd-resolved (system/default.nix).
#
# Neither half can do it alone on macOS:
# - Tailscale DNS on (accept-dns): quad-100 answers tailnet names and sends
#   everything else to the router in plain DNS, bypassing any NextDNS
#   profile ("unconfigured" on test.nextdns.io).
# - A NextDNS configuration profile: takes every query, tailnet names too,
#   which NextDNS can't answer; /etc/resolver entries don't get a look in.
#
# So the nextdns CLI runs as the local resolver on 127.0.0.1 and every
# network service points its DNS there (set below: -auto-activate did nothing
# under launchd): public names over DoH to the profile, *.ts.net forwarded to
# quad-100, which still answers with accept-dns off. The tailnet search domain keeps short
# names (`harbor`, `mantle`) working. Don't install the NextDNS profile on
# top: it would take over again.
let
  tailnet = "tail004a08.ts.net";
  tailscale = "/usr/local/bin/tailscale"; # shim from the tailscale-app cask
in
{
  services.nextdns = {
    enable = true;
    arguments = [
      "-profile 57bc2c"
      "-listen 127.0.0.1:53"
      "-forwarder ts.net.=100.100.100.100"
      "-report-client-info"
      "-detect-captive-portals"
      "-cache-size 10MB"
    ];
  };

  system.activationScripts.postActivation.text = ''
    # Tailscale must not override DNS, or it takes every query back.
    if [ -x ${tailscale} ]; then
      sudo -u ${vars.user.name} ${tailscale} set --accept-dns=false 2>/dev/null || true
    fi
    networksetup -listallnetworkservices | tail -n +2 | sed 's/^\*//' | grep -v -x Tailscale | while read -r svc; do
      networksetup -setdnsservers "$svc" 127.0.0.1 2>/dev/null || true
      networksetup -setsearchdomains "$svc" ${tailnet} 2>/dev/null || true
    done
  '';
}
