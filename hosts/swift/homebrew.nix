# swift's Homebrew extras; the shared casks and brews are in
# modules/darwin/homebrew-common.nix.
{ ... }:

{
  imports = [ ../../modules/darwin/homebrew-common.nix ];

  homebrew.casks = [
    "affinity"
    "blackhole-2ch"
    "claude"
    "macwhisper"
  ];
}
