{ lib, buildGoModule, fetchFromGitHub, sourcePin }:

# The caller must supply an immutable, published source revision and both fixed
# hashes. No local /tmp checkout or floating branch may enter a host closure.
assert lib.assertMsg
  (builtins.match "[0-9a-f]{40}" sourcePin.rev != null)
  "nanomdm-patched requires a full 40-character commit revision";
assert lib.assertMsg
  (builtins.match "sha256-[A-Za-z0-9+/=]+" sourcePin.hash != null)
  "nanomdm-patched requires a fixed source hash";
assert lib.assertMsg
  (builtins.match "sha256-[A-Za-z0-9+/=]+" sourcePin.vendorHash != null)
  "nanomdm-patched requires a fixed Go vendor hash";

buildGoModule {
  pname = "nanomdm";
  version = "0.9.0-patched-${builtins.substring 0 12 sourcePin.rev}";

  src = fetchFromGitHub {
    inherit (sourcePin) owner repo rev hash;
  };
  vendorHash = sourcePin.vendorHash;
  subPackages = [ "cmd/nanomdm" ];
  env.CGO_ENABLED = "0";
  ldflags = [ "-s" "-w" ];
  doCheck = true;

  meta = {
    description = "Pinned patched NanoMDM v0.9 server";
    homepage = "https://github.com/micromdm/nanomdm";
    license = lib.licenses.mit;
    mainProgram = "nanomdm";
    platforms = [ "x86_64-linux" ];
  };
}
