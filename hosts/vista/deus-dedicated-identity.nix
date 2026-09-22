# Dedicated host/nspawn UID for Deus. OFF by default, and never migrates files.
{ config, lib, pkgs, ... }:
let
  cfg = config.malli.mdm.deusDedicatedIdentity;
  uid = 3999;
  id = toString uid;
  # Declarative, non-ephemeral container root (stateVersion >= 22.05); both
  # asserted below.
  containerRoot = "/var/lib/nixos-containers/headscale";
  # Host side: the bind-mounted state dir, and the container's own deus
  # passwd/group entries. NixOS never changes an existing UID or GID
  # (update-users-groups.pl warns "not applying UID change" and keeps the
  # old one), so the manual groupmod/usermod of the migration is the only
  # thing that moves them; declaring 3999 alone leaves them at 999. A
  # container that was never started has no entries yet and gets 3999 from
  # its first activation, so an absent entry passes.
  statePreflight = pkgs.writeShellScript "vista-deus-identity-preflight" ''
    set -eu
    fail() { echo "vista-deus-identity-preflight: $*" >&2; exit 1; }
    test ! -L /var/lib/deus || fail "/var/lib/deus is a symlink"
    test -d /var/lib/deus || fail "/var/lib/deus is not a directory"
    state=$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' /var/lib/deus)
    [ "$state" = '${id}:${id}:700' ] || fail "/var/lib/deus is $state, not ${id}:${id}:700"
    for db in passwd group; do
      file=${containerRoot}/etc/$db
      [ -e "$file" ] || continue
      entry=$(${pkgs.gawk}/bin/awk -F: '$1 == "deus" { print $3 }' "$file")
      [ -z "$entry" ] || [ "$entry" = '${id}' ] \
        || fail "the container's deus $db entry is $entry, not ${id}: groupmod/usermod it first"
    done
  '';
  # Container side, in deus-server itself, as the deus user: Deus refuses to
  # start unless it really runs as 3999:3999 on a 3999:3999:0700 state dir.
  # This holds on every start path (switch, reload, boot, restart, a manual
  # start), not only on a switch.
  deusGuard = pkgs.writeShellScript "deus-identity-guard" ''
    set -eu
    fail() { echo "deus-identity-guard: $*; refusing to start Deus" >&2; exit 1; }
    u=$(${pkgs.coreutils}/bin/id -u deus) || fail "no deus user"
    g=$(${pkgs.coreutils}/bin/id -g deus) || fail "no deus group"
    [ "$u:$g" = '${id}:${id}' ] || fail "deus is $u:$g, not ${id}:${id}"
    test ! -L /var/lib/deus || fail "/var/lib/deus is a symlink"
    test -d /var/lib/deus || fail "/var/lib/deus is not a directory"
    state=$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' /var/lib/deus)
    [ "$state" = '${id}:${id}:700' ] || fail "/var/lib/deus is $state, not ${id}:${id}:700"
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
      {
        assertion = !config.containers.headscale.ephemeral
          && lib.versionAtLeast config.system.stateVersion "22.05";
        message = "The Deus UID 3999 preflight reads the headscale container's passwd/group under ${containerRoot}; an ephemeral or pre-22.05 container keeps its root elsewhere.";
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
      # The Deus module sets createHome, and update-users-groups.pl then
      # chowns and chmods the home (/var/lib/deus, the bind mount) to
      # whatever UID/GID the container's passwd still holds on EVERY
      # activation: with the usermod skipped, straight back to 999 (host
      # btrbk). The directory is the bind mount and always exists, so
      # nothing needs creating, and the Deus module's tmpfiles rule keeps
      # its mode. That tmpfiles rule (and the other "deus"-owned ones) would
      # re-own to 999 too, which is why the container never activates while
      # its passwd says 999: the host preflight gates both the reload below
      # and container@headscale's start.
      users.users.deus.createHome = lib.mkForce false;
      # The Deus module enforces this on the bind-mounted parent via tmpfiles.
      # The host preflight below must pass *before* it gets that chance.
      services.deus.server.stateDirMode = "0700";
      systemd.services.deus-server.serviceConfig.ExecStartPre =
        lib.mkBefore [ "${deusGuard}" ];
    };

    # Fail before a switch or nspawn boot can silently re-own the state-dir
    # parent. This checks only the parent and the container's deus entries;
    # the approved migration must audit every existing entry under it before
    # setting migrationConfirmed.
    #
    # A failed activation snippet does NOT stop the switch: NixOS records the
    # failure and runs every later snippet, including the container reload,
    # whose container activation (users, tmpfiles) would then re-own the
    # state and restart Deus. So the preflight runs before the reload, and
    # the reload is skipped unless it passed: the container keeps its running
    # generation until a switch with a passing preflight.
    system.activationScripts.vista-deus-identity-preflight.text = ''
      ${statePreflight}
      vistaDeusIdentityPreflight=$?
    '';
    system.activationScripts.reload-headscale-container = {
      deps = [ "vista-deus-identity-preflight" ];
      text = lib.mkMerge [
        (lib.mkBefore ''
          if [ "''${vistaDeusIdentityPreflight:-1}" != 0 ]; then
            echo "NOT reloading container@headscale: vista-deus-identity-preflight failed. The container keeps its running generation; fix the Deus UID ${id} state, then switch again." >&2
          else
            :
        '')
        (lib.mkAfter ''
          fi
        '')
      ];
    };
    systemd.services."container@headscale".serviceConfig.ExecStartPre =
      lib.mkBefore [ "${statePreflight}" ];
  };
}
