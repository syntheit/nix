{ ... }:

{
  sops.defaultSopsFile = ../../secrets/conduit.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };

  # Deus secrets — sops renders to /run/secrets, which is a host-only
  # tmpfs. The headscale container can't follow that symlink, so the
  # deus-stage activation script in headscale.nix copies the actual
  # file contents into bind-mounted paths.
  sops.secrets.deus_operator_token.mode = "0444";
  sops.secrets.deus_agent_token.mode = "0444";
  # Read-only by root, copied into the container and re-permissioned to
  # the fleet user there so SSH accepts it as an identity file.
  # Stored as its own binary-encrypted file to avoid YAML multi-line
  # escaping pain — the OpenSSH private key format has trailing newlines
  # and base64 wrapping that fight with `|` literal blocks.
  sops.secrets.deus_deploy_key = {
    sopsFile = ../../secrets/conduit/deus_deploy_key;
    format = "binary";
    mode = "0400";
  };
}
