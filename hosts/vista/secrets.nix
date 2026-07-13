{ config, ... }:

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
}
