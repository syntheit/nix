{ config, lib, ... }:

# Self-recovery for remote headless boxes: a hang nobody can power-cycle is
# worse than a reboot.
let
  cfg = config.services.serverSafety;
in
{
  config = lib.mkIf (cfg.enable && cfg.recovery.enable) {
    boot.kernel.sysctl = {
      "kernel.panic" = 10; # reboot 10s after a panic (default 0 = hang forever)
      "kernel.panic_on_oops" = 1; # don't limp on in a corrupted state
    };
  };
}
