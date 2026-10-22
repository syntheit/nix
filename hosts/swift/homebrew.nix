# swift's Homebrew extras; the shared casks and brews are in
# modules/darwin/homebrew-common.nix.
{ ... }:

{
  imports = [ ../../modules/darwin/homebrew-common.nix ];

  homebrew.casks = [
    "blackhole-2ch"
  ];
}
