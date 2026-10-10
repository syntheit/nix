# One-week battery/thermal logger. A root daemon takes one short powermetrics
# + battery sample per minute into /var/db/battlog/battlog.sqlite (world
# readable); `battlog report` summarises it. Cost: ~1s powermetrics per minute.
{ pkgs, ... }:
let
  battlog = pkgs.callPackage ../../packages/battlog { };
in
{
  environment.systemPackages = [ battlog ];

  launchd.daemons.battlog = {
    serviceConfig = {
      Label = "io.matv.battlog";
      ProgramArguments = [
        "${battlog}/bin/battlog"
        "collect"
      ];
      StartInterval = 60;
      LowPriorityIO = true;
      Nice = 10;
      ProcessType = "Background";
      StandardErrorPath = "/var/log/battlog.log";
    };
  };
}
