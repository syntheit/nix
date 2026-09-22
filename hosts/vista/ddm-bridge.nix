# Dormant, single-purpose NanoMDM network-namespace to Deus DDM Unix bridge.
# No live container, UID change, socket mount, or DDM command exists by default.
{ config, pkgs, lib, ... }:
let
  cfg = config.malli.mdm.ddmBridge;
  bridgeUID = 3999;
  bridgeID = toString bridgeUID;
  stateDir = "/var/lib/deus";
  privateDir = "${stateDir}/ddm-private";
  socketPath = "${privateDir}/socket";
  bridgeText = builtins.readFile ../../packages/nanomdm-ddm-bridge.py;
  bridgeTag = "1.0.0-${builtins.substring 0 12 (builtins.hashString "sha256" bridgeText)}";
  nanomdmVersion = import ../../packages/nanomdm-patched/version.nix;
  reviewedCoordinates = pin: { inherit (pin) deusRev nanomdmCommit hash; };
  # A directory, not a bare file: dockerTools rsyncs every copyToRoot entry as
  # "<entry>/" into the image root, and a single writeText file fails that
  # with "Not a directory".
  bridgeSource = pkgs.writeTextDir "nanomdm-ddm-bridge.py" bridgeText;
  bridgeImage = pkgs.dockerTools.buildImage {
    name = "malli-deus-ddm-bridge";
    tag = bridgeTag;
    copyToRoot = [ pkgs.python3 bridgeSource ];
    config = {
      Entrypoint = [ "${pkgs.python3}/bin/python3" "${bridgeSource}/nanomdm-ddm-bridge.py" ];
      Env = [ "PYTHONDONTWRITEBYTECODE=1" ];
      User = "${bridgeID}:${bridgeID}";
    };
  };
  # Pass/fail probes of the private socket. They connect and close; nothing
  # is ever sent, so no request, key or enrollment ID crosses the socket.
  #   wait PATH SECONDS  exit 0 once PATH is a socket (never a symlink) that
  #                      accepts a connection; 1 if none did in SECONDS.
  #   clear-stale PATH   unlink PATH only if it is a socket owned by this UID
  #                      whose connect is refused (ECONNREFUSED: no listener
  #                      holds it), and only if it is still that same inode.
  #                      A live listener, anything that is not such a socket,
  #                      or any other connect result is left alone. Exit 0.
  socketProbe = pkgs.writeText "deus-ddm-socket-probe.py" ''
    import errno, os, socket, stat, sys, time

    def refused(path):
        # None when a listener accepted the connection, else the OSError.
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(2)
        try:
            s.connect(path)
            return None
        except OSError as e:
            return e
        finally:
            s.close()

    def lstat_socket(path):
        try:
            st = os.lstat(path)
        except FileNotFoundError:
            return None
        return st if stat.S_ISSOCK(st.st_mode) else False

    mode, path = sys.argv[1], sys.argv[2]
    if mode == "wait":
        limit = int(sys.argv[3])
        deadline = time.monotonic() + limit
        while True:
            if lstat_socket(path) and refused(path) is None:
                sys.exit(0)
            if time.monotonic() >= deadline:
                print(f"{path}: no listener accepted a connection within {limit}s", file=sys.stderr)
                sys.exit(1)
            time.sleep(2)
    elif mode == "clear-stale":
        st = lstat_socket(path)
        if st is None:
            sys.exit(0)
        if st is False or st.st_uid != os.geteuid():
            print(f"{path}: not a socket owned by this UID; left in place", file=sys.stderr)
            sys.exit(0)
        err = refused(path)
        if err is None:
            print(f"{path}: a listener is live on it; left in place", file=sys.stderr)
        elif err.errno != errno.ECONNREFUSED:
            print(f"{path}: not proven stale ({err.strerror}); left in place", file=sys.stderr)
        else:
            again = lstat_socket(path)
            if again and (again.st_dev, again.st_ino) == (st.st_dev, st.st_ino):
                os.unlink(path)
                print(f"{path}: removed a stale socket (connect refused, no listener)", file=sys.stderr)
        sys.exit(0)
    else:
        sys.exit(f"usage: {sys.argv[0]} wait PATH SECONDS | clear-stale PATH")
  '';
  statePreflight = pkgs.writeShellScript "deus-ddm-state-preflight" ''
    set -eu
    test ! -L ${stateDir}
    test -d ${stateDir}
    test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${stateDir})" = '${bridgeID}:${bridgeID}:700'
  '';
  bridgePreflight = pkgs.writeShellScript "deus-ddm-bridge-preflight" ''
    set -eu
    ${statePreflight}
    test ! -L ${privateDir}
    test -d ${privateDir}
    test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${privateDir})" = '${bridgeID}:${bridgeID}:700'
    # A socket file is not a listener: after an unclean Deus exit the file
    # stays and nothing accepts on it. Require one that accepts a connection.
    # (Run as root, which Deus's SO_PEERCRED check closes silently.)
    ${pkgs.python3}/bin/python3 ${socketProbe} wait ${socketPath} 0
    test ! -L ${socketPath}
    test -S ${socketPath}
    test "$(${pkgs.coreutils}/bin/stat -c '%u:%g:%a' ${socketPath})" = '${bridgeID}:${bridgeID}:600'
  '';
  # Runs inside the headscale container, in deus-server itself and as its
  # user (UID 3999), before EVERY Deus start. Deus never creates the socket's
  # parent, and a host tmpfiles rule alone comes too late on the first -dm
  # switch: the host's tmpfiles run at sysinit-reactivation, AFTER the
  # activation script whose container reload has already restarted Deus,
  # which then logs "private DDM DISABLED" and never retries. mkdir as the
  # deus user gives exactly 3999:3999, and -m sets 0700 whatever the umask.
  # An existing path is left alone: Deus and the bridge preflight each
  # refuse anything but a real 3999:3999:0700 directory.
  #
  # Then the stale socket: after an unclean exit (SIGKILL at the stop
  # timeout, a crash, a hard reset) the socket file outlives Deus, and a Deus
  # that refuses an existing path would keep DDM off for good. Deus is not
  # running during its own ExecStartPre, so a socket nobody accepts on is
  # stale; clear-stale proves that with ECONNREFUSED before it unlinks.
  deusDdmPrepare = pkgs.writeShellScript "deus-ddm-private-prepare" ''
    set -u
    if [ ! -e ${privateDir} ] && [ ! -L ${privateDir} ]; then
      ${pkgs.coreutils}/bin/mkdir -m 0700 ${privateDir}
    fi
    exec ${pkgs.python3}/bin/python3 ${socketProbe} clear-stale ${socketPath}
  '';
