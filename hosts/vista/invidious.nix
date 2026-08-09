{
  config,
  lib,
  pkgs,
  ...
}:

let
  net = "invidious";
in
{
  # ── Invidious — self-hosted YouTube frontend (the subscriptions feed) ──────
  # What the "browse my channels, watch live, chronological feed" use case
  # actually wants (TubeArchivist is an archive, not a feed). Runs on vista's
  # RESIDENTIAL IP — the thing that makes it work, since YouTube blocks
  # datacenter IPs, not home ones.
  #
  # PRIVATE / tailscale-only ON PURPOSE: a public Invidious gets scraped by
  # strangers, which burns the home IP's quota and gets it flagged — that's what
  # kills instances. Single-user + Tailscale keeps the residential IP clean and
  # avoids proxying video through conduit. Clients (Yattee on iOS, Materialious
  # on the Pixel, or a browser) point at http://<vista-tailscale>:3000 and share
  # one Invidious account so subscriptions sync across devices.
  #
  # Stack = the upstream 3-container compose, translated:
  #   invidious            — Crystal frontend/API on :3000
  #   invidious-companion  — Deno sidecar on :8282; auto-rotates po_token +
  #                          visitor_data (~every 5 min) so playback survives
  #                          YouTube's bot checks. Replaces the old sig-helper.
  #   invidious-db         — postgres 14 (accounts, subscriptions, playlists)
  # The config + secrets are rendered by sops (hosts/vista/secrets.nix); the
  # companion's SERVER_SECRET_KEY must equal invidious_companion_key.

  # docker on an always-on server: start containers at boot. (services/default.nix
  # defaults to socket-activated — right for the laptops, not for a server.)
  # This lived in tubearchivist.nix; moved here when TA was removed.
  virtualisation.docker.enableOnBoot = lib.mkForce true;
  virtualisation.docker.liveRestore = lib.mkForce true;

  # Shared docker network so the containers resolve each other by name.
  systemd.services.docker-invidious-network = {
    description = "Create the invidious docker network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "create-invidious-network" ''
        ${pkgs.docker}/bin/docker network create ${net} || true
      '';
    };
  };

  virtualisation.oci-containers.containers = {
    invidious-db = {
      image = "postgres:14";
      environmentFiles = [ config.sops.templates."invidious-db.env".path ];
      volumes = [ "invidious_pgdata:/var/lib/postgresql/data" ];
      extraOptions = [ "--network=${net}" ];
    };

    invidious-companion = {
      image = "quay.io/invidious/invidious-companion:latest";
      environmentFiles = [ config.sops.templates."invidious-companion.env".path ];
      volumes = [ "invidious_companioncache:/var/tmp/youtubei.js" ];
      extraOptions = [
        "--network=${net}"
        "--read-only"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges:true"
      ];
    };

    invidious = {
      # PINNED to a release — do NOT use :latest. On quay, invidious's :latest
      # tag tracks an old stable release (as of 2026-08 it points at the
      # 2026-06-26 build, HEAD detached at v2.20260626.0), which predates the
      # 2026-07-23 YouTube hotfix (#5818). That old build still sends the
      # blacklisted WEB clientVersion 2.20250222.10.00, so every video 400s
      # ("Youtube API returned status code 400") even though playback via the
      # companion works. 2.20260804.1 contains #5818 (clientVersion
      # 2.20260722.01.00) and is verified 200 against YouTube.
      #
      # YouTube periodically re-blacklists the client version; when watch pages
      # start 400ing again, bump this to the newest quay release tag
      # (https://quay.io/repository/invidious/invidious?tab=tags) and redeploy —
      # `docker run --pull missing` fetches the new tag automatically.
      image = "quay.io/invidious/invidious:2.20260804.1";
      # 0.0.0.0:3000 — reachable over tailscale0/wg0 (both firewall-trusted),
      # while LAN/WAN stay closed. Only tailscale is actually used.
      ports = [ "3000:3000" ];
      # Full config (incl. secrets) comes from the sops-rendered file.
      volumes = [
        "${config.sops.templates."invidious.yml".path}:/invidious/config/config.yml:ro"
      ];
      dependsOn = [
        "invidious-db"
        "invidious-companion"
      ];
      extraOptions = [ "--network=${net}" ];
    };
  };

  # Ordering: wait for the network + sops-rendered config/secrets.
  systemd.services.docker-invidious-db = {
    after = [
      "docker-invidious-network.service"
      "sops-nix.service"
    ];
    requires = [ "docker-invidious-network.service" ];
  };
  systemd.services.docker-invidious-companion = {
    after = [
      "docker-invidious-network.service"
      "sops-nix.service"
    ];
    requires = [ "docker-invidious-network.service" ];
  };
  systemd.services.docker-invidious = {
    after = [
      "docker-invidious-network.service"
      "sops-nix.service"
    ];
    requires = [ "docker-invidious-network.service" ];
  };

  # Invidious + companion accumulate memory and stale sessions; upstream says to
  # restart at least daily. Bounce both every 6h.
  systemd.services.invidious-restart = {
    description = "Periodic restart of Invidious + companion (memory/session hygiene)";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "invidious-restart" ''
        ${pkgs.docker}/bin/docker restart invidious invidious-companion || true
      '';
    };
  };
  systemd.timers.invidious-restart = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 00/6:00:00";
      Persistent = true;
      RandomizedDelaySec = "5m";
    };
  };
}
