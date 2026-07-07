# opencode — terminal AI coding agent, driven by GLM-5.2 via OpenRouter.
#
# Declarative config is written to ~/.config/opencode/opencode.json by the
# home-manager `programs.opencode` module. The OpenRouter API key is NEVER
# stored in Nix: opencode reads it at runtime from the sops-decrypted file via
# {file:...} interpolation, so the key stays out of both the world-readable Nix
# store and the shell environment.
#
# Requires: a sops secret `openrouter_key` decrypted to /run/secrets/openrouter_key
# on the host (see hosts/*/secrets and .sops.yaml). Importing this module before
# that secret exists is harmless — opencode only fails at runtime if the key is
# missing, so the package + config still deploy cleanly.
{ pkgs, ... }:
{
  programs.opencode = {
    enable = true;
    package = pkgs.opencode;

    settings = {
      # opencode self-updates by default; that fails/wastes effort against the
      # immutable Nix store. Updates come through nixpkgs instead.
      autoupdate = false;

      # GLM-5.2 (Zhipu/Z.ai) — current top open-weight model, ~1M context — as
      # the default workhorse. Subagents (general/explore/scout) inherit this.
      model = "openrouter/z-ai/glm-5.2";

      # Only used for trivial background work (session titles, summaries).
      # Quality-irrelevant, so it can share the main model.
      small_model = "openrouter/z-ai/glm-5.2";

      # OpenRouter is a built-in provider (via the models.dev catalog), so we
      # only override the apiKey. {env:...} is currently broken for apiKey
      # (opencode issue #19946); {file:...} works and reads the sops secret.
      provider.openrouter.options.apiKey = "{file:/run/secrets/openrouter_key}";
    };
  };
}
