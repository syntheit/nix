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
  # malli-nix READ deploy key for the git mirror (github.com). On conduit this
  # was placed by hand and never managed; formalized here as a sops secret.
  sops.secrets.malli_nix_deploy_key = {
    sopsFile = ../../secrets/vista/malli_nix_deploy_key;
    format = "binary";
    mode = "0400";
  };
  sops.secrets.deus_malli_nix_write_key = {
    sopsFile = ../../secrets/vista/deus_malli_nix_write_key;
    format = "binary";
    mode = "0400";
  };
  # GitHub App private key (malli-granter App) the granter uses to mint
  # installation tokens and push to malli-nix via the ruleset bypass,
  # replacing the branch-protection-blocked deploy-key direct push.
  sops.secrets.deus_github_app_key = {
    sopsFile = ../../secrets/vista/deus_github_app_key;
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

  # Auth.js JWT signing/encryption secret for the deus web console
  # (services.deus.web, host-level — see headscale.nix). 0400/root: read by
  # systemd (root) via LoadCredential in the malli-web unit, not by the
  # malli-web user directly — matches deus_deploy_key et al above.
  sops.secrets.deus_web_auth_secret = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };

  # Google OAuth client SECRET for console SSO. Only this half is sensitive —
  # the client ID is public by design and sits as a plain value in
  # headscale.nix. Same 0400/root treatment: it reaches the process through
  # systemd LoadCredential, never an Environment= string, which would render it
  # into the world-readable nix store.
  sops.secrets.deus_web_google_client_secret = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };

  # malli-ai platform-admin bearer token. deus-server uses it to read a bot's
  # DECLARED runner placement and to flip it between `ecs` and `fleet`.
  #
  # That flip is the actual AWS→Mac migration step. Writing hosts/bots.json
  # only provisions capacity on the Mac: RUNNER_PLACEMENT_ENFORCED is on in
  # prod, and an `ecs`-placed bot never consults deus at all, so no amount of
  # fleet-side config moves its traffic.
  #
  # 0400/root like deus_web_auth_secret: it reaches deus-server through systemd
  # LoadCredential, never an Environment= string, which would render it into
  # the world-readable nix store and into /proc/*/environ.
  #
  # ⚠️ This is a PIPELINE_API_KEY-class credential, which malli-ai treats as
  # full platform admin — it can provision and retire orgs, buy Twilio numbers
  # and reset passwords, none of which deus has any business doing. deus calls
  # only the two placement routes. The durable fix is a scoped service
  # principal; the orchestrator already accepts MALLI_PRO_ADMIN_API_KEY under a
  # separate name, so one can be minted without resharing this key.
  sops.secrets.deus_malli_admin_token = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };
}
