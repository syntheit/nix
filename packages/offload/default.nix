# offload — hand token-heavy work from Claude Code to cheap OpenRouter models
# through headless opencode (see offload.sh). `opencode` itself comes from the
# user's PATH so the home-manager wrapper (config, Exa websearch) applies.
{
  writeShellApplication,
  coreutils,
  git,
  gnugrep,
  jq,
  util-linux,
}:

writeShellApplication {
  name = "offload";
  runtimeInputs = [
    coreutils
    git
    gnugrep
    jq
    util-linux
  ];
  text = builtins.readFile ./offload.sh;
}
