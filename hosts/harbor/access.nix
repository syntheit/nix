{ ... }:

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
          "harbor.matv.io" = "ssh://localhost:64829";
          "request.matv.io" = "http://localhost:5055";
          "links.matv.io" = "http://localhost:28793";
          "cloud.matv.io" = {
            service = "https://localhost:9787";
            originRequest.noTLSVerify = true;
          };
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

}
