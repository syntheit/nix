{ lib, ... }:

# Server safety: ways back in when something breaks, and ways for the box to
# recover by itself. Plan: ~/contexts/fleet-resilience.md.
{
  imports = [
    ./rescue.nix
    ./recovery.nix
  ];

  options.services.serverSafety = {
    enable = lib.mkEnableOption "server safety infrastructure (watchdog + rescue SSH)";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Primary user account allowed rescue SSH access";
    };
    recovery.enable = lib.mkEnableOption ''
      self-recovery: reboot after a kernel panic or oops instead of hanging
      forever (headless boxes nobody can power-cycle)
    '';
  };
}
