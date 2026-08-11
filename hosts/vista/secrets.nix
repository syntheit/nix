{ config, lib, ... }:

{
  # sops-nix — secrets decrypted at activation time to /run/secrets/.
  # vista's own age identity (derived from its SSH host key) is a recipient on
  # secrets/vista.yaml; see .sops.yaml. Edit the secret values with
  # `sops secrets/vista.yaml`.
  sops.defaultSopsFile = ../../secrets/vista.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # ── Invidious (self-hosted YouTube frontend) ──────────────────────────────
  sops.secrets.invidious_companion_key = { };
  sops.secrets.invidious_hmac_key = { };
  sops.secrets.invidious_db_password = { };

  # Full invidious config.yml, mounted into the container at
  # /invidious/config/config.yml. 0444 so the container's non-root user can
  # read it. invidious_companion_key MUST equal the companion's
  # SERVER_SECRET_KEY (rendered just below).
  sops.templates."invidious.yml" = {
    mode = "0444";
    content = ''
      db:
        dbname: invidious
        user: kemal
        password: ${config.sops.placeholder.invidious_db_password}
        host: invidious-db
        port: 5432
      check_tables: true
      invidious_companion:
        - private_url: "http://invidious-companion:8282/companion"
      invidious_companion_key: "${config.sops.placeholder.invidious_companion_key}"
      hmac_key: "${config.sops.placeholder.invidious_hmac_key}"
    '';
  };

  # companion sidecar secret — must match invidious_companion_key above.
  sops.templates."invidious-companion.env".content = ''
    SERVER_SECRET_KEY=${config.sops.placeholder.invidious_companion_key}
  '';

  # postgres init env for the invidious DB.
  sops.templates."invidious-db.env".content = ''
    POSTGRES_DB=invidious
    POSTGRES_USER=kemal
    POSTGRES_PASSWORD=${config.sops.placeholder.invidious_db_password}
  '';

  # OpenRouter key for opencode — from the shared secret file (vista's default
  # sops file is vista.yaml, so override sopsFile just for this one).
  sops.secrets.openrouter_key = {
    sopsFile = ../../secrets/shared.yaml;
    owner = "daniel";
    mode = "0400";
  };

  # ── Deus / Headscale nspawn (migrated from conduit) ──────────────────────
  # Re-keyed from conduit into secrets/vista-deus.yaml + secrets/vista/*.
  # sops renders to /run/secrets/; the deus-stage activation script in
  # headscale.nix copies the contents into the nspawn's bind-mounted paths.
  sops.secrets.deus_operator_token = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.deus_agent_token = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.deus_service_token = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.cloudflare_api_token = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.cloudflare_account_id = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.cloudflare_zone_id = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.nanomdm_api = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0444"; };
  sops.secrets.deus_deploy_key = {
    sopsFile = ../../secrets/vista/deus_deploy_key;
    format = "binary";
    mode = "0400";
  };
  sops.secrets.deus_malli_nix_write_key = {
    sopsFile = ../../secrets/vista/deus_malli_nix_write_key;
    format = "binary";
    mode = "0400";
  };
  sops.secrets.deus_fleet_age_key = lib.mkIf (builtins.pathExists ../../secrets/vista/deus_fleet_age_key) {
    sopsFile = ../../secrets/vista/deus_fleet_age_key;
    format = "binary";
    mode = "0444";
  };

  # WireGuard private key for the wg0 link to conduit (vista = 10.100.0.4).
  sops.secrets.vista_wg_private_key = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };
}
