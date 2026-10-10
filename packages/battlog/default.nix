# One-week battery/thermal logger: `battlog collect` runs from a root launchd
# daemon (modules/darwin/battlog.nix), the other subcommands read the DB.
{ writers }:
writers.writePython3Bin "battlog" {
  flakeIgnore = [
    "E"
    "W"
  ];
} (builtins.readFile ./battlog.py)
