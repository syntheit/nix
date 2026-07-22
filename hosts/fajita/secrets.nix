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
}
