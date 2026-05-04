{ config, pkgs, ... }:

# =====================================================================
# Recyclarr — keeps Sonarr/Radarr Custom Formats and quality profiles
# in sync with the TRaSH Guides community recommendations.
#
# Runs as a systemd-triggered one-shot Docker container (no daemon).
# Config lives at /arespool/appdata/recyclarr/recyclarr.yml.
# API keys are extracted at run-time from the *arr config.xml files,
# exported as env vars, and consumed by the yml via !env_var.
# =====================================================================

{
  systemd.tmpfiles.rules = [
    "d /arespool/appdata/recyclarr 0750 matv users -"
    "d /arespool/appdata/recyclarr/cache 0750 matv users -"
  ];

  systemd.services.recyclarr-sync = {
    description = "Sync Sonarr/Radarr profiles with TRaSH Guides via Recyclarr";
    after = [ "docker.service" "docker-sonarr.service" "docker-radarr.service" ];
    wants = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";   # needs to read the *arr config.xml files (root-readable)
      ExecStart = pkgs.writeShellScript "recyclarr-sync" ''
        set -euo pipefail

        # Pull API keys directly from the *arr config files. Avoids hard-coding
        # them in nix/sops while still being declaratively re-runnable.
        SONARR_API_KEY=$(${pkgs.gnugrep}/bin/grep -oP '(?<=<ApiKey>)[^<]+' /arespool/appdata/sonarr/config.xml)
        RADARR_API_KEY=$(${pkgs.gnugrep}/bin/grep -oP '(?<=<ApiKey>)[^<]+' /arespool/appdata/radarr/config.xml)

        if [ ''${#SONARR_API_KEY} -ne 32 ] || [ ''${#RADARR_API_KEY} -ne 32 ]; then
          echo "ERROR: API key length mismatch (sonarr=''${#SONARR_API_KEY}, radarr=''${#RADARR_API_KEY})" >&2
          exit 1
        fi

        ${pkgs.docker}/bin/docker run --rm \
          --network=host \
          -v /arespool/appdata/recyclarr:/config \
          -e SONARR_API_KEY="$SONARR_API_KEY" \
          -e RADARR_API_KEY="$RADARR_API_KEY" \
          -e TZ=America/New_York \
          ghcr.io/recyclarr/recyclarr:latest \
          sync
      '';
    };
  };

  systemd.timers.recyclarr-sync = {
    description = "Run Recyclarr nightly to keep profiles current with TRaSH Guides";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:30:00";   # 4:30 AM, after restic offsite
      RandomizedDelaySec = "30min";
      Persistent = true;
    };
  };
}