in
{
  options.malli.mdm.ddmBridge = {
    enable = lib.mkEnableOption "the private NanoMDM-to-Deus DDM bridge";
    identityMigrationConfirmed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Explicit operator attestation that all Deus-owned bind-mounted entries and UID/GID maps were audited and migrated to 3999:3999; preserve files owned by other identities.";
    };
    credentialMigrationConfirmed = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Explicit operator attestation that NanoMDM and Deus DDM keys are private file-backed credentials, not CLI arguments or world-readable tokens.";
    };
    receiverConfigured = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Explicit operator attestation that the Deus private listener is file-key-configured for one enrollment and was tested with SO_PEERCRED UID 3999.";
    };
    enrollmentID = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        The single freshly verified NanoMDM device-channel enrollment ID the
        Deus private listener will answer for. This is a one-device pin, not a
        fleet-wide DDM switch; re-enrollment requires a new value and review.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.identityMigrationConfirmed
          && config.malli.mdm.deusDedicatedIdentity.enable
          && config.malli.mdm.deusDedicatedIdentity.migrationConfirmed;
        message = "DDM bridge requires separately enabled, approved, and verified dedicated Deus UID/GID 3999 migration.";
      }
      {
        assertion = cfg.credentialMigrationConfirmed;
        message = "DDM bridge requires private file-backed NanoMDM/Deus DDM credentials and a separately approved credential migration.";
      }
      {
        assertion = cfg.receiverConfigured;
        message = "DDM bridge requires the pinned Deus private receiver and actual SO_PEERCRED UID 3999 check before activation.";
      }
      {
        assertion = builtins.elem config.containers.headscale.privateUsers [ "no" "identity" ];
        message = "DDM bridge UID 3999 assumes identity host/nspawn UID mapping; re-design for shifted mappings.";
      }
      {
        # NOT the old name check. That one read a tag that mdm.nix derives from
        # the pin and compared it to a prefix also derived from the pin, so it
        # restated the pin to itself and passed for any source, upstream
        # included. Check the pin's actual coordinates against the reviewed
        # allowlist instead. (mdm.nix binds the pin's hash to the tree the
        # locked deus input really carries.)
        assertion = config.malli.mdm.nanomdmPatchedSourcePin != null
          && builtins.elem (reviewedCoordinates config.malli.mdm.nanomdmPatchedSourcePin)
            (map reviewedCoordinates
              config.malli.mdm.declarativeManagement.reviewedSourcePins);
        message = "DDM bridge requires a NanoMDM source pin on the reviewed declarative-management allowlist in hosts/vista/nanomdm-reviewed-source.nix; an arbitrary v0.9 pin is the unpatched, request-forgery build.";
      }
      {
        # And the image the container will actually run must be the one built
        # from such a revision: mdm.nix takes the tag from the package's own
        # version, and the acceptable tags are computed from the allowlist rows
        # with the same function, so a pin swapped underneath the module
        # cannot keep this green.
        assertion = builtins.elem
          config.virtualisation.oci-containers.containers.nanomdm.image
          (map (entry: "malli-nanomdm:${nanomdmVersion entry}")
            config.malli.mdm.declarativeManagement.reviewedSourcePins);
        message = "DDM bridge requires the configured NanoMDM image tag to be one built from a reviewed, endpoint-confined revision (hosts/vista/nanomdm-reviewed-source.nix).";
      }
      {
        assertion = cfg.enrollmentID != ""
          && builtins.stringLength cfg.enrollmentID <= 128
          && builtins.match "[A-Za-z0-9-]+" cfg.enrollmentID != null;
        message = "DDM bridge requires one verified NanoMDM device-channel enrollment ID (1-128 letters, digits or hyphens) in malli.mdm.ddmBridge.enrollmentID.";
      }
    ];

    # The ONLY directory this module creates. Deus refuses to bind its private
    # listener unless the socket's parent already exists, is owned by the Deus
    # UID and is exactly mode 0700 (internal/ddm/private_linux.go), and it
    # never creates that parent itself; the bridge preflight above then
    # re-checks the same three properties before Docker can start the sidecar.
    # This is a new, empty directory — not a chown of migrated Deus state, and
    # not a substitute for the approved /var/lib/deus migration, whose own
    # activation preflight still fails the switch if the parent is wrong.
    #
    # deus-server creates it itself before every start, and clears a stale
    # socket in it (deusDdmPrepare, "-": a failure there leaves only DDM
    # off, as Deus does, never the whole control plane). The host rule stays
    # for the bridge side and for boot. No host tmpfiles "r" rule for the
    # socket: a switch re-runs "systemd-tmpfiles --create --remove"
    # (systemd-tmpfiles-resetup), which would unlink a LIVE socket from under
    # a running Deus.
    systemd.tmpfiles.rules = [
      "d ${privateDir} 0700 ${bridgeID} ${bridgeID} -"
    ];
    containers.headscale.config = { ... }: {
      systemd.services.deus-server.serviceConfig.ExecStartPre =
        lib.mkAfter [ "-${deusDdmPrepare}" ];
    };

    # Same kernel-visible identity as nspawn's Deus process, but distinct from
    # host btrbk UID 999. No auto-chown: the operator must back up and migrate
    # the full /var/lib/deus tree before enabling this option.
    virtualisation.oci-containers.containers.deus-ddm-bridge = {
      imageFile = bridgeImage;
      image = "malli-deus-ddm-bridge:${bridgeTag}";
      user = "${bridgeID}:${bridgeID}";
      # Loopback is ONLY NanoMDM's private network namespace; no host port.
      ports = [ ];
      volumes = [ "${privateDir}:/run/ddm-private:ro" ];
      extraOptions = [
        "--network=container:nanomdm"
        "--read-only"
        "--cap-drop=ALL"
        "--security-opt=no-new-privileges"
        "--pids-limit=64"
      ];
      dependsOn = [ "nanomdm" ];
    };

    # Fail before Docker can implicitly create a missing bind source. Keep
    # NanoMDM available if the bridge fails. PartOf + Wants recreates the
    # sidecar in the NEW NanoMDM netns after a NanoMDM container restart.
    systemd.services.docker-deus-ddm-bridge = {
      after = [ "container@headscale.service" ];
      partOf = [ "docker-nanomdm.service" ];
      serviceConfig.ExecStartPre = lib.mkBefore [ "${bridgePreflight}" ];
    };
    systemd.services.docker-nanomdm.wants = [ "docker-deus-ddm-bridge.service" ];

  };
}
