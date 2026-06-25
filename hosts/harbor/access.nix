{ pkgs, ... }:

{
  # =====================================================
  # COCKROACH ACCESS INFRASTRUCTURE
  # Never restart access services during nixos-rebuild switch.
  # Changes only take effect on reboot. This prevents losing access.
  # =====================================================

  services.cloudflared = {
    enable = true;
    tunnels = {
      "harbor" = {
        ingress = {
          "harbor-ssh.matv.io" = "ssh://localhost:64829";
          "request.matv.io" = "http://localhost:5055";
          "links.matv.io" = "http://localhost:28793";
          "downloader.matv.io" = "http://localhost:9091";
          "prowlarr.matv.io" = "http://localhost:9696";
          "sonarr.matv.io" = "http://localhost:8989";
          "radarr.matv.io" = "http://localhost:7878";
          "bazarr.matv.io" = "http://localhost:6767";
          "notes.matv.io" = "http://localhost:5230";
          "vault.matv.io" = "http://localhost:29446";
          "drivehealth.matv.io" = "http://localhost:5153";
          "sync.matv.io" = "http://localhost:8384";
          "retrospend.app" = "http://localhost:1997";
          "tracearr.matv.io" = "http://localhost:7898";
          "dav.matv.io" = "http://localhost:5232";
          "grafana.matv.io" = "http://localhost:3100";
          "paperless.matv.io" = "http://localhost:28981";
          "keep.matv.io" = "http://localhost:3030";
          "docs.matv.io" = "http://localhost:3040";
          "map.matv.io" = "http://localhost:8100";
          "files.matv.io" = "http://localhost:4717";
          "asado-list.matv.io" = "http://localhost:4730";
          "malli-dev.sudoman.net" = "http://localhost:8787";
          "pro-malli-dev.sudoman.net" = "http://localhost:3000";
        };
        default = "http_status:404";
        credentialsFile = "/etc/cloudflared/credentials.json";
      };
    };
  };
  systemd.services.cloudflared-tunnel-harbor.restartIfChanged = false;

  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  systemd.services.tailscaled.restartIfChanged = false;

  # ---------------------------------------------------------------
  # Tailscale endpoint self-heal.
  #
  # harbor lives behind a NAT we don't control (a router at a remote
  # site). Peers reach harbor's tailscale UDP port only through a
  # *dynamic* UPnP/NAT-PMP mapping on that router. If the lease lapses
  # — e.g. the router reboots or its mapping table churns — harbor keeps
  # advertising a now-dead public endpoint, peers can no longer reach it
  # directly, and tailscale wedges on the stale path instead of cleanly
  # falling back to DERP (its tiny disco probes still squeak through, so
  # it never demotes the dead path). Symptom: `tailscale status` shows
  # the peer as `direct <ip>:<port>` with tx climbing and rx frozen.
  #
  # The router isn't ours to configure (the textbook fix — a static UDP
  # port-forward — isn't available), so the only lever is on harbor.
  # `rebind` re-creates magicsock's UDP socket (re-acquiring the NAT
  # port-mapping) and `restun` re-derives + republishes our public
  # endpoint. These are exactly what tailscale does on a network change:
  # they do NOT drop the daemon or existing sessions (verified live).
  # Running them on a short timer bounds endpoint staleness to one
  # interval, so a lapsed mapping self-corrects within minutes instead of
  # staying broken until someone manually restarts tailscaled.
  systemd.services.tailscale-reendpoint = {
    description = "Refresh tailscale NAT port-mapping + public endpoint (harbor is behind a NAT we don't control)";
    after = [ "tailscaled.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "tailscale-reendpoint" ''
        ${pkgs.tailscale}/bin/tailscale debug rebind || true
        ${pkgs.tailscale}/bin/tailscale debug restun || true
      '';
    };
  };

  systemd.timers.tailscale-reendpoint = {
    description = "Periodically refresh tailscale endpoint so a lapsed NAT mapping self-heals";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "10min";
      RandomizedDelaySec = "30s";
    };
  };

}
