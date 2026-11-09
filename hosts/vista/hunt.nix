{ lib, pkgs, vars, ... }:
let
  user = vars.user.name;
  repo = "/home/${user}/Projects/hunt";
  tailscaleAddr = "100.96.21.56"; # vista on the syntheit tailnet
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
  # 09:00 rather than earlier: a block found in an evening run keeps its site in a 12 h cooldown past dawn.
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
      TimeoutStartSec = "10h"; # daily.sh has per-step timeouts; this is the backstop so a wedged run frees data/daily.lock
    };
  };
  systemd.timers.hunt-daily = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 09:00:00 America/Argentina/Buenos_Aires";
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
}
