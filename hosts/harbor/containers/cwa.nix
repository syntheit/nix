{ ... }:

{
  # Calibre-Web Automated — eBook library, OPDS, and Kobo Sync server.
  # Public access via conduit's Caddy at https://library.matv.io
  # (Caddy → 10.100.0.2:8083 over WireGuard; wg0 is firewall-trusted, so
  # only conduit and localhost can reach the container).
  #
  # Books are uploaded directly via CWA's web UI.
  virtualisation.oci-containers.containers.cwa = {
    image = "crocodilestick/calibre-web-automated:v4.0.6";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
    };
    ports = [ "8083:8083" ];
    volumes = [
      "/arespool/appdata/cwa/config:/config"
      "/arespool/appdata/cwa/library:/calibre-library"
      "/arespool/appdata/cwa/plugins:/config/.config/calibre/plugins"
    ];
  };

  systemd.tmpfiles.rules = [
    # Numeric UID/GID — matches container's PUID=1000 (host user `matv`).
    # Hardcoded so a `matv` rename doesn't silently break the container.
    "d /arespool/appdata/cwa            0755 1000 1000 -"
    "d /arespool/appdata/cwa/config     0755 1000 1000 -"
    "d /arespool/appdata/cwa/library    0755 1000 1000 -"
    "d /arespool/appdata/cwa/plugins    0755 1000 1000 -"
  ];
}
