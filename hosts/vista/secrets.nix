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

  # ── Foyer (server dashboard, api-only) ────────────────────────────────────
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };

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
      # Public at https://lumen.matv.io via conduit (password wall) (2026-11-02): accounts only.
      domain: lumen.matv.io
      https_only: true
      external_port: 443
      registration_enabled: false
      login_enabled: true
      popular_enabled: false
      statistics_enabled: false
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

  # Meta app + permanent Page token for the hunt events pack (Instagram Business
  # Discovery as matv.events; ~/Projects/hunt src/hunt/hunts/events/graph.py reads
  # /run/secrets/events_meta_<key>). secrets/events-meta.yaml is shared with raven.
  # The token's data access lapses ~90 days after the last re-authorisation
  # (data_access_expires_at 2027-02-15); `hunt events token` checks it daily and
  # construct shows "Instagram key expires in N days" from 14 days out.
  sops.secrets.events_meta_page_token = { sopsFile = ../../secrets/events-meta.yaml; key = "page_token"; owner = "daniel"; mode = "0400"; };
  sops.secrets.events_meta_app_id = { sopsFile = ../../secrets/events-meta.yaml; key = "app_id"; owner = "daniel"; mode = "0400"; };
  sops.secrets.events_meta_app_secret = { sopsFile = ../../secrets/events-meta.yaml; key = "app_secret"; owner = "daniel"; mode = "0400"; };

  # WireGuard private key for the wg0 link to conduit (vista = 10.100.0.4).
  sops.secrets.vista_wg_private_key = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };
}
