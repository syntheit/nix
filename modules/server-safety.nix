{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.serverSafety;
in
{
  options.services.serverSafety = {
    enable = lib.mkEnableOption "server safety infrastructure (watchdog + rescue SSH)";
    user = lib.mkOption {
      type = lib.types.str;
      description = "Primary user account allowed rescue SSH access";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      # Dead man's switch — arm before risky rebuilds, disarm after verifying access
      (pkgs.writeShellScriptBin "arm-watchdog" ''
        mkdir -p /var/lib/nixos-watchdog
        readlink /run/current-system > /var/lib/nixos-watchdog/rollback-target
        echo "Saved rollback target: $(cat /var/lib/nixos-watchdog/rollback-target)"
        systemctl start nixos-watchdog.timer
        echo "Watchdog armed. You have 10 minutes to disarm with: sudo disarm-watchdog"
      '')
      (pkgs.writeShellScriptBin "disarm-watchdog" ''
        systemctl stop nixos-watchdog.timer
        systemctl stop nixos-watchdog.service 2>/dev/null || true
        rm -f /var/lib/nixos-watchdog/rollback-target
        echo "Watchdog disarmed. Config is permanent."
      '')
    ];

    # Dead man's switch — rolls back to saved generation if not disarmed
    systemd.services.nixos-watchdog = {
      description = "Dead man's switch - rolls back to saved generation";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "watchdog-rollback" ''
          if [ -f /var/lib/nixos-watchdog/rollback-target ]; then
            TARGET=$(cat /var/lib/nixos-watchdog/rollback-target)
            echo "Watchdog triggered! Rolling back to: $TARGET"
            nix-env -p /nix/var/nix/profiles/system --set "$TARGET"
            "$TARGET/bin/switch-to-configuration" switch
            rm -f /var/lib/nixos-watchdog/rollback-target
          else
            echo "No rollback target found, rebooting as fallback"
            systemctl reboot
          fi
        '';
      };
    };

    systemd.timers.nixos-watchdog = {
      description = "Dead man's switch timer (10 min)";
      timerConfig = {
        OnActiveSec = "10min";
        Unit = "nixos-watchdog.service";
        RemainAfterElapse = false;
      };
    };

    # Rescue SSH — independent of services.openssh, reachable over Tailscale on port 64830.
    # If main sshd or tunnel breaks, this still works.
    systemd.services.sshd-rescue = {
      description = "Rescue SSH daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      restartIfChanged = false;
      serviceConfig = {
        ExecStart = "${pkgs.openssh}/bin/sshd -D -f /etc/ssh/sshd_rescue_config";
        Restart = "always";
        RestartSec = "5s";
      };
    };

    environment.etc."ssh/sshd_rescue_config".text = ''
      Port 64830
      PidFile /run/sshd-rescue.pid
      HostKey /etc/ssh/ssh_host_ed25519_key
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u
      AllowUsers ${cfg.user}
      StrictModes yes
    '';
  };
}
