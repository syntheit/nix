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
  deusRuleCount = toString (builtins.length deusRules);
  # Host side: the bind-mounted state dir, and the container's own deus
  # passwd/group entries. NixOS never changes an existing UID or GID
  # (update-users-groups.pl warns "not applying UID change" and keeps the
  # old one), so the manual groupmod/usermod of the migration is the only
  # thing that moves them; declaring 3999 alone leaves them at 999. A
  # container that was never started has no entries yet and gets 3999 from
  # its first activation, so an absent entry counts as 3999.
  #
  # What a start in a half-migrated state actually costs, measured from the
  # container's own tmpfiles rules rather than assumed: SIX rules name deus,
  # one `d` on the state dir and five `f`/`C+` leaves under it. None of them
  # is `Z`, `z`, `R`, `r` or `X`, so nothing recurses and no unrelated owner
  # under the state dir is touched. A start therefore re-owns at most those
  # six inodes (and re-chmods them), which a chown puts straight back, and
  # the three `C+` leaves are force-copied from their source on every start
  # anyway. Nothing is destroyed and nothing is unrecoverable.
  #
  # Against that: the container is Headscale, the VPN control plane for the
  # whole Mac fleet. A refused start is an outage for every Mac, and — since
  # `systemctl restart container@headscale` stops before it starts — a
  # one-way one. So:
  #   start  NEVER refuses. It reports what it found and what a start would
  #          re-own, and exits 0 whatever the state: all 999, all 3999, any
  #          mixture, an absent passwd/group, even an absent state dir.
  #          deus-server's own guard (deusGuard below) is what keeps Deus
  #          down, and it now carries the whole check.
  #   reown  refuses a state a re-own would flip: the entries must be all
  #          999 or all 3999 and already own the state dir and every other
  #          deus tmpfiles path. Refusing here costs nothing — the container
  #          keeps running the generation it is on — so the check stays.
  #   switch is `reown` plus the finished migration (all 3999 and the dir
  #          3999:3999:0700). It gates the activation's reload, which would
  #          otherwise restart a running Deus into that guard.
  #   reload (ExecReload, so a manual `systemctl reload` or `nixos-container
  #          update` too) picks between the two by SYSTEM_PATH, which
  #          /etc/nixos-containers/headscale.conf carries:
  #            - equal to this generation's container: the switch rule. That
  #              is the STEADY-STATE reload, once this generation is both the
  #              running unit and the one named in headscale.conf.
  #            - anything else: the reown rule. An activation's own
  #              `systemctl reload` always lands here, not on the switch
  #              rule: it runs before daemon-reload, so it executes the
  #              OUTGOING generation's ExecReload while headscale.conf
  #              already names the incoming one, and the two paths differ
  #              whenever the container config changed at all. The switch
  #              rule is applied to a switch by the activation gate below,
  #              not by ExecReload. This is also what lets a rollback from
  #              this generation to one before step 4 reload an all-999
  #              container.
  statePreflight = pkgs.writeShellScript "vista-deus-identity-preflight" ''
    set -eu
    mode=''${1:-switch}
    say() { echo "vista-deus-identity-preflight: $*" >&2; }
    fail() { say "$*"; exit 1; }
    # Every finding is reported and counted. Only the modes that gate a
    # re-own turn a count into a refusal; `start` never does.
    problems=0
    note() { say "$*"; problems=$((problems + 1)); }
    fix="Finish or undo the Deus UID ${id} migration so that the container's deus passwd/group entries and ${stateDir} agree: usermod/groupmod the container's deus entries, and re-own the ${legacy}-owned entries under ${stateDir} to match. See the Deus state migration step in docs/vista-mdm-credential-cutover-draft.md."
    case $mode in
      start | reown | switch) ;;
      reload)
        if [ "''${SYSTEM_PATH-}" = ${config.containers.headscale.path} ]; then mode=switch; else mode=reown; fi ;;
      *) fail "unknown mode $mode" ;;
    esac
    entry() {
      file=${containerRoot}/etc/$1
      [ -e "$file" ] || return 0
      ${pkgs.gawk}/bin/awk -F: '$1 == "deus" { print $3 }' "$file"
    }
    u=$(entry passwd)
    g=$(entry group)
    # What the container's activation gives deus. NixOS never changes an
    # existing UID or GID, so only an absent entry gets ${id}.
    eu=''${u:-${id}}
    eg=''${g:-${id}}
    case "$eu:$eg" in
      '${id}:${id}' | '${legacy}:${legacy}') ;;
      *) note "the container's deus user is ''${u:-absent} and its group ''${g:-absent}: a start would give deus $eu:$eg. $fix" ;;
    esac
    # The bind-mounted state dir. Empty `state` means it could not be read,
    # which the switch rule below refuses on its own.
    state=
    if [ -L ${stateDir} ]; then
      note "${stateDir} is a symlink, not the bind-mounted state directory; tmpfiles will not chown through it"
    elif [ ! -d ${stateDir} ]; then
      note "${stateDir} is not a directory"
    elif ! state=$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${stateDir} 2>/dev/null); then
      state=
      note "${stateDir} exists but cannot be stat'ed, so its ownership is unknown"
    elif [ "''${state%:*}" != "$eu:$eg" ]; then
      note "${stateDir} is $state, but a start would re-own it to the container's deus, $eu:$eg. $fix"
    fi
    # The other ${deusRuleCount} paths a container tmpfiles rule gives to deus.
    # Absent, unreadable and symlinked paths are called out rather than
    # skipped in silence: a bare `return 0` here once hid a stat that had
    # lost a race, and `set -eu` turned it into an exit with no reason.
    ownedBy() {
      if [ -L "$1" ]; then
        note "$1 is a symlink: the container's tmpfiles replaces it (C+) or refuses its line (f) rather than chowning its target. $fix"
        return 0
      fi
      if ! o=$(${pkgs.coreutils}/bin/stat -c '%u:%g' "$1" 2>/dev/null); then
        if [ -e "$1" ]; then
          note "$1 exists but cannot be stat'ed, so its ownership is unknown"
        else
          say "$1 does not exist; the container's tmpfiles will create it as $eu:$eg"
        fi
        return 0
      fi
      if { [ "$2" = 1 ] && [ "''${o%:*}" != "$eu" ]; } || { [ "$3" = 1 ] && [ "''${o#*:}" != "$eg" ]; }; then
        note "$1 is $o, but the container's tmpfiles would re-own it to $eu:$eg. $fix"
      fi
    }
    ${ownedChecks}
    if [ "$mode" = start ]; then
      if [ "$problems" != 0 ]; then
        say "starting the container anyway. It carries Headscale, the VPN control plane for the whole Mac fleet, and refusing its start is an outage for every Mac; a start re-owns at most ${stateDir} and the ${deusRuleCount} paths above, which a chown puts back. deus-server's own guard keeps Deus down until the migration is finished."
      elif [ "$eu:$eg" = '${legacy}:${legacy}' ]; then
        say "the container's deus and ${stateDir} are all still ${legacy}: the Deus UID ${id} migration has not been done. Nothing would be re-owned; a step-4 or later container configuration keeps deus-server down until the migration."
      fi
      exit 0
    fi
    [ "$problems" = 0 ] || exit 1
    if [ "$mode" = switch ]; then
      [ "$eu:$eg" = '${id}:${id}' ] \
        || fail "the Deus UID ${id} migration has not been done: the container's deus and ${stateDir} ($state) are still ${legacy}. Finish it first — usermod/groupmod the container's deus entries to ${id}, and re-own ${stateDir} to ${id}:${id} mode 0700 along with the ${legacy}-owned entries under it."
      [ "$state" = '${id}:${id}:700' ] || fail "${stateDir} is ''${state:-unreadable}, not ${id}:${id}:700"
    elif [ "$eu:$eg" = '${legacy}:${legacy}' ]; then
      say "the container's deus and ${stateDir} are all still ${legacy}: the Deus UID ${id} migration has not been done. Going ahead, since nothing would be re-owned; a step-4 or later container configuration keeps deus-server down until the migration."
    fi
  '';
  # Container side, in deus-server itself, as the deus user: Deus refuses to
  # start unless it really runs as 3999:3999 on a 3999:3999:0700 state dir
  # AND owns every other path its own tmpfiles rules name. The container's
  # start no longer refuses a half-migrated state, so this is the ONLY check
  # left, and it must be the whole one — a Deus that cannot read
  # 0600 ${legacy}-owned credentials under its state dir, or cannot write a
  # ${legacy}-owned known_hosts, fails in ways that look like anything but a
  # half-done chown. Refusing here costs Deus only; Headscale keeps running.
  # This holds on every start path (switch, reload, boot, restart, a manual
  # start), not only on a switch.
  deusGuard = pkgs.writeShellScript "deus-identity-guard" ''
    set -eu
    fail() { echo "deus-identity-guard: $*; refusing to start Deus" >&2; exit 1; }
    u=$(${pkgs.coreutils}/bin/id -u deus) || fail "no deus user"
    g=$(${pkgs.coreutils}/bin/id -g deus) || fail "no deus group"
    [ "$u:$g" != '${legacy}:${legacy}' ] \
      || fail "deus is still ${legacy}:${legacy}: the Deus UID ${id} migration has not been done. Finish it — usermod/groupmod the container's deus entries and re-own ${stateDir} — or boot the generation before it"
    [ "$u:$g" = '${id}:${id}' ] || fail "deus is $u:$g, not ${id}:${id}"
    test ! -L ${stateDir} || fail "${stateDir} is a symlink"
    test -d ${stateDir} || fail "${stateDir} is not a directory"
    state=$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${stateDir}) \
      || fail "${stateDir} cannot be stat'ed"
    [ "$state" = '${id}:${id}:700' ] || fail "${stateDir} is $state, not ${id}:${id}:700"
    # Same ${deusRuleCount} paths the host preflight reports on, checked here
    # against the identity Deus actually has. Absent is fine: tmpfiles creates
    # those as deus. Unreadable or symlinked is not, and says so.
    ownedBy() {
      if [ -L "$1" ]; then
        fail "$1 is a symlink, not the file Deus's own tmpfiles rule owns"
      fi
      if ! o=$(${pkgs.coreutils}/bin/stat -c '%u:%g' "$1" 2>/dev/null); then
        [ ! -e "$1" ] || fail "$1 exists but cannot be stat'ed, so Deus cannot prove it owns it"
        return 0
      fi
      if { [ "$2" = 1 ] && [ "''${o%:*}" != "$u" ]; } || { [ "$3" = 1 ] && [ "''${o#*:}" != "$g" ]; }; then
        fail "$1 is $o, not $u:$g: the Deus UID ${id} migration is half-done, and Deus would read or write it as the wrong user"
      fi
    }
    ${ownedChecks}
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
      # passwd/group entries too, which is why the host preflight refuses a
      # RELOAD or a SWITCH unless those entries already own what the rules
      # name. A start is allowed whatever they say: see the preflight's own
      # comment for why six reversible chowns beat a fleet-wide outage.
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
      };    };

    # Fail before a SWITCH can silently re-own the state-dir parent or the
    # other deus tmpfiles paths. (An nspawn boot is allowed to: see the
    # preflight's comment.) This checks only those and the container's deus
    # entries; the approved migration must audit every existing entry under
    # the state dir before setting migrationConfirmed.
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
            echo "NOT reloading container@headscale: vista-deus-identity-preflight failed, so the container keeps its running generation and its running Deus. Fix the Deus UID ${id} state and switch again, or roll back: this generation is already the boot default, and a boot into it starts the container either way — Headscale keeps running, deus-server's guard keeps Deus down until the migration is finished." >&2
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
    # oneshot. It only REPORTS: in start mode the script cannot refuse, and
    # Wants= (not Requires=) means even a crashed or unstartable oneshot
    # cannot fail the container's start job. That ordering is deliberate —
    # `systemctl restart container@headscale` stops the container first, so
    # anything that can refuse the start behind it is a one-way outage for
    # the whole Mac fleet.
    systemd.services.vista-deus-identity-preflight = {
      description = "Deus UID ${id} state report for container@headscale";
      unitConfig.RequiresMountsFor = [ stateDir containerRoot ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${statePreflight} start";
      };
    };
    systemd.services."container@headscale" = {
      wants = [ "vista-deus-identity-preflight.service" ];
      after = [ "vista-deus-identity-preflight.service" ];
      # The same report inside the unit, for a start that skips the oneshot:
      # a restart job (systemd fails only start jobs on a failed dependency)
      # or --job-mode=ignore-dependencies. "-" so that even an unexpected
      # non-zero exit — a bug, a missing binary, a full /run — cannot keep
      # Headscale down.
      serviceConfig.ExecStartPre = lib.mkBefore [ "-${statePreflight} start" ];
      # ExecReload lines run in order and stop at the first failure, so a
      # refusal leaves the container's running generation — and its running
      # Headscale — untouched. Refusing a reload costs no availability,
      # which is why this one still can.
      serviceConfig.ExecReload = lib.mkBefore [ "${statePreflight} reload" ];
    };
  };
}
