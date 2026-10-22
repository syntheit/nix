# mini's Homebrew extras; the shared casks and brews are in
# modules/darwin/homebrew-common.nix.
{ ... }:

{
  imports = [ ../../modules/darwin/homebrew-common.nix ];

  homebrew.casks = [
    # "blackhole-2ch"  # existential.audio (162.241.218.190) is down; brew bundle has no
                       # per-URL timeout and hangs forever. Re-enable once the upstream
                       # is reachable, or install the .pkg from
                       # https://github.com/ExistentialAudio/BlackHole/releases
  ];
}
