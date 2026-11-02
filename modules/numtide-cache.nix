# Binary cache for the llm-agents flake (claude-code, opencode).
#
# Both are vendor binaries being unpacked, so a miss costs little; the cache
# just saves every host redoing that after each daily bump.
#
# Trust: substituted paths are signed by the key below, so this trusts Numtide's
# build infrastructure not to ship something other than what the flake says.
# Works on both NixOS and nix-darwin.
{ ... }:
{
  nix.settings = {
    extra-substituters = [ "https://cache.numtide.com" ];
    extra-trusted-public-keys = [
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };
}
