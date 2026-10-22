# deus CLI v3 (`deus login`, then `deus hosts`, `deus bot X --why`, ...).
#
# Built from the private malli-deus flake input, so it tracks whatever rev
# flake.lock pins: bump the `deus` input to update it. `deus update` refuses
# to replace a binary under /nix/store, so it never fights this. Laptops
# without nix install it from the console instead (Settings, Install CLI).
{ inputs, pkgs, ... }:
{
  environment.systemPackages = [
    inputs.deus.packages.${pkgs.stdenv.hostPlatform.system}.deus-cli
  ];
}
