{ config, pkgs, ... }:

{
  # ===== CALIBRE-WEB-AUTOMATED =====
  # Library + OPDS + Kobo Sync server. Books arrive via the rclone pull
  # below into /arespool/cwa-ingest, where CWA's polling watcher picks
  # them up, enriches metadata, and moves them into the Calibre library
  # (then deletes the local ingest copy).
  virtualisation.oci-containers.containers.cwa = {
    image = "crocodilestick/calibre-web-automated:V4.0.6";
    environment = {
      PUID = "1000";
      PGID = "1000";
      TZ = "America/New_York";
      # Cloudflare Tunnel = 1 proxy hop (issue #841 — required for OPDS auth
      # via X-Forwarded-* headers).
      TRUSTED_PROXY_COUNT = "1";
      # rclone writes downloaded books non-atomically; CWA's poll-mode
      # size-stability watcher is more reliable than inotify here.
      NETWORK_SHARE_MODE = "true";
    };
    ports = [ "127.0.0.1:8083:8083" ];
    volumes = [
      "/arespool/appdata/cwa/config:/config"
      "/arespool/appdata/cwa/library:/calibre-library"
      "/arespool/appdata/cwa/plugins:/config/.config/calibre/plugins"
      "/arespool/cwa-ingest:/cwa-book-ingest"
    ];
  };

  # ===== SEAFILE → CWA INGEST (rclone, 60s timer) =====
  # Drop a book into the Seafile "Books" library; rclone moves it into
  # /arespool/cwa-ingest within ~1 min. CWA enriches it, files it into
  # the Calibre library, and deletes the local copy. Move semantics
  # drain the Books library, so the Calibre library is the canonical archive.
  #
  # One-way by design — CWA's post-ingest deletes never reach Seafile,
  # because rclone is invoked outbound only and never re-mirrors.
  systemd.services.cwa-ingest-pull = {
    description = "rclone Seafile drop folder → CWA ingest";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.rclone ];

    script = ''
      set -eu
      rclone move \
        --config "$CREDENTIALS_DIRECTORY/rclone.conf" \
        --min-age 30s \
        --create-empty-src-dirs=false \
        seafile-books: /arespool/cwa-ingest
    '';

    serviceConfig = {
      Type = "oneshot";
      User = "cwa-ingest";
      Group = "books";
      UMask = "0002";
      LoadCredential = [
        "rclone.conf:${config.sops.templates."rclone-seafile.conf".path}"
      ];
      ReadWritePaths = [ "/arespool/cwa-ingest" ];
    };
  };

  systemd.timers.cwa-ingest-pull = {
    description = "Periodically pull books from Seafile into CWA ingest";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "1min";
      OnUnitInactiveSec = "60s";
      AccuracySec = "10s";
    };
  };

  # System user that runs the rclone pull. Group `books` is shared with
  # `matv` (CWA's PUID=1000) so CWA can delete files rclone wrote here.
  users.users.cwa-ingest = {
    isSystemUser = true;
    group = "books";
    description = "rclone Seafile → CWA ingest mover";
  };
  users.groups.books = { };
  users.users.matv.extraGroups = [ "books" ];

  systemd.tmpfiles.rules = [
    # Numeric UID/GID — matches container's PUID=1000 (host user `matv`).
    # Hardcoded so a `matv` rename doesn't silently break the container.
    "d /arespool/appdata/cwa            0755 1000 1000 -"
    "d /arespool/appdata/cwa/config     0755 1000 1000 -"
    "d /arespool/appdata/cwa/library    0755 1000 1000 -"
    "d /arespool/appdata/cwa/plugins    0755 1000 1000 -"
    # Setgid 2775 so files rclone writes inherit `books` group → CWA can delete.
    "d /arespool/cwa-ingest             2775 cwa-ingest books -"
  ];

  # See ./CWA_SETUP.md for one-time secrets/Kobo setup.
}
