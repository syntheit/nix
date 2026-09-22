# The isolated rehearsal harness and every binary it runs.
#
# Only source revisions enter this expression: no backup, key, token, path
# to data or file from /var/lib. The Nix store is world-readable, so it holds
# the binaries and the scripts and nothing else. build.sh calls this file
# from a committed tree (git archive semantics via fetchGit); see README.md.
#
# The two NanoMDM servers are not rebuilt from a copy of their recipe. They
# are read out of Vista's own configuration: the binary each nanomdm
# container image's entrypoint execs.
#   v0.6  the configuration at vistaRev, as it is (the live release).
#   v0.9  the same configuration with malli.mdm.nanomdmPatchedSourcePin set
#         and the deus input replaced by newDeus, which is what step 3 turns
#         on. The pin's tree hash is checked against newDeus's vendored tree.
{ vistaRepo
, vistaRev
, newDeusRepo
, newDeusRev
, newDeusRef ? ""
, oldDeusRepo
, oldDeusRev
, oldDeusRef ? ""
  # The reviewed canary pin (tests/vista-mdm-credentials-eval.nix; Deus
  # third_party/VENDORED.md). deusRev only names the build in its version
  # string; the tree is fixed by hash.
, pinDeusRev ? "101d427b9c879be013d201269608bc5f3ef00494"
}:
let
  vistaFlake = builtins.getFlake "git+file://${vistaRepo}?rev=${vistaRev}";
  vista = vistaFlake.nixosConfigurations.vista;
  # What Vista's deus input builds with: the flake's nixpkgs, no overlays.
  pkgs = vistaFlake.inputs.nixpkgs.legacyPackages.x86_64-linux;
  inherit (pkgs) lib;

  gitSource = repo: rev: ref: builtins.fetchGit ({
    url = "file://${repo}";
    inherit rev;
  } // lib.optionalAttrs (ref != "") { inherit ref; });
  gitFlake = repo: rev: ref: builtins.getFlake
    ("git+file://${repo}?rev=${rev}" + lib.optionalString (ref != "") "&ref=${ref}");

  newDeusSrc = gitSource newDeusRepo newDeusRev newDeusRef;
  oldDeusSrc = gitSource oldDeusRepo oldDeusRev oldDeusRef;

  pin = {
    deusRev = pinDeusRev;
    nanomdmCommit = "3c52ba4a031c6d2035cea0722a47c598318fc59d";
    hash = "sha256-lhhXPgBp7SmdMCQc1c9/3ZBmrAbElvdXDtEWN68BP/Y=";
    vendorHash = "sha256-W49woVx8MjNZsfGHPudYReTRggnjfZ4f3VKCwgqaaV0=";
  };
  # Aborts the build unless newDeus vendors exactly the pinned tree (the
  # check hosts/vista/mdm.nix makes with a named assertion).
  vendoredNanoMDM = builtins.path {
    path = "${newDeusSrc}/third_party/nanomdm";
    name = "source";
    sha256 = pin.hash;
  };

  vistaV09 = vista.extendModules {
    specialArgs.inputs = vistaFlake.inputs // {
      deus = gitFlake newDeusRepo newDeusRev newDeusRef;
    };
    modules = [ { malli.mdm.nanomdmPatchedSourcePin = pin; } ];
  };
  entrypointOf = system: builtins.head
    system.config.virtualisation.oci-containers.containers.nanomdm.imageFile.buildArgs.config.Entrypoint;
  # The one nanomdm binary the entrypoint script execs, as a symlink; the
  # reference keeps the binary in this closure. Also $out/storage-flags: the
  # -storage and -storage-options flags that exec passes, as "-flag value"
  # pairs on one line, so the rehearsal can prove it runs each version with
  # the storage flags vista's configuration gives it.
  nanomdmFromEntrypoint = name: entrypoint: pkgs.runCommand name { } ''
    bins=$(grep -o '/nix/store/[a-z0-9]\{32\}-nanomdm-[^/ ]*/bin/nanomdm' ${entrypoint} | sort -u)
    if [ "$(printf '%s\n' "$bins" | grep -c .)" != 1 ]; then
      echo "expected exactly one nanomdm binary in ${entrypoint}" >&2
      exit 1
    fi
    # The exec of that binary, its continuation lines joined.
    cmd=$(sed -e ':a' -e '/\\$/N' -e 's/\\\n/ /' -e 'ta' ${entrypoint} \
      | awk -v b="$bins" '$1 == "exec" && $2 == b')
    if [ "$(printf '%s\n' "$cmd" | grep -c .)" != 1 ]; then
      echo "expected exactly one 'exec $bins' in ${entrypoint}" >&2
      exit 1
    fi
    set -f
    # Split the command into its words, unglobbed.
    set -- $cmd
    set +f
    flags=""
    while [ $# -gt 0 ]; do
      f=$1
      shift
      case $f in --*) f=''${f#-} ;; esac
      case $f in
        -storage | -storage-options)
          if [ $# = 0 ]; then echo "$f without a value in ${entrypoint}" >&2; exit 1; fi
          flags="$flags $f $1"
          shift ;;
        -storage=* | -storage-options=*) flags="$flags ''${f%%=*} ''${f#*=}" ;;
      esac
    done
    mkdir -p $out/bin
    ln -s "$bins" $out/bin/nanomdm
    printf '%s\n' ${entrypoint} > $out/entrypoint
    printf '%s\n' "''${flags# }" > $out/storage-flags
  '';
  nanomdmV06 = nanomdmFromEntrypoint "vista-nanomdm-live" (entrypointOf vista);
  nanomdmV09 = nanomdmFromEntrypoint "vista-nanomdm-step3" (entrypointOf vistaV09);

  # The storage flags the rehearsal runs each version with. v0.9's file
  # storage needs enable_deprecated=1, and v0.6 refuses any -storage-options,
  # so a rollback must drop it. The build checks both lists against the
  # entrypoints above, and inner.sh checks them again before it starts
  # either server.
  v09StorageFlags = [ "-storage" "file" "-storage-options" "enable_deprecated=1" ];
  v06StorageFlags = [ "-storage" "file" ];
  storageFlagsChecked =
    assert lib.assertMsg (lib.elem "enable_deprecated=1" v09StorageFlags)
      "v0.9's file storage needs -storage-options enable_deprecated=1";
    assert lib.assertMsg (!(lib.elem "-storage-options" v06StorageFlags))
      "v0.6 refuses any -storage-options";
    pkgs.runCommand "nanomdm-storage-flags-checked" { } ''
      check() { # label rehearsal-flags entrypoint-flags-file
        if [ "$(cat "$3")" != "$2" ]; then
          echo "$1: the rehearsal would run nanomdm with '$2', but vista's entrypoint passes '$(cat "$3")'" >&2
          exit 1
        fi
      }
      check "v0.9 (step 3)" ${lib.escapeShellArg (toString v09StorageFlags)} ${nanomdmV09}/storage-flags
      check "v0.6 (today)" ${lib.escapeShellArg (toString v06StorageFlags)} ${nanomdmV06}/storage-flags
      touch $out
    '';

  # probe/main.go compiled inside each version's own module, beside its
  # cmd/nanomdm, so it links that version's storage/file. It imports only
  # the module's own packages, so the module's vendor hash is unchanged.
  probeFor = { name, src, vendorHash }: pkgs.buildGoModule {
    pname = "nanomdm-rehearsal-probe-${name}";
    version = "1";
    src = pkgs.runCommand "nanomdm-${name}-with-probe" { } ''
      cp -r ${src} $out
      chmod -R u+w $out
      mkdir -p $out/cmd/rehearsal-probe
      cp ${./probe/main.go} $out/cmd/rehearsal-probe/main.go
    '';
    inherit vendorHash;
    subPackages = [ "cmd/rehearsal-probe" ];
    env.CGO_ENABLED = "0";
    doCheck = false;
  };
  probeV09 = probeFor { name = "v0.9"; src = vendoredNanoMDM; inherit (pin) vendorHash; };
  probeV06 = probeFor {
    name = "v0.6.0";
    src = pkgs.fetchFromGitHub {
      owner = "micromdm";
      repo = "nanomdm";
      rev = "v0.6.0";
      hash = "sha256-uzdSLmldVJlRbQlc+QhAN+E9I0m+1gHvqYsUBbFoqp0=";
    };
    vendorHash = "sha256-I3RjGi+lI4vXcw1TvEsmpTjgoZWgbMmrpCiy0UQofKc=";
  };

  # Deus exactly as Vista's deus input builds it (nix/package.nix with the
  # vista flake's nixpkgs), from committed trees only.
  deusNew = pkgs.callPackage "${newDeusSrc}/nix/package.nix" { };
  deusOld = pkgs.callPackage "${oldDeusSrc}/nix/package.nix" { };
  # The new Deus's migrations run through `deus-server -migrate-only` (Deus
  # c26640d). The build refuses a new Deus whose deus-server lacks the flag,
  # so a wrong --new-deus-rev fails here, before any backup is decrypted;
  # inner.sh probes for it again at run time.
  deusNewServer = pkgs.runCommand "deus-server-migrate-only-${deusNew.version}" { } ''
    rc=0
    ${deusNew}/bin/deus-server -help > help 2>&1 || rc=$?
    if [ "$rc" != 0 ] || ! grep -Eq '^ +-migrate-only( |$)' help; then
      echo "new deus ${newDeusRev} (${deusNew.version}): deus-server -help exited $rc and lists no -migrate-only; the rehearsal needs Deus c26640d or later" >&2
      exit 1
    fi
    mkdir -p $out/bin
    ln -s ${deusNew}/bin/deus-server $out/bin/deus-server
  '';
  # The tables the old Deus's own store.Open creates in an empty database,
  # one name per line. vista runs that Deus, so its deus.db has every one of
  # them; inner.sh refuses a copy that lacks any, such as the empty database
  # a mistyped `sqlite3 <source> .backup` makes. The build also requires
  # heartbeats among them: inner.sh requires rows there, because Deus keeps
  # one per host that ever reported and never deletes it.
  deusOldTables = pkgs.runCommand "deus-${deusOld.version}-tables" {
    nativeBuildInputs = [ pkgs.sqlite pkgs.libarchive ];
  } ''
    mkdir -p xlsx/xl/_rels
    printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets/></workbook>' > xlsx/xl/workbook.xml
    printf '%s' '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>' > xlsx/xl/_rels/workbook.xml.rels
    (cd xlsx && bsdtar --format zip -cf ../empty.xlsx xl)
    : > no-hosts
    ${deusOld}/bin/deus-rack-import -db "$PWD/deus.db" -xlsx "$PWD/empty.xlsx" \
      -hosts-file "$PWD/no-hosts" -dry-run > /dev/null
    sqlite3 -batch -bail deus.db \
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT GLOB 'sqlite_*' ORDER BY name;" > tables
    n=$(grep -c . tables || true)
    if [ "$n" -lt 1 ] || ! grep -qx heartbeats tables; then
      echo "old deus ${oldDeusRev} (${deusOld.version}): its store.Open made $n tables, and heartbeats is not one of them" >&2
      exit 1
    fi
    mkdir -p $out
    cp tables $out/tables
  '';

  tools = with pkgs; [
    bash coreutils findutils gnugrep gnused gawk diffutils util-linux
    bubblewrap age libarchive sqlite curl jq openssl
  ];
  sandboxPath = lib.makeBinPath tools;

  # deus.rollback proves something only when the old Deus is another Deus
  # than the new one. Once /home/daniel/nix/flake.lock points at the new
  # Deus, build.sh's default old revision is the new one, and the check
  # would test the new Deus against itself. So the harness refuses to build
  # when the two share a revision or a version; inner.sh checks again at run
  # time and fails deus.rollback.
  distinctDeus = newDeusRev != oldDeusRev && deusNew.version != deusOld.version;

  prelude = { v09 ? nanomdmV09, v09Entrypoint ? nanomdmV09
            , deusNewBin ? "${deusNewServer}/bin/deus-server"
            , rollbackDeus ? deusOld, rollbackDeusRev ? oldDeusRev
              # Self-test only: shell code appended to the prelude.
            , preludeExtra ? "" }: ''
    readonly NANOMDM_V09=${v09}/bin/nanomdm
    readonly NANOMDM_V06=${nanomdmV06}/bin/nanomdm
    readonly -a V09_STORAGE=(${lib.escapeShellArgs v09StorageFlags})
    readonly -a V06_STORAGE=(${lib.escapeShellArgs v06StorageFlags})
    readonly V09_ENTRYPOINT_FLAGS=${v09Entrypoint}/storage-flags
    readonly V06_ENTRYPOINT_FLAGS=${nanomdmV06}/storage-flags
    # Built only after ${storageFlagsChecked} checked both lists against vista's entrypoints.
    readonly PROBE_V09=${probeV09}/bin/rehearsal-probe
    readonly PROBE_V06=${probeV06}/bin/rehearsal-probe
    readonly DEUS_NEW=${deusNewBin}
    readonly DEUS_OLD=${rollbackDeus}/bin/deus-rack-import
    readonly DEUS_OLD_TABLES=${deusOldTables}/tables
    readonly DEUS_NEW_REV=${lib.escapeShellArg newDeusRev}
    readonly DEUS_OLD_REV=${lib.escapeShellArg rollbackDeusRev}
    readonly DEUS_NEW_VERSION=${lib.escapeShellArg deusNew.version}
    readonly DEUS_OLD_VERSION=${lib.escapeShellArg rollbackDeus.version}
    readonly V09_EXPECTED_PREFIX=0.9.0-patched-${builtins.substring 0 12 pin.nanomdmCommit}
    readonly V06_EXPECTED=v0.6.0
    readonly SANDBOX_PATH=${sandboxPath}
    readonly BUILD_INFO=${lib.escapeShellArg (lib.concatStringsSep "\n" [
      "vista config  ${vistaRev}"
      "new deus      ${newDeusRev} (${deusNew.version})"
      "old deus      ${rollbackDeusRev} (${rollbackDeus.version})"
      "v0.9 pin      deus ${pin.deusRev}, nanomdm ${pin.nanomdmCommit}"
      "              tree ${pin.hash}"
    ])}
    # Each script uses a subset of these.
    : "$NANOMDM_V09" "$NANOMDM_V06" "''${V09_STORAGE[@]}" "''${V06_STORAGE[@]}" "$V09_ENTRYPOINT_FLAGS" \
      "$V06_ENTRYPOINT_FLAGS" "$PROBE_V09" "$PROBE_V06" "$DEUS_NEW" "$DEUS_OLD" \
      "$DEUS_OLD_TABLES" "$DEUS_NEW_REV" "$DEUS_OLD_REV" "$DEUS_NEW_VERSION" "$DEUS_OLD_VERSION" \
      "$V09_EXPECTED_PREFIX" "$V06_EXPECTED" "$SANDBOX_PATH" "$BUILD_INFO"
    ${preludeExtra}
  '';

  mkInner = args: pkgs.writeShellApplication {
    name = "malli-rehearsal-inner";
    runtimeInputs = tools;
    text = prelude args + builtins.readFile ./inner.sh;
  };
  mkHarness = args: pkgs.writeShellApplication {
    name = "malli-rehearse";
    runtimeInputs = tools ++ [ pkgs.systemd ];
    text = prelude args + ''
      readonly INNER=${mkInner args}/bin/malli-rehearsal-inner
    '' + builtins.readFile ./rehearse.sh;
  };

  harness =
    assert lib.assertMsg distinctDeus ("the old Deus is not another Deus: new ${newDeusRev} (${deusNew.version}) and "
      + "old ${oldDeusRev} (${deusOld.version}) share a revision or a version, so deus.rollback would test the new Deus against itself. "
      + "Build with --old-deus-rev set to the Deus vista runs today");
    mkHarness { };

  # ── Self-test only ─────────────────────────────────────────────────────
  # A v0.9 that, once stopped, rewrites every TokenUpdate.plist in the store
  # it was given: the "v0.9 wrote something v0.6 cannot read" case.
  faultyV09 = pkgs.writeShellApplication {
    name = "nanomdm";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      dsn=""
      prev=""
      for a in "$@"; do
        if [ "$prev" = -storage-dsn ]; then dsn=$a; fi
        prev=$a
      done
      ${nanomdmV09}/bin/nanomdm "$@" &
      pid=$!
      trap 'kill -TERM "$pid" 2>/dev/null' TERM INT
      rc=0
      wait "$pid" || rc=$?
      wait "$pid" 2>/dev/null || true
      if [ -n "$dsn" ]; then
        for f in "$dsn"/*/TokenUpdate.plist; do
          [ -e "$f" ] && printf 'v0.9-only-format' > "$f"
        done
      fi
      exit "$rc"
    '';
  };
  harnessFaultyV09 = mkHarness { v09 = faultyV09; };
  # The old Deus's deus-server stands in for a new Deus built from a revision
  # before c26640d: it has no -migrate-only, and bypasses the build's check.
  harnessNoMigrateOnly = mkHarness { deusNewBin = "${deusOld}/bin/deus-server"; };
  # The new Deus stands in for the old one, as build.sh's default would make
  # it once the live flake.lock points at the new Deus. It bypasses the
  # build's check, so inner.sh's own check must fail deus.rollback.
  harnessOldIsNew = mkHarness { rollbackDeus = deusNew; rollbackDeusRev = newDeusRev; };
  # Step 3's entrypoint as if its configuration had dropped
  # -storage-options enable_deprecated=1, while the rehearsal still runs v0.9
  # with it: the rehearsal would prove a configuration step 3 does not run.
  # It bypasses the build's check (which reads the real entrypoint), so
  # inner.sh's own check must fail v09.start.
  driftedV09Entrypoint = pkgs.runCommand "nanomdm-entrypoint-drifted" { } ''
    sed 's/ -storage-options enable_deprecated=1//' ${entrypointOf vistaV09} > $out
    if cmp -s $out ${entrypointOf vistaV09}; then echo "the drift did not apply" >&2; exit 1; fi
  '';
  harnessDriftedV09 = mkHarness {
    v09Entrypoint = nanomdmFromEntrypoint "vista-nanomdm-step3-drifted" driftedV09Entrypoint;
  };
  # A harness in which cp fails, as it would on a full tmpfs: inner.sh's
  # copy of deus.db then stops the run on errexit, an abort no check
  # expects. The summary and a RESULT: FAIL line must still be printed.
  harnessCpFails = mkHarness {
    preludeExtra = ''
      # shellcheck disable=SC2329 # only inner.sh calls cp
      cp() { echo "self-test: cp fails here on purpose" >&2; return 1; }
    '';
  };

  fixture = pkgs.writeShellApplication {
    name = "malli-rehearsal-fixture";
    runtimeInputs = tools ++ [ pkgs.gnutar pkgs.zstd ];
    text = ''
      readonly DEUS_OLD=${deusOld}/bin/deus-rack-import
    '' + builtins.readFile ./selftest/make-fixture.sh;
  };
  selftest = pkgs.writeShellApplication {
    name = "malli-rehearsal-selftest";
    runtimeInputs = tools;
    text = ''
      readonly HARNESS=${harness}/bin/malli-rehearse
      readonly HARNESS_FAULTY_V09=${harnessFaultyV09}/bin/malli-rehearse
      readonly HARNESS_NO_MIGRATE_ONLY=${harnessNoMigrateOnly}/bin/malli-rehearse
      readonly HARNESS_OLD_IS_NEW=${harnessOldIsNew}/bin/malli-rehearse
      readonly HARNESS_DRIFTED_V09=${harnessDriftedV09}/bin/malli-rehearse
      readonly HARNESS_CP_FAILS=${harnessCpFails}/bin/malli-rehearse
      readonly FIXTURE=${fixture}/bin/malli-rehearsal-fixture
    '' + builtins.readFile ./selftest/run.sh;
  };
in
{
  inherit harness selftest nanomdmV06 nanomdmV09 probeV06 probeV09 deusNew deusOld;
}
