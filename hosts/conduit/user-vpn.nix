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
    iptablesChain = allowChain;
    # Reuse deus-server's operator token — same humans manage both
    # surfaces. The activation script in headscale.nix stages
    # /run/secrets/deus_operator_token into this file.
    operatorTokenFile = "/var/lib/deus-tokens/operator-token";
    # Headscale's unix socket lives inside the nspawn container at
    # /run/headscale and isn't bind-mounted out — the simplest way
    # for a host-side process to query it is `nixos-container run`,
    # which enters the container's namespaces and execs the command
    # there. The container's `headscale` binary is on its system
    # PATH; we use the absolute path through the running closure
    # so we don't depend on the container's PATH ordering.
    headscaleCommand = "nixos-container run headscale -- /run/current-system/sw/bin/headscale nodes list -o json";
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

  # ── iptables: per-peer chain + default-deny + NAT ─────────
  # NixOS firewall is iptables-based on this host (don't switch to
  # nftables — the existing wg0 setup uses iptables masquerade). We
  # add our chain via the firewall's extraCommands, and the deus
  # uservpn package adds individual peer rules at runtime.
  #
  # Chain layout:
  #   FORWARD:
  #     -s 10.99.0.0/24 -j MALLI_USERVPN     (jump to our chain)
  #     -d 10.99.0.0/24 -j MALLI_USERVPN_RET (return-traffic chain — accept established)
  #
  #   MALLI_USERVPN:
  #     [runtime-managed per-peer ACCEPTs at top of chain]
  #     -j DROP                              (default-deny tail)
  #
  #   MALLI_USERVPN_RET:
  #     -m state --state ESTABLISHED,RELATED -j ACCEPT
  #     -j DROP
  networking.firewall.extraCommands = lib.mkAfter ''
    # Idempotent: -N creates if missing; -F flushes; we always set up
    # the chains fresh at firewall (re)load. Runtime per-peer rules
    # are re-added by the deus uservpn package's reconcile loop on
    # startup, so flushing here is safe.
    iptables -N ${allowChain} 2>/dev/null || true
    iptables -F ${allowChain}
    iptables -A ${allowChain} -j DROP

    iptables -N ${allowChain}_RET 2>/dev/null || true
    iptables -F ${allowChain}_RET
    iptables -A ${allowChain}_RET -m state --state ESTABLISHED,RELATED -j ACCEPT
    iptables -A ${allowChain}_RET -j DROP

    # Wire the chains into FORWARD. -C tests existence first so we
    # don't append duplicates on reload.
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
