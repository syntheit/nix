# Dedicated host/nspawn UID for Deus. OFF by default, and never migrates files.
{ config, lib, pkgs, ... }:
let
  cfg = config.malli.mdm.deusDedicatedIdentity;
  uid = 3999;
  id = toString uid;
  # The container's deus user and group before the migration (runbook step 4
  # preconditions: `c id -u deus; c id -g deus` → 999, 999).
  legacy = "999";
  stateDir = "/var/lib/deus";
  # Declarative, non-ephemeral container root (stateVersion >= 22.05); both
  # asserted below.
  containerRoot = "/var/lib/nixos-containers/headscale";
  inner = config.containers.headscale.config;
  # Every other path a container tmpfiles rule gives to deus. tmpfiles
  # resolves "deus" through the container's own passwd/group on each run and
  # re-owns an existing path to it (d, f, C+ alike), so these must already
  # be owned by whatever those entries say.
  fields = rule: lib.filter (f: f != "")
    (lib.splitString " " (builtins.replaceStrings [ "\t" ] [ " " ] rule));
  deusRules = lib.filter (r: r.path != stateDir && (r.user == "deus" || r.group == "deus"))
    (map (rule: let f = fields rule; at = n: if builtins.length f > n then builtins.elemAt f n else "-"; in
      { path = at 1; user = at 3; group = at 4; }) inner.systemd.tmpfiles.rules
    ++ lib.concatLists (lib.mapAttrsToList (_: paths: lib.concatLists (lib.mapAttrsToList (path: types:
      map (t: { inherit path; user = t.user or "-"; group = t.group or "-"; }) (lib.attrValues types))
      paths)) inner.systemd.tmpfiles.settings));
  flag = b: if b then "1" else "0";
  ownedChecks = lib.concatMapStrings (r: ''
    ownedBy ${lib.escapeShellArg r.path} ${flag (r.user == "deus")} ${flag (r.group == "deus")}
  '') deusRules;
  # Host side: the bind-mounted state dir, and the container's own deus
  # passwd/group entries. NixOS never changes an existing UID or GID
  # (update-users-groups.pl warns "not applying UID change" and keeps the
  # old one), so the manual groupmod/usermod of the migration is the only
  # thing that moves them; declaring 3999 alone leaves them at 999. A
  # container that was never started has no entries yet and gets 3999 from
  # its first activation, so an absent entry counts as 3999.
  #
  # With createHome off, a container start (or reload) re-owns Deus's state
  # only through tmpfiles, and only to those entries. So:
  #   start  refuses only a state it would re-own: the entries must be all
  #          999 or all 3999 and already own the state dir and every other
  #          deus tmpfiles path. All 999 (nothing migrated) starts: Headscale
  #          runs, and deus-server's own guard keeps Deus down.
  #   switch additionally requires the finished migration (all 3999 and the
  #          dir 3999:3999:0700). It gates the activation's reload, which
  #          would otherwise restart a running Deus into that guard.
  #   reload (ExecReload, so a manual `systemctl reload` or `nixos-container
  #          update` too) holds a reload into this generation's container
  #          to the switch rule, and one into any other generation's
  #          container to the start rule. During a switch the activation's
  #          `systemctl reload` runs before daemon-reload, so it still runs
  #          the ExecReload of the generation being left, with the new
  #          generation's SYSTEM_PATH: a rollback from this generation to
  #          one before step 4 must still reload an all-999 container.
  statePreflight = pkgs.writeShellScript "vista-deus-identity-preflight" ''
    set -eu
    mode=''${1:-switch}
    fail() { echo "vista-deus-identity-preflight: $*" >&2; exit 1; }
    fix="Finish runbook step 4 (commands 8 and 8a) or its Undo, so that the container's deus user and group and ${stateDir} are all ${legacy} or all ${id}."
    case $mode in
      start | switch) ;;
      reload)
        if [ "''${SYSTEM_PATH-}" = ${config.containers.headscale.path} ]; then mode=switch; else mode=start; fi ;;
      *) fail "unknown mode $mode" ;;
    esac
    test ! -L ${stateDir} || fail "${stateDir} is a symlink"
    test -d ${stateDir} || fail "${stateDir} is not a directory"
    state=$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${stateDir})
    entry() {
      file=${containerRoot}/etc/$1
      [ -e "$file" ] || return 0
      ${pkgs.gawk}/bin/awk -F: '$1 == "deus" { print $3 }' "$file"
    }
    u=$(entry passwd)
    g=$(entry group)
    # What the container's activation gives deus.
    eu=''${u:-${id}}
    eg=''${g:-${id}}
    case "$eu:$eg" in
      '${id}:${id}' | '${legacy}:${legacy}') ;;
      *) fail "the container's deus user is ''${u:-absent} and its group ''${g:-absent}: a start would give deus $eu:$eg. $fix" ;;
    esac
    [ "''${state%:*}" = "$eu:$eg" ] \
      || fail "${stateDir} is $state, but a start would re-own it to the container's deus, $eu:$eg. $fix"
    ownedBy() {
      [ -e "$1" ] && [ ! -L "$1" ] || return 0
      o=$(${pkgs.coreutils}/bin/stat -c '%u:%g' "$1")
      if [ "$2" = 1 ] && [ "''${o%:*}" != "$eu" ] || { [ "$3" = 1 ] && [ "''${o#*:}" != "$eg" ]; }; then
        fail "$1 is $o, but the container's tmpfiles would re-own it to $eu:$eg. $fix"
      fi
    }
    ${ownedChecks}
    if [ "$mode" = switch ]; then
      [ "$eu:$eg" = '${id}:${id}' ] \
        || fail "the Deus UID ${id} migration has not been done: the container's deus and ${stateDir} ($state) are still ${legacy}. Do runbook step 4 commands 5-9 first."
      [ "$state" = '${id}:${id}:700' ] || fail "${stateDir} is $state, not ${id}:${id}:700"
    elif [ "$eu:$eg" = '${legacy}:${legacy}' ]; then
      echo "vista-deus-identity-preflight: the container's deus and ${stateDir} are all still ${legacy}: the Deus UID ${id} migration has not been done. Going ahead, since nothing would be re-owned; a step-4 or later container configuration keeps deus-server down until the migration." >&2
    fi
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
    [ "$u:$g" != '${legacy}:${legacy}' ] \
      || fail "deus is still ${legacy}:${legacy}: the Deus UID ${id} migration (runbook step 4) has not been done. Do it, or boot the generation before step 4"
    [ "$u:$g" = '${id}:${id}' ] || fail "deus is $u:$g, not ${id}:${id}"
    test ! -L ${stateDir} || fail "${stateDir} is a symlink"
    test -d ${stateDir} || fail "${stateDir} is not a directory"
    state=$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${stateDir})
    [ "$state" = '${id}:${id}:700' ] || fail "${stateDir} is $state, not ${id}:${id}:700"
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
      # activation. The directory is the bind mount and always exists, so
      # nothing needs creating, and the Deus module's tmpfiles rule keeps
      # its mode. That rule (and the other "deus"-owned ones) re-owns to the
      # passwd/group entries too, which is why the host preflight below
      # refuses to start or reload the container unless those entries
      # already own what the rules name.
      users.users.deus.createHome = lib.mkForce false;
      # The Deus module enforces this on the bind-mounted parent via tmpfiles.
      services.deus.server.stateDirMode = "0700";
      systemd.services.deus-server = {
        serviceConfig = {
          ExecStartPre = lib.mkBefore [ "${deusGuard}" ];
          # Deus never gives up: a crash loop, such as a transient failure at
          # boot, retries for as long as it lasts instead of parking Deus in
          # "failed". The Deus module's Restart=always and RestartSec=5s stay;
          # each automatic restart waits about 1.5 times longer than the one
          # before, from 5 s up to 5 min over ten steps (about 10 min in
          # all), then every 5 min. A guard refusal repeats on that schedule:
          # noisy, and Deus stays down. systemd resets the step count only on
          # a start it did not queue itself (a manual start or restart, or a
          # switch that restarts Deus), so ten crashes without one leave
          # every later crash at 5 min.
          RestartSteps = 10;
          RestartMaxDelaySec = "5min";
        };
        # No start limit: 0 turns rate limiting off, so no number of
        # restarts ends in start-limit-hit.
        startLimitIntervalSec = 0;
      };
    };

    # Fail before a switch or nspawn boot can silently re-own the state-dir
    # parent or the other deus tmpfiles paths. This checks only those and the
    # container's deus entries; the approved migration must audit every
    # existing entry under the state dir before setting migrationConfirmed.
    #
    # A failed activation snippet does NOT stop the switch: NixOS records the
    # failure and runs every later snippet, including the container reload,
    # whose container activation (users, tmpfiles) would then re-own the
    # state and restart Deus. So the preflight runs before the reload, and
    # the reload is skipped unless it passed: the container keeps its running
    # generation until a switch with a passing preflight.
    system.activationScripts.vista-deus-identity-preflight.text = ''
      ${statePreflight} switch
      vistaDeusIdentityPreflight=$?
    '';
    system.activationScripts.reload-headscale-container = {
      deps = [ "vista-deus-identity-preflight" ];
      text = lib.mkMerge [
        (lib.mkBefore ''
          if [ "''${vistaDeusIdentityPreflight:-1}" != 0 ]; then
            echo "NOT reloading container@headscale: vista-deus-identity-preflight failed, so the container keeps its running generation. Fix the Deus UID ${id} state and switch again, or roll back: this generation is already the boot default, and a boot into it keeps Deus down (all ${legacy}: the container starts, deus-server refuses) or the whole container down (a mixed state)." >&2
          else
            :
        '')
        (lib.mkAfter ''
          fi
        '')
      ];
    };

    # Every start job of the container (boot, systemctl start, nixos-container
    # start, and each retry its Restart=on-failure queues) first runs this
    # oneshot. A refusal fails it once, with its reason, and the container's
    # start job fails as a dependency before nspawn runs: no 100 ms retry
    # loop into start-limit-hit, and the container, never started, is not
    # restarted. RefuseManualStop, because Requires= would carry a manual
    # stop or restart of this unit over to the container.
    systemd.services.vista-deus-identity-preflight = {
      description = "Deus UID ${id} preflight for container@headscale";
      unitConfig = {
        RequiresMountsFor = [ stateDir containerRoot ];
        RefuseManualStop = true;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${statePreflight} start";
      };
    };
    systemd.services."container@headscale" = {
      requires = [ "vista-deus-identity-preflight.service" ];
      after = [ "vista-deus-identity-preflight.service" ];
      # The same check inside the unit, for a start that skips the oneshot:
      # a restart job (systemd fails only start jobs on a failed Requires=)
      # or --job-mode=ignore-dependencies. After a refusal here, the retry
      # Restart= queues is a start job, and the oneshot ends it.
      serviceConfig.ExecStartPre = lib.mkBefore [ "${statePreflight} start" ];
      # ExecReload lines run in order and stop at the first failure, so a
      # refusal leaves the container's running generation untouched.
      serviceConfig.ExecReload = lib.mkBefore [ "${statePreflight} reload" ];
    };
  };
}
