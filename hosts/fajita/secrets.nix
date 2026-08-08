{ ... }:

{
  # Shared user secret (openrouter_key for opencode), decrypted at activation
  # with fajita's SSH host key (its age key is enrolled in ../../.sops.yaml).
  # Read by opencode via {file:/run/secrets/openrouter_key}.
  sops.defaultSopsFile = ../../secrets/shared.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  sops.secrets.openrouter_key = {
    owner = "daniel";
    mode = "0400";
  };

  # Telegram api_id / api_hash for paloma, injected at RUNTIME by
  # pkgs.paloma-wrapped. Declared here so the secret is present when the app is
  # eventually installed on the phone (see the commented paloma-wrapped line in
  # hosts/fajita/default.nix). From secrets/shared.yaml (keys: paloma_api_id,
  # paloma_api_hash).
  sops.secrets.paloma_api_id = {
    owner = "daniel";
    mode = "0400";
  };
  sops.secrets.paloma_api_hash = {
    owner = "daniel";
    mode = "0400";
  };
}
