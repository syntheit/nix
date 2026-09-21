{ lib, buildGoModule, fetchFromGitHub, sourcePin }:

let
  # ── LOCAL-PATH OVERRIDE — PRE-PUBLICATION TESTING ONLY ─────────────────────
  # A local checkout is mutable and unreviewable: it has no content hash, it
  # can change between an evaluation and a build, and nothing records which
  # bytes were used. It exists so the patched tree can be built and its version
  # string checked BEFORE the fork is published, and it needs `--impure`
  # because a flake's pure evaluation refuses absolute paths. The Vista module
  # additionally refuses to combine it with privateCredentials.enable, so it
  # cannot reach a deployed host closure.
  localPath = sourcePin.localPath or null;
  local = localPath != null;
in

# The caller must supply an immutable, published source revision and both fixed
# hashes. No local /tmp checkout or floating branch may enter a host closure.
assert lib.assertMsg
  (builtins.match "[0-9a-f]{40}" sourcePin.rev != null)
  "nanomdm-patched requires a full 40-character commit revision";
assert lib.assertMsg
  (local || builtins.match "sha256-[A-Za-z0-9+/=]+" sourcePin.hash != null)
  "nanomdm-patched requires a fixed source hash";
assert lib.assertMsg
  (builtins.match "sha256-[A-Za-z0-9+/=]+" sourcePin.vendorHash != null)
  "nanomdm-patched requires a fixed Go vendor hash";

buildGoModule (finalAttrs: {
  pname = "nanomdm";
  version = "0.9.0-patched-${builtins.substring 0 12 sourcePin.rev}";

  src = if local then lib.cleanSource localPath else fetchFromGitHub {
    inherit (sourcePin) owner repo rev hash;
  };
  vendorHash = sourcePin.vendorHash;
  subPackages = [ "cmd/nanomdm" ];
  env.CGO_ENABLED = "0";
  # cmd/nanomdm declares `var version = "unknown"` and serves it verbatim on
  # /version and -version. Without this -X the rollback identity signal — which
  # of the two builds is live — reads "unknown" on both, so pin the real
  # revision into the binary. Keep it in sync with pname/version above.
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
    description = "Pinned patched NanoMDM v0.9 server";
    homepage = "https://github.com/micromdm/nanomdm";
    license = lib.licenses.mit;
    mainProgram = "nanomdm";
    platforms = [ "x86_64-linux" ];
  };
})
