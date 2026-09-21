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
  # reference keeps the binary in this closure.
  nanomdmFromEntrypoint = name: entrypoint: pkgs.runCommand name { } ''
    bins=$(grep -o '/nix/store/[a-z0-9]\{32\}-nanomdm-[^/ ]*/bin/nanomdm' ${entrypoint} | sort -u)
    if [ "$(printf '%s\n' "$bins" | grep -c .)" != 1 ]; then
      echo "expected exactly one nanomdm binary in ${entrypoint}" >&2
      exit 1
    fi
    mkdir -p $out/bin
    ln -s "$bins" $out/bin/nanomdm
    printf '%s\n' ${entrypoint} > $out/entrypoint
  '';
  nanomdmV06 = nanomdmFromEntrypoint "vista-nanomdm-live" (entrypointOf vista);
  nanomdmV09 = nanomdmFromEntrypoint "vista-nanomdm-step3" (entrypointOf vistaV09);

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

  tools = with pkgs; [
    bash coreutils findutils gnugrep gnused gawk diffutils util-linux
    bubblewrap age libarchive sqlite curl jq openssl
  ];
  sandboxPath = lib.makeBinPath tools;

  prelude = { v09 ? nanomdmV09 }: ''
    readonly NANOMDM_V09=${v09}/bin/nanomdm
    readonly NANOMDM_V06=${nanomdmV06}/bin/nanomdm
    readonly PROBE_V09=${probeV09}/bin/rehearsal-probe
    readonly PROBE_V06=${probeV06}/bin/rehearsal-probe
    readonly DEUS_NEW=${deusNew}/bin/deus-rack-import
    readonly DEUS_OLD=${deusOld}/bin/deus-rack-import
    readonly DEUS_NEW_VERSION=${lib.escapeShellArg deusNew.version}
    readonly DEUS_OLD_VERSION=${lib.escapeShellArg deusOld.version}
    readonly V09_EXPECTED_PREFIX=0.9.0-patched-${builtins.substring 0 12 pin.nanomdmCommit}
    readonly V06_EXPECTED=v0.6.0
    readonly SANDBOX_PATH=${sandboxPath}
    readonly BUILD_INFO=${lib.escapeShellArg (lib.concatStringsSep "\n" [
      "vista config  ${vistaRev}"
      "new deus      ${newDeusRev} (${deusNew.version})"
      "old deus      ${oldDeusRev} (${deusOld.version})"
      "v0.9 pin      deus ${pin.deusRev}, nanomdm ${pin.nanomdmCommit}"
      "              tree ${pin.hash}"
    ])}
    # Each script uses a subset of these.
    : "$NANOMDM_V09" "$NANOMDM_V06" "$PROBE_V09" "$PROBE_V06" "$DEUS_NEW" "$DEUS_OLD" \
      "$DEUS_NEW_VERSION" "$DEUS_OLD_VERSION" "$V09_EXPECTED_PREFIX" "$V06_EXPECTED" \
      "$SANDBOX_PATH" "$BUILD_INFO"
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

  harness = mkHarness { };

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
      readonly FIXTURE=${fixture}/bin/malli-rehearsal-fixture
    '' + builtins.readFile ./selftest/run.sh;
  };
in
{
  inherit harness selftest nanomdmV06 nanomdmV09 probeV06 probeV09 deusNew deusOld;
}
