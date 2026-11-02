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

  # construct (services.constructLife): Anthropic API for in-app agents, Basic-auth password for the private F-Droid
  # repo at /fdroid/repo, and the culture sync's Seerr and Jellyfin keys. Same values as harbor.yaml.
  sops.secrets.anthropic_key = { owner = "droid"; mode = "0400"; };
  sops.secrets.fdroid_password = { owner = "droid"; mode = "0400"; };
  sops.secrets.seerr_api_key = { owner = "droid"; mode = "0400"; };
  sops.secrets.jellyfin_api_key = { owner = "droid"; mode = "0400"; };
}
