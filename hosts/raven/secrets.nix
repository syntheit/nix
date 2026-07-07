{ ... }:

{
  sops.defaultSopsFile = ../../secrets/raven.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };

  # OpenRouter key for opencode — pulled from the shared secret file (raven's
  # default sops file is raven.yaml, so override sopsFile just for this one).
  sops.secrets.openrouter_key = {
    sopsFile = ../../secrets/shared.yaml;
    owner = "droid";
    mode = "0400";
  };
}
