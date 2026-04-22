# Headscale — open-source Tailscale coordination server.
# Runs natively (not Docker) via the NixOS module.
# Exposed via Caddy reverse proxy at headscale.matv.io.
#
# Cannot use Cloudflare Tunnel — Tailscale's TS2021 protocol uses
# WebSocket upgrades via HTTP POST, which Cloudflare blocks.
# https://github.com/juanfont/headscale/issues/3060
#
# Admin commands:
#   sudo headscale users create malli
#   sudo headscale preauthkeys create --user 1 --reusable --expiration 720h
#   sudo headscale nodes list

{ pkgs, ... }:

let
  # Static SPA — no server process, just files served by Caddy.
  # User enters Headscale URL + API key in the browser on first visit.
  # Credentials are stored in browser local storage only.
  headscale-ui = pkgs.fetchzip {
    url = "https://github.com/gurucomputing/headscale-ui/releases/download/2025.01.20/headscale-ui.zip";
    hash = "sha256-eMT3/UsTYkiJFzoWlNPOM6hgbyGoBbPi3cs/u71KJ0c=";
    stripRoot = false;
  };
in
{
  # ── Conduit is both Headscale server AND a client on its own network ──
  # This makes conduit reachable from the Malli fleet (Mac Mini VMs),
  # allowing it to proxy the Docker registry from harbor over WireGuard.
  services.tailscale = {
    enable = true;
    # Auth key created via: headscale preauthkeys create --user 1 --reusable --expiration 8760h
    # Write to /etc/tailscale/authkey on conduit manually (one-time).
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--login-server" "https://headscale.matv.io"
      "--hostname" "conduit"
    ];
  };

  services.headscale = {
    enable = true;
    address = "127.0.0.1";
    port = 8085;

    settings = {
      server_url = "https://headscale.matv.io";

      # DNS — base_domain MUST differ from server_url domain
      dns = {
        magic_dns = true;
        base_domain = "tail.matv.io";
        override_local_dns = true;
        nameservers.global = [
          "1.1.1.1"
          "1.0.0.1"
        ];
      };

      # IP allocation for tailnet nodes
      prefixes = {
        v4 = "100.64.0.0/10";
        v6 = "fd7a:115c:a1e0::/48";
        allocation = "sequential";
      };

      # Use Tailscale's free public DERP relay servers.
      # We can add our own later if needed for privacy/latency.
      derp = {
        urls = [ "https://controlplane.tailscale.com/derpmap/default" ];
        auto_update_enabled = true;
        update_frequency = "3h";
      };

      # SQLite is the recommended DB — Postgres is discouraged by maintainers
      database = {
        type = "sqlite";
        sqlite = {
          path = "/var/lib/headscale/db.sqlite";
          write_ahead_log = true;
        };
      };

      # Don't phone home
      logtail.enabled = false;
      disable_check_updates = true;

      # Nodes don't expire (we manage lifecycle ourselves)
      node.expiry = 0;
    };
  };

  # Caddy reverse proxy — handles TLS automatically via Let's Encrypt.
  # WebSocket upgrades work natively with Caddy (no special config).
  # Headscale-UI served at /web — same origin as API, no CORS needed.
  services.caddy.virtualHosts."headscale.matv.io" = {
    extraConfig = ''
      handle_path /web* {
        root * ${headscale-ui}
        file_server
      }
      handle {
        reverse_proxy localhost:8085
      }
    '';
  };

  # ── Docker Registry proxy ──────────────────────────────────
  # Forwards port 5000 from Tailscale interface to harbor's registry
  # over WireGuard. Only Headscale fleet machines can reach it.
  #
  # Mac Minis pull from: http://conduit:5000/malli/cursor-runner:latest
  systemd.services.registry-proxy = {
    description = "Proxy Docker registry to harbor over WireGuard";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:5000,fork,reuseaddr TCP:10.100.0.2:5000";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Only open port 5000 on the Tailscale interface — blocked from the internet
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5000 ];
}
