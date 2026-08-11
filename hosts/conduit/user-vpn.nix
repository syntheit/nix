# User-VPN gateway — independent WireGuard interface for end-user
# remote access to fleet machines. Distinct from:
#   - wg0 (host ↔ harbor link, 10.100.0.0/24 on UDP 51820)
#   - tailscale0 (fleet headscale tailnet)
#
# Architecture: each end user gets a peer on this interface with a
# /32 in 10.99.0.0/24. Their traffic is forwarded onto tailscale0 to
# reach the fleet, but only for (host, port) pairs allowed by per-peer
# iptables rules. Peers and their rules are managed at runtime by the
# deus uservpn package (inside the headscale container) — NOT
# statically in nix — so adding/removing users doesn't redeploy.
#
# See ../../malli-deus/USERVPN.md for the full architectural plan.

{ config, pkgs, lib, inputs, ... }:

let
  iface = "wg-malli";
  subnet = "10.99.0.0/24";
  serverAddr = "10.99.0.1/24";
  listenPort = 51821;       # 51820 is taken by wg0 (harbor link)
  allowChain = "MALLI_USERVPN";
  allowSet = "MALLI_USERVPN_ALLOW";

  # Post-vista-migration (2026-08): the Headscale nspawn no longer runs on
  # conduit, so the old node lookup `nixos-container run headscale …` is dead
  # here. user-vpn is a separate remote-access surface — out of scope for the
  # bot routing this migration unblocks — so we let hostname→IP resolution
  # DEGRADE rather than couple conduit back to vista over SSH/gRPC. The daemon
  # still starts and serves (startup Reconcile re-adds ipset tuples from its own
  # sqlite, not from headscale); only NEW grants that need node resolution fail,
  # and they fail LOUDLY in the journal instead of silently mis-resolving.
  # Re-point at vista's headscale (gRPC, or SSH through the :2222 relay) to
  # re-enable. A single-token script is used because the granter whitespace-
  # splits the argv, so a quoted `sh -c '…'` would not survive.
  headscaleLookupDisabled = pkgs.writeShellScript "uservpn-headscale-disabled" ''
    echo "user-vpn headscale node lookup is disabled on conduit: the Headscale nspawn moved to vista (2026-08). Re-point services.deus.uservpn-server.headscaleCommand at vista to re-enable." >&2
    exit 1
  '';
