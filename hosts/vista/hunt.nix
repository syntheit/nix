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
      TimeoutStartSec = "infinity";
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
}
