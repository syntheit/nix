{ ... }:

{
  sops.defaultSopsFile = ../../secrets/conduit.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };
}
