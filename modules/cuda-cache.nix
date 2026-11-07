# Binary cache for nixpkgs CUDA builds (the NixOS CUDA team's Hydra).
#
# cache.nixos.org carries no CUDA builds, so without this any `cudaSupport`
# package (pkgsCuda.python3Packages.torch, llama-cpp, ollama-cuda) compiles
# from source for hours. Checked 2026-11-07 against mantle's pin: all of those
# hit. Only with the default cudaCapabilities, though: narrowing them (e.g. to
# ["7.5"] for the 2070S) changes every hash and misses the cache.
#
# Enable CUDA per package or per project, never globally via
# nixpkgs.config.cudaSupport: that rebuilds unrelated system packages.
#
# Trust: substituted paths are signed by the key below, so this trusts the
# NixOS CUDA team's build infrastructure. Replaced cuda-maintainers.cachix.org
# (retired Nov 2025, now 401s).
{ ... }:
{
  nix.settings = {
    extra-substituters = [ "https://cache.nixos-cuda.org" ];
    extra-trusted-public-keys = [
      "cache.nixos-cuda.org:74DUi4Ye579gUqzH4ziL9IyiJBlDpMRn9MBN8oNan9M="
    ];
  };
}
