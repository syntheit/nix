{ config, lib, ... }:

# CPU energy/performance preference (EPP) for intel_pstate / amd-pstate-epp in
# active mode. EPP only applies under the powersave governor ("performance"
# pins it to performance); powersave still boosts on demand, EPP sets how
# eagerly. powersave + balance_performance is the kernel's own default.
# Measured on mantle (3700X): ~7 W less package power at light desktop load.
# Published benchmarks show ~0-1% throughput difference.
let
  epp = config.powerManagement.energyPerformancePreference;
in
{
  options.powerManagement.energyPerformancePreference = lib.mkOption {
    type = lib.types.nullOr (
      lib.types.enum [
        "default"
        "performance"
        "balance_performance"
        "balance_power"
        "power"
      ]
    );
    default = null;
    description = "EPP hint written to every CPU at boot. null leaves it alone.";
  };

  config = lib.mkIf (epp != null) {
    powerManagement.cpuFreqGovernor = lib.mkDefault "powersave";
    systemd.services.cpu-epp = {
      description = "Set CPU energy/performance preference";
      after = [ "cpufreq.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
          echo ${epp} > "$f"
        done
      '';
    };
  };
}
