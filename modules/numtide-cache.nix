# Binary cache for the llm-agents flake (claude-code, codex, opencode).
#
# Without it, codex builds from Rust source on every host after every daily
# bump. claude-code and opencode are just vendor binaries being unpacked, so
# they cost nothing either way — this is about codex.
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
