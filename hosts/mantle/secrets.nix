{ ... }:

{
  # Shared user secrets live in secrets/shared.yaml, decrypted at activation
  # with mantle's SSH host key (its age key is enrolled in ../../.sops.yaml).
  # Currently just the OpenRouter key, read by opencode at runtime via
  # {file:/run/secrets/openrouter_key} (see home/modules/opencode.nix).
  sops.defaultSopsFile = ../../secrets/shared.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets.openrouter_key = {
    owner = "daniel";
    mode = "0400";
  };

  # Telegram api_id / api_hash for paloma, injected at RUNTIME into the app's
  # env by pkgs.paloma-wrapped (overlays/default.nix) — never baked into the
  # nix store. From the shared secret file (values added separately via
  # `sops secrets/shared.yaml`; keys: paloma_api_id, paloma_api_hash).
  sops.secrets.paloma_api_id = {
    owner = "daniel";
    mode = "0400";
  };
  sops.secrets.paloma_api_hash = {
    owner = "daniel";
    mode = "0400";
  };

  # WireGuard private key for the point-to-point link to conduit (mirrors
  # harbor's wg_conduit_private_key). Lives in secrets/mantle.yaml, which is
  # also where the MDM stack's nanomdm_api + scep_challenge live.
  sops.secrets.mantle_wg_private_key.sopsFile = ../../secrets/mantle.yaml;
}
