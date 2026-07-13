{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Shared docker network so the stack's containers resolve each other by name
  # (archivist-es, archivist-redis) exactly as the upstream compose expects.
  net = "tubearchivist";
in
{
  # ── TubeArchivist — isolated, self-hosted YouTube media server ─────────────
  # Deliberately SEPARATE from harbor's Jellyfin: this box subscribes to a
  # handful of channels, downloads a rolling window of their uploads with
  # yt-dlp, and serves them from its OWN web UI/player — a finite, de-algorithmed
  # library with no search-all-of-YouTube surface to rabbit-hole into.
  #
  # Why HERE (vista) and not conduit: YouTube blocks datacenter/VPS IPs. vista is
  # on a residential home IP, so the download side must run here. conduit is only
  # a dumb inbound TLS reverse-proxy (yt.matv.io → Caddy → WireGuard → here), so
  # YouTube only ever sees vista's residential IP — never the NY VPS.

  # ── docker: start the stack at boot ───────────────────────────────────────
  # services/default.nix sets enableOnBoot=false (socket-activated — correct for
  # the laptops). vista is an always-on server, so the stack must come up on boot
  # without someone poking the docker socket. mkForce overrides the shared default.
  virtualisation.docker.enableOnBoot = lib.mkForce true;
  virtualisation.docker.liveRestore = lib.mkForce true;

  # ── Elasticsearch kernel requirement ──────────────────────────────────────
  # ES mmaps its indices and refuses to start below vm.max_map_count=262144.
  # (vista currently reads far higher, but pin it so a future kernel-default
  # change can't silently break ES.)
  boot.kernel.sysctl."vm.max_map_count" = 262144;

  # ── Storage layout ────────────────────────────────────────────────────────
  # Downloaded videos are large and CHURN (rolling-window retention deletes old
  # ones). Put them on a dedicated btrfs subvolume: a nested subvolume is
  # excluded from the parent (@) snapshot, so btrbk's daily 7d/4w snapshots can't
  # pin deleted videos for weeks and blow up disk usage. Owned by uid 1000 to
  # match the container's HOST_UID. ES index / thumbnail cache / redis are small,
  # so they stay as docker-managed named volumes (simpler permissions).
  systemd.tmpfiles.rules = [
    "v /var/lib/tubearchivist       0750 root root -"
    "d /var/lib/tubearchivist/media 0750 1000 1000 -"
  ];

  # ── Firewall ──────────────────────────────────────────────────────────────
  # wg0 is the tunnel to conduit; tailscale0 is already trusted (default.nix).
  # The TA container binds 0.0.0.0:8055 but the LAN/WAN interface stays
  # firewalled, so :8055 is reachable ONLY via the tunnel (conduit) or tailscale
  # (local). trustedInterfaces is a merged list, so this adds to the existing one.
  networking.firewall.trustedInterfaces = [ "wg0" ];

  # ── WireGuard tunnel to conduit (mirrors harbor's wg0) ────────────────────
  # vista dials OUT to conduit; conduit has no endpoint for us. 10.100.0.4 is
  # vista's tunnel address (harbor=.2, mantle=.3). The private key is placed
  # manually at /etc/wireguard/wg0-private.key (out of this public repo) — the
  # same approach conduit uses for its own key; sops later. The matching PUBLIC
  # key is registered as a peer in hosts/conduit/default.nix.
  networking.wg-quick.interfaces.wg0 = {
    address = [ "10.100.0.4/24" ];
    privateKeyFile = "/etc/wireguard/wg0-private.key";
    peers = [
      {
        publicKey = "bhXOmLJsZDR0ZeF/Wnzt116Jw0tHzbfhoe2kG2+ZDAw="; # conduit
        endpoint = "192.3.203.146:51820";
        allowedIPs = [ "10.100.0.1/32" ];
        persistentKeepalive = 25;
      }
    ];
  };

  # ── Create the shared docker network before the containers start ──────────
  systemd.services.docker-tubearchivist-network = {
    description = "Create the tubearchivist docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "create-ta-network" ''
        ${pkgs.docker}/bin/docker network create ${net} || true
      '';
    };
  };

  # ── The TubeArchivist stack (upstream 3-container compose, translated) ─────
  # Secrets (TA_USERNAME / TA_PASSWORD / ELASTIC_PASSWORD) come from a sops
  # template (hosts/vista/secrets.nix) rendered to a runtime path — never in the
  # nix store or this public repo. ELASTIC_PASSWORD must match between the app
  # and es containers, so both read the same rendered file.
  virtualisation.oci-containers.containers = {
    archivist-es = {
      image = "bbilly1/tubearchivist-es"; # ES 8, amd64
      environment = {
        "ES_JAVA_OPTS" = "-Xms1g -Xmx1g";
        "xpack.security.enabled" = "true";
        "discovery.type" = "single-node";
        "path.repo" = "/usr/share/elasticsearch/data/snapshot";
      };
      environmentFiles = [ config.sops.templates."tubearchivist.env".path ]; # ELASTIC_PASSWORD
      volumes = [ "ta_es:/usr/share/elasticsearch/data" ];
      extraOptions = [
        "--network=${net}"
        "--ulimit=memlock=-1:-1"
      ];
    };

    archivist-redis = {
      image = "redis";
      volumes = [ "ta_redis:/data" ];
      dependsOn = [ "archivist-es" ];
      extraOptions = [ "--network=${net}" ];
    };

    tubearchivist = {
      image = "bbilly1/tubearchivist";
      ports = [ "8055:8000" ]; # host 8055 → container 8000 (host :8000 is taken by another local service)
      volumes = [
        "/var/lib/tubearchivist/media:/youtube"
        "ta_cache:/cache"
      ];
      environment = {
        "ES_URL" = "http://archivist-es:9200";
        "REDIS_CON" = "redis://archivist-redis:6379";
        "HOST_UID" = "1000";
        "HOST_GID" = "1000";
        "TZ" = "America/New_York";
        # Allowed hosts + CSRF origins. Public origin is https (conduit's Caddy
        # terminates TLS); the wg + tailscale IPs allow direct access on :8055.
        # A wrong/missing value here surfaces as HTTP 400 Bad Request.
        "TA_HOST" = "https://yt.matv.io http://vista:8055 http://100.96.21.56:8055 http://10.100.0.4:8055";
      };
      environmentFiles = [ config.sops.templates."tubearchivist.env".path ]; # TA_USERNAME/PASSWORD + ELASTIC_PASSWORD
      dependsOn = [
        "archivist-es"
        "archivist-redis"
      ];
      extraOptions = [ "--network=${net}" ];
    };

    # ── Optional: PO-token provider (uncomment if downloads hit 403 / "bot") ──
    # vista's residential IP usually satisfies YouTube without this, but if
    # downloads start failing with 403 / "Sign in to confirm you're not a bot",
    # enable a PO-token provider and turn it on in TA → Settings → Application.
    # IMPORTANT: pin this image to the version TA bundles (see the TA container's
    # backend/requirements.plugins.txt) or you'll get compatibility errors.
    #
    # bgutil-provider = {
    #   image = "brainicism/bgutil-ytdlp-pot-provider:<match-TA-version>";
    #   extraOptions = [ "--network=${net}" ];
    # };
  };

  # Container ordering: wait for the shared network to exist, and for sops to
  # have rendered the env file the app + es read (ELASTIC_PASSWORD etc.).
  systemd.services.docker-archivist-es = {
    after = [
      "docker-tubearchivist-network.service"
      "sops-nix.service"
    ];
    requires = [ "docker-tubearchivist-network.service" ];
  };
  systemd.services.docker-archivist-redis.after = [ "docker-tubearchivist-network.service" ];
  systemd.services.docker-tubearchivist.after = [
    "docker-tubearchivist-network.service"
    "sops-nix.service"
  ];
}