in
{
  imports = [ inputs.deus.nixosModules.uservpn-server ];

  # ── HTTP server (granter API) ──────────────────────────────
  # Runs on the host as a systemd unit, NOT inside the headscale
  # nspawn container — needs root for `wg` and `iptables` shellouts.
  # Operator endpoints reachable on conduit's tailnet IP at :8087;
  # the public /redeem path is fronted by Caddy at api.themalli.ai
  # (defined in headscale.nix).
  services.deus.uservpn-server = {
    enable = true;
    publicEndpoint = "conduit.matv.io:${toString listenPort}";
    wgInterface = iface;
    ipsetName = allowSet;
    # Reuse deus-server's operator token — same humans manage both surfaces
    # (deus itself now runs in the nspawn on vista; this is the same token
    # value, re-keyed there too). Read the sops secret directly now that the
    # nspawn's deus-stage activation (which used to stage it) has moved off
    # conduit with the container.
    operatorTokenFile = "/run/secrets/deus_operator_token";
    # DEGRADED post-migration: the nspawn (and its headscale socket) moved to
    # vista, so this host can no longer `nixos-container run headscale`. Points
    # at a script that fails loudly (see headscaleLookupDisabled above); the
    # daemon stays up, only new node-resolving grants error. Re-point at vista
    # to restore user-vpn fleet lookups.
    headscaleCommand = "${headscaleLookupDisabled}";
    dnsServers = [ "100.64.0.1" ];
  };

  # Server private key, generated out-of-band and added to sops:
  #   wg genkey | tee /tmp/wg-malli.priv | wg pubkey
  #   sops secrets/conduit.yaml  → paste under wg_malli_private_key
  # Then add to secrets.nix:
  #   sops.secrets.wg_malli_private_key.mode = "0400";
  sops.secrets.wg_malli_private_key = {
    mode = "0400";
    owner = "root";
  };

  # ── WG interface ──────────────────────────────────────────
  networking.wireguard.interfaces.${iface} = {
    ips = [ serverAddr ];
    listenPort = listenPort;
    privateKeyFile = config.sops.secrets.wg_malli_private_key.path;
    # Peers are added/removed at runtime by the deus uservpn package.
    peers = [];
  };

  networking.firewall.allowedUDPPorts = [ listenPort ];

  # Forward enabled in host kernel so packets can route from wg-malli
  # onto tailscale0. (Already set globally for the harbor wg0 NAT
  # case, declaring here is redundant-but-explicit.)
  boot.kernel.sysctl."net.ipv4.ip_forward" = lib.mkDefault 1;

  environment.systemPackages = [ pkgs.ipset ];

  # ── ipset + iptables: O(1) per-tuple ACL + NAT ────────────
  # Per-peer ACL is a hash:ip,port,ip ipset of (src_ip, dst_port,
  # dst_ip) triples. (ipset's only valid 3-tuple ip-port-ip type
  # orders fields as ip,port,ip — not ip,ip,port.) Hashtable matches
  # in O(1) regardless of member count, so the chain stays at two
  # static rules even at fleet scale (planned: 600 users × ~3 dsts
  # × ~3 ports = ~5400 tuples).
  #
  # Chain layout:
  #   FORWARD:
  #     -s 10.99.0.0/24 -j MALLI_USERVPN     (egress from WG peers)
  #     -d 10.99.0.0/24 -j MALLI_USERVPN_RET (return traffic)
  #
  #   MALLI_USERVPN:
  #     -m set --match-set MALLI_USERVPN_ALLOW src,dst,dst -j ACCEPT
  #     -j DROP                                   (default-deny)
  #
  #   MALLI_USERVPN_RET:
  #     -m state --state ESTABLISHED,RELATED -j ACCEPT
  #     -j DROP
  networking.firewall.extraCommands = lib.mkAfter ''
    # ipset: declare once, runtime adds/removes happen via the deus
    # uservpn package. -exist makes recreate idempotent across reloads.
    ${pkgs.ipset}/bin/ipset create ${allowSet} hash:ip,port,ip \
      family inet hashsize 1024 maxelem 65536 -exist

    # Forward chain: idempotent recreate (-N if missing, -F flush).
    # Runtime ACL state lives in the ipset, NOT the chain — the chain
    # itself stays at two rules forever. Reload-safe: ipset survives
    # firewall reload (we only flush iptables, not ipset).
    iptables -N ${allowChain} 2>/dev/null || true
    iptables -F ${allowChain}
    iptables -A ${allowChain} -m set --match-set ${allowSet} src,dst,dst -j ACCEPT
    iptables -A ${allowChain} -j DROP

    iptables -N ${allowChain}_RET 2>/dev/null || true
    iptables -F ${allowChain}_RET
    iptables -A ${allowChain}_RET -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A ${allowChain}_RET -j DROP

    # Wire chains into FORWARD. -C avoids duplicate appends on reload.
    iptables -C FORWARD -s ${subnet} -j ${allowChain} 2>/dev/null \
      || iptables -A FORWARD -s ${subnet} -j ${allowChain}
    iptables -C FORWARD -d ${subnet} -j ${allowChain}_RET 2>/dev/null \
      || iptables -A FORWARD -d ${subnet} -j ${allowChain}_RET

    # Masquerade WG → tailnet so return packets find their way back.
    iptables -t nat -C POSTROUTING -s ${subnet} -o tailscale0 -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s ${subnet} -o tailscale0 -j MASQUERADE
  '';

  networking.firewall.extraStopCommands = ''
    iptables -t nat -D POSTROUTING -s ${subnet} -o tailscale0 -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -d ${subnet} -j ${allowChain}_RET 2>/dev/null || true
    iptables -D FORWARD -s ${subnet} -j ${allowChain} 2>/dev/null || true
    iptables -F ${allowChain}_RET 2>/dev/null || true
    iptables -X ${allowChain}_RET 2>/dev/null || true
    iptables -F ${allowChain} 2>/dev/null || true
    iptables -X ${allowChain} 2>/dev/null || true
    # NB: ipset is NOT destroyed on firewall stop — the daemon's
    # PartOf=firewall.service triggers a Reconcile that re-adds tuples
    # if the set goes missing, but keeping the set intact across
    # firewall reloads avoids a window where active connections drop.
  '';

  # ── Runtime control surface ───────────────────────────────
  # The user-vpn HTTP server and operator CLI live in malli-deus but
  # run as a SEPARATE host-side systemd unit (NOT inside the headscale
  # nspawn container) so they can shell out to `wg` and `iptables`
  # without container capability gymnastics.
  #
  # Unit:    systemd.services.malli-uservpn-server (declared elsewhere)
  # Binary:  $out/bin/malli-uservpn-server
  # State:   /var/lib/malli-uservpn/tokens.db (sqlite)
  # Listen:  127.0.0.1:8087 — Caddy proxies the public redeem endpoint
  #          to https://api.themalli.ai/v1/user-vpn/redeem
  #
  # The deus operator CLI's `deus user-vpn` subcommands talk to this
  # server (NOT to the deus-server in the container) — mostly via
  # tailnet from inside the container, since fleet operators SSH into
  # the container, but the server is reachable on conduit's tailnet
  # IP from anywhere on the headscale tailnet.
  #
  # See ../../malli-deus/USERVPN.md and ../../malli-deus/internal/uservpn/.
}
