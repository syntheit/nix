# Dedicated host/nspawn UID for Deus. OFF by default, and never migrates files.
{ config, lib, pkgs, ... }:
let
  cfg = config.malli.mdm.deusDedicatedIdentity;
  uid = 3999;
  statePreflight = pkgs.writeShellScript "vista-deus-identity-preflight" ''
    set -eu
    test ! -L /var/lib/deus
    test -d /var/lib/deus
    test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' /var/lib/deus)" = '3999:3999:700'
  '';
in
{
  options.malli.mdm.deusDedicatedIdentity = {
    enable = lib.mkEnableOption "dedicated host-visible UID 3999 for nspawn Deus";
    migrationConfirmed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Explicit approval and completed backup/ownership audit of the entire
        Deus bind-mounted state tree. No automatic chown is performed.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.migrationConfirmed;
        message = "Dedicated Deus UID 3999 requires a separately approved backup, ownership migration, and validation of all bind-mounted Deus state.";
      }
      {
        assertion = builtins.elem config.containers.headscale.privateUsers [ "no" "identity" ];
        message = "Dedicated Deus UID 3999 assumes identity host/nspawn UID mapping; re-design for shifted mappings.";
      }
    ];

    users.groups.deus-ddm-bridge.gid = uid;
    users.users.deus-ddm-bridge = {
      isSystemUser = true;
      inherit uid;
      group = "deus-ddm-bridge";
    };
    containers.headscale.config = { ... }: {
      users.groups.deus.gid = uid;
      users.users.deus.uid = uid;
      # The Deus module enforces this on the bind-mounted parent via tmpfiles.
      # The host preflight below must pass *before* it gets that chance.
      services.deus.server.stateDirMode = "0700";
    };

    # Fail before a switch or nspawn boot can silently re-own the state-dir
    # parent. This checks only the parent; the approved migration must audit
    # every existing entry under it before setting migrationConfirmed.
    system.activationScripts.vista-deus-identity-preflight.text = "${statePreflight}";
    systemd.services."container@headscale".serviceConfig.ExecStartPre =
      lib.mkBefore [ "${statePreflight}" ];
  };
}
