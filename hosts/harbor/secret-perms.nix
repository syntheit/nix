{ ... }:

# App config files that hold credentials (API keys, app keys, password hashes)
# were world-readable (0644). Owners stay as they are (each app reads its own
# file as that owner); only "other" loses read. `z` re-applies the mode at boot
# and on every switch, since some apps rewrite these files with their umask.
{
  systemd.tmpfiles.rules = map (f: "z ${f} 0600 - - -") [
    "/arespool/appdata/sonarr/config.xml"
    "/arespool/appdata/radarr/config.xml"
    "/arespool/appdata/prowlarr/config.xml"
    "/arespool/appdata/jellyseerr_config/settings.json" # pre-native Seerr config, kept for restic
    "/arespool/appdata/radicale/htpasswd"
    "/arespool/appdata/pelican/panel-data/.env"
    "/arespool/appdata/cwa/config/.key"
  ];
}
