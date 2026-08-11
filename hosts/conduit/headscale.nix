# Fleet control-plane RELAY (post-migration to vista, 2026-08).
#
# The Headscale + deus + git-mirror nspawn and the two registries moved to
# vista (hosts/vista/{headscale,registry,zot}.nix) — vista has the RAM/CPU this
# 1 GB VPS lacked (Headscale couldn't deliver fresh nodes their initial netmap
# under load, which broke new-node onboarding). conduit stays the thin PUBLIC
# RELAY: it keeps the public IP + TLS + the wg0 hub, and forwards every
# fleet-facing endpoint to vista (10.100.0.4) over WireGuard. `server_url` is
# unchanged (headscale.matv.io), so the ~349 fleet nodes never re-register.
#
#   Caddy  headscale.matv.io / mini.themalli.ai → vista:8085 (Headscale)
#          bootstrap.matv.io  (device ADE paths) → vista:8086 (deus)
#          bootstrap.matv.io  /pkg/*             → local file_server (pkg stays here)
#          mdm/scep/enroll.matv.io               → mantle 10.100.0.3
#   socat  :5000 / :5001  → vista (docker + zot registries)
#          :8086 (deus)   → vista   [fleet tailnet 100.64.0.1 + mantle ADE webhook via wg]
#          :9418 (git://) → vista
#          :2222 (ssh)    → vista   [public operator SSH into the nspawn]
#          :9990          → mantle 10.100.0.3   [deus-on-vista's ADE call, hub-routed]

{ pkgs, ... }:

let
  vista = "10.100.0.4";
  mantle = "10.100.0.3";

  headscale-ui = pkgs.fetchzip {
    url = "https://github.com/gurucomputing/headscale-ui/releases/download/2025.01.20/headscale-ui.zip";
    hash = "sha256-eMT3/UsTYkiJFzoWlNPOM6hgbyGoBbPi3cs/u71KJ0c=";
    stripRoot = false;
  };

  # A socat TCP forwarder as a systemd service. `listen` is host:port on
  # conduit; `dest` is host:port to forward to (vista over wg, or mantle).
  socatProxy = name: desc: listen: dest: {
    "${name}" = {
      description = desc;
      after = [ "network-online.target" "tailscaled.service" "wg-quick-wg0.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:${listen},fork,reuseaddr TCP:${dest}";
        Restart = "always";
        RestartSec = "5s";
      };
    };
  };
in
{
  # Signed ADE bootstrap pkg is still SERVED FROM conduit by Caddy (file_server
  # below) — Daniel scp's the nix-built + signed pkg here. Only the dir stays on
  # conduit; the deus ADE logic that references the pkg URL runs on vista.
  systemd.tmpfiles.rules = [
    "d /var/lib/malli-bootstrap 0755 root root -"
  ];

  # ── Tailscale (on host) ─────────────────────────────────────
  # conduit stays a malli-tailnet node (100.64.0.1) so it can socat-forward the
  # tailnet-facing endpoints (deus/git/registries) to vista. It connects to its
  # own Caddy front (headscale.matv.io → vista). Unchanged from before the move.
  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--login-server"
      "https://headscale.matv.io"
      "--hostname"
      "conduit"
    ];
  };

  # ── Caddy reverse proxy (on host) ─────────────────────────
  services.caddy.virtualHosts."headscale.matv.io" = {
    extraConfig = ''
      handle /web/* {
        root * ${headscale-ui}
        file_server
        try_files {path} /web/index.html
      }
      redir /web /web/ permanent
      handle /api/* {
        @options method OPTIONS
        header @options Access-Control-Allow-Origin "*"
        header @options Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header @options Access-Control-Allow-Headers "Authorization, Content-Type"
        header @options Access-Control-Max-Age "86400"
        respond @options 204
        reverse_proxy ${vista}:8085
      }
      handle {
        reverse_proxy ${vista}:8085
      }
    '';
  };
  services.caddy.virtualHosts."mini.themalli.ai" = {
    extraConfig = ''
      handle /v1/user-vpn/redeem {
        reverse_proxy localhost:8087
      }
      handle /connect* {
        reverse_proxy localhost:8087
      }
      handle /Malli.dmg {
        root * /var/lib/malli-uservpn
        file_server
      }
      handle /appcast.xml {
        root * /var/lib/malli-uservpn
        file_server
      }
      handle {
        reverse_proxy ${vista}:8085
      }
    '';
  };
  services.caddy.virtualHosts."bootstrap.matv.io" = {
    extraConfig = ''
      handle /ade/bootstrap-creds {
        reverse_proxy ${vista}:8086
      }
      handle /healthz {
        reverse_proxy ${vista}:8086
      }
      handle_path /pkg/* {
        root * /var/lib/malli-bootstrap
        file_server
      }
      handle {
        respond "not found" 404
      }
    '';
  };
  services.caddy.virtualHosts."mdm.matv.io".extraConfig = ''
    reverse_proxy ${mantle}:9990
  '';
  services.caddy.virtualHosts."scep.matv.io".extraConfig = ''
    reverse_proxy ${mantle}:8081
  '';
  services.caddy.virtualHosts."enroll.matv.io".extraConfig = ''
    reverse_proxy ${mantle}:9991
  '';

  # ── socat forwards to vista (and mantle) ───────────────────
  # Only Headscale fleet machines (tailscale0) + the wg mesh can reach these.
  systemd.services =
    (socatProxy "registry-proxy" "Docker registry → vista over wg" "5000" "${vista}:5000")
    // (socatProxy "zot-proxy" "Zot OCI registry → vista over wg" "5001" "${vista}:5001")
    // (socatProxy "deus-proxy" "deus-server → vista (fleet + ADE webhook)" "8086" "${vista}:8086")
    // (socatProxy "git-mirror-proxy" "git:// mirror → vista over wg" "9418" "${vista}:9418")
    // (socatProxy "operator-ssh-proxy" "operator SSH into the nspawn → vista" "2222" "${vista}:2222")
    // (socatProxy "nanomdm-proxy" "deus-on-vista's ADE call → mantle (hub-routed)" "9990" "${mantle}:9990");

  # Fleet-facing tailnet ports (blocked from the internet), plus the wg0-only
  # nanomdm forward. Public :2222 for operator SSH into the moved nspawn.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5000 5001 8086 9418 ];
  networking.firewall.interfaces.wg0.allowedTCPPorts = [ 8086 9990 ];
  networking.firewall.allowedTCPPorts = [ 2222 ];
}
