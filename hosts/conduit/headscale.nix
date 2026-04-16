# Headscale — open-source Tailscale coordination server.
# Runs natively (not Docker) via the NixOS module.
# Exposed via Caddy reverse proxy at headscale.matv.io.
#
# Cannot use Cloudflare Tunnel — Tailscale's TS2021 protocol uses
# WebSocket upgrades via HTTP POST, which Cloudflare blocks.
# https://github.com/juanfont/headscale/issues/3060
#
# Admin commands:
#   headscale users create malli
#   headscale preauthkeys create --user malli --reusable --expiration 720h
#   headscale nodes list

{ ... }:

{
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
  services.caddy.virtualHosts."headscale.matv.io" = {
    extraConfig = ''
      reverse_proxy localhost:8085
    '';
  };
}
