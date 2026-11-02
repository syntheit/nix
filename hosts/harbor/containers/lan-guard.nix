{ ... }:

# Docker publishes ports with a DNAT in PREROUTING, so they never reach the
# NixOS input firewall: every 0.0.0.0 port was open to the LAN at the friend's
# house (and to anything UPnP forwards there). Drop new connections that come
# in on the LAN NIC and were DNAT'd to a container. Only the forward hook is
# touched, so host access (sshd, tailscaled, cloudflared, wg0) is unaffected,
# and traffic from wg0 (conduit Caddy/DNAT) and tailscale0 still gets through.
# Syncthing stays reachable for direct peer connections.
{
  networking.nftables.tables.docker-lan-guard = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority filter - 5;
        iifname "enp4s0" ct state new ct status dnat ct original proto-dst != { 21027, 22000 } counter drop
      }
    '';
  };
}
