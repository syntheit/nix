{ lib, buildGoModule, src, sourcePin }:

# The patched NanoMDM v0.9 server, built from the tree Deus vendors at
# third_party/nanomdm (its VENDORED.md records the canary commit and the
# patches). hosts/vista/mdm.nix passes that tree from the `deus` flake input
# as `src` and asserts that it is the tree sourcePin.hash names; this file
# only builds it. There is no other source: no fetch, no local path.
#
# These asserts, not the Vista module's, are what an operator actually reads:
# forcing config.assertions forces the systemd units, which force this
# derivation, so a module-level assertion on the same conditions can never
# print. Keep the messages self-contained and name the option they came from.
assert lib.assertMsg
  (builtins.match "[0-9a-f]{40}" sourcePin.deusRev != null)
  "nanomdm-patched requires the full 40-character Deus revision in malli.mdm.nanomdmPatchedSourcePin.deusRev";
assert lib.assertMsg
  (builtins.match "[0-9a-f]{40}" sourcePin.nanomdmCommit != null)
  "nanomdm-patched requires the full 40-character vendored NanoMDM commit in malli.mdm.nanomdmPatchedSourcePin.nanomdmCommit";
assert lib.assertMsg
  (builtins.match "sha256-[A-Za-z0-9+/]{43}=" sourcePin.hash != null)
  "nanomdm-patched requires the NAR hash of the vendored tree in malli.mdm.nanomdmPatchedSourcePin.hash";
assert lib.assertMsg
  (builtins.match "sha256-[A-Za-z0-9+/=]+" sourcePin.vendorHash != null)
  "nanomdm-patched requires a fixed Go vendor hash";

buildGoModule (finalAttrs: {
  pname = "nanomdm";
  version = import ./version.nix sourcePin;

  inherit src;
  vendorHash = sourcePin.vendorHash;
  subPackages = [ "cmd/nanomdm" ];
  env.CGO_ENABLED = "0";
  # cmd/nanomdm declares `var version = "unknown"` and serves it verbatim on
  # /version and -version. Without this -X the rollback identity signal — which
  # of the two builds is live — reads "unknown" on both, so pin the reviewed
  # source into the binary: the vendored canary commit and the Deus revision
  # that carries it (./version.nix).
  ldflags = [ "-s" "-w" "-X main.version=${finalAttrs.version}" ];
  doCheck = true;

  # subPackages narrows BOTH the build and the check phase, so on its own it
  # would run only cmd/nanomdm's tests and skip every DDM-endpoint, HMAC-body
  # and storage test in the patched tree. Widen the check phase alone (the
  # install still ships one binary) to the packages this deployment actually
  # depends on: the DM hook and its endpoint confinement, the HMAC body
  # signer/verifier shared by the DM and webhook paths, the webhook service,
  # and the file storage backend we run plus its two siblings. MySQL and
  # PostgreSQL storage tests are deliberately excluded — they need a live
  # server and would only add build time and flakiness.
  preCheck = ''
    subPackages=(
      cmd/nanomdm
      service/dmhook
      service/webhook
      service/nanomdm
      http/hashbody
      http/mdm
      storage/file
      storage/inmem
      storage/diskv
    )
  '';

  meta = {
    description = "Patched NanoMDM v0.9 server vendored in Deus";
    homepage = "https://github.com/micromdm/nanomdm";
    license = lib.licenses.mit;
    mainProgram = "nanomdm";
    platforms = [ "x86_64-linux" ];
  };
})
