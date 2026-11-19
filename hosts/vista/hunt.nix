{ lib, pkgs, vars, ... }:
let
  user = vars.user.name;
  repo = "/home/${user}/Projects/hunt";
  tailscaleAddr = "100.96.21.56"; # vista on the syntheit tailnet

  # hunt events steps: ~/Projects/hunt/scripts/events.sh <step> (see the timers at the end)
  eventsUnit = step: {
    description = "hunt events ${step}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ bash coreutils git nix openssh rsync util-linux gnugrep gnused findutils ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = repo;
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/events.sh ${step}";
      Nice = 10;
      TimeoutStartSec = "3h";
    };
  };
  eventsTimer = times: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = map (t: "*-*-* ${t} America/Argentina/Buenos_Aires") times;
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };
in
{
  # ntfy for hunt alerts (scripts/daily.sh posts to topic `hunt` when a new listing enters the top 10).
  # Tailscale address only; phones subscribe to http://100.96.21.56:2586/hunt over the tailnet.
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = "${tailscaleAddr}:2586";
      base-url = "http://${tailscaleAddr}:2586";
    };
  };
  # Binding the Tailscale address needs tailscale0 up: start after tailscaled and keep retrying until it binds.
  systemd.services.ntfy-sh = {
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = 5;
    };
  };

  # hunt apartments daily pipeline (~/Projects/hunt/scripts/daily.sh): collect → enrich → score → export → raven.
  # The script holds data/daily.lock, so a run still going (e.g. a manual `hunt-run`) makes this one exit.
  # 04:00 (+ up to 20 min), while nobody is working on the box. The 15:00 details window's blocks clear their 12 h
  # cooldown by ~03:40. Persistent: a night with the box off runs it once at the next boot.
  systemd.services.hunt-daily = {
    description = "hunt apartments daily pipeline";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ bash coreutils git nix openssh curl rsync util-linux gnugrep gnused procps findutils ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = repo;
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/daily.sh";
      Nice = 10;
      Slice = "background.slice"; # memory cap (10G, apartments peaked at 6.4G), low CPU/IO weight; see memory.nix
      OOMScoreAdjust = 500; # first victim if the cap is hit
      TimeoutStartSec = "10h"; # daily.sh has per-step timeouts; this is the backstop so a wedged run frees data/daily.lock
    };
  };
  systemd.timers.hunt-daily = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00 America/Argentina/Buenos_Aires";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };

  # Afternoon window: detail pages only (no search pass, no cars), then the same enrich/score/export/rsync tail as the
  # morning run. `daily.sh --details-only` takes the same data/daily.lock (a morning run still going makes this one exit).
  # Per-window caps live in hunt.toml (details_per_run: Zonaprop 750, MercadoLibre 300, Argenprop 0).
  systemd.services.hunt-details = {
    description = "hunt apartments details-only window";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ bash coreutils git nix openssh curl rsync util-linux gnugrep gnused procps findutils ];
    serviceConfig = {
      Type = "oneshot";
      User = user;
      WorkingDirectory = repo;
      ExecStart = "${pkgs.bash}/bin/bash ${repo}/scripts/daily.sh --details-only";
      Nice = 10;
      Slice = "background.slice";
      OOMScoreAdjust = 500;
      TimeoutStartSec = "10h";
    };
  };
  systemd.timers.hunt-details = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 15:00:00 America/Argentina/Buenos_Aires";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };

  # hunt events (Instagram venues → raw posts → events.json on raven), the_construct events-spec.md. Each run pulls
  # Daniel's approved watch list from construct (ssh raven construct api GET /api/events/watch), runs one step, exports
  # data/events/export/events.json and rsyncs it to raven:/var/lib/construct/hunt/. Its own lock (data/events.lock),
  # never touches git (daily.sh updates and gates the checkout). Credentials: /run/secrets/events_meta_* (secrets.nix).
  # Switch: [daily] enabled in src/hunt/hunts/events/hunt.toml. By hand: systemctl start hunt-events-sweep.
  #   sweep  Business Discovery for watched business/creator accounts, 4x a day (~10/14/19/23 ART, jittered)
  #   embed  logged-out profile embed for watched personal accounts, 2x a day
  #   token  debug_token → data-access expiry → construct's "Instagram key expires in N days" at ≤ 14 days
  systemd.services.hunt-events-sweep = eventsUnit "sweep";
  systemd.timers.hunt-events-sweep = eventsTimer [ "09:50:00" "13:50:00" "18:50:00" "22:50:00" ];
  systemd.services.hunt-events-embed = eventsUnit "embed";
  systemd.timers.hunt-events-embed = eventsTimer [ "11:30:00" "20:30:00" ];
  systemd.services.hunt-events-token = eventsUnit "token";
  systemd.timers.hunt-events-token = eventsTimer [ "08:30:00" ];
}
