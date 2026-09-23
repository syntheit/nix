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

  # ADE admin password: the fixed password deus-server gives the admin on
  # every ADE-provisioned Mac. It used to be a literal in headscale.nix, which
  # put it in this public repo and in the world-readable unit file. The file
  # holds exactly the bytes deus-server receives, with no trailing newline.
  #
  # Declared unconditionally, unlike the gated secrets below: without it ADE
  # would quietly fall back to random per-device passwords, so a missing file
  # has to fail the build. 0400/root: it reaches deus-server through systemd
  # LoadCredential (see the deus-server wrapper in headscale.nix).
  #
  # Re-create (on vista, from the repo root) without the value touching argv:
  #   printf '%s' "$pw" | sops encrypt --filename-override \
  #     secrets/vista/deus_ade_admin_password --input-type binary \
  #     --output-type binary /dev/stdin > secrets/vista/deus_ade_admin_password
  sops.secrets.deus_ade_admin_password = {
    sopsFile = ../../secrets/vista/deus_ade_admin_password;
    format = "binary";
    mode = "0400";
  };

  # ── Dark-host alerting sinks ──────────────────────────────────────
  # deus-server's dark-host watch has been merged and deployed since the
  # September incident and has never fired once, for one reason: it was
  # never given a sink. It sweeps the fleet every 60s and raises an event
  # when a Mac goes seen→unseen for ten minutes, then posts it nowhere.
  # Eight bot Macs stayed dark for four days and the first report came
  # from a customer.
  #
  # Either file alone switches it on; both can run together.
  #
  # Standalone sops files gated on the file existing, rather than keys in
  # vista-deus.yaml, for the same reason deus_fleet_age_key is: a
  # declared-but-absent key fails sops activation for the WHOLE host, so
  # a secret that has not been created yet would break every rebuild
  # until it was. Absent file → the whole wiring below is inert and
  # deus-server starts exactly as it does today.
  #
  # ⚠️ These are also systemd LoadCredential sources, and systemd FAILS a
  # unit whose credential source is missing. That is why the gate is on
  # the encrypted file's presence at EVAL time, not on the staged file at
  # runtime: nix decides whether the flag is emitted at all, so the unit
  # can never reference a credential that was not staged.
  #
  # Create either one ON VISTA (.sops.yaml routes secrets/vista/* to
  # vista + daniel), then `git add` it — a flake cannot see an untracked
  # file, so an un-added secret evaluates as absent and nothing happens:
  #
  #   printf '%s' 'https://hooks.slack.com/services/T…/B…/…' \
  #     | sops --encrypt --input-type binary --output-type binary /dev/stdin \
  #     > ~/nix/secrets/vista/deus_dark_host_webhook
  #   git -C ~/nix add secrets/vista/deus_dark_host_webhook
  #
  #   printf '%s' 'https://<key>@<org>.ingest.sentry.io/<project>' \
  #     | sops --encrypt --input-type binary --output-type binary /dev/stdin \
  #     > ~/nix/secrets/vista/deus_dark_host_sentry_dsn
  #   git -C ~/nix add secrets/vista/deus_dark_host_sentry_dsn
  #
  # No trailing newline: deus trims whitespace, but a webhook URL is
  # compared against hooks.slack.com by hostname and there is no reason
  # to make that depend on trimming.
  #
  # 0400/root like the other LoadCredential sources — systemd reads them
  # as root before dropping to the deus user, so neither ever has to be
  # readable by deus on disk.
  sops.secrets.deus_dark_host_webhook = lib.mkIf (builtins.pathExists ../../secrets/vista/deus_dark_host_webhook) {
    sopsFile = ../../secrets/vista/deus_dark_host_webhook;
    format = "binary";
    mode = "0400";
  };
  sops.secrets.deus_dark_host_sentry_dsn = lib.mkIf (builtins.pathExists ../../secrets/vista/deus_dark_host_sentry_dsn) {
    sopsFile = ../../secrets/vista/deus_dark_host_sentry_dsn;
    format = "binary";
    mode = "0400";
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
  sops.secrets.deus_malli_admin_token_dev = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };

  # Read-only AWS credentials for deus-server, so the console can show the bots
  # that are STILL on Fargate alongside the ones already on Macs. Each bot has
  # its own ECS service named svc-<botUid>, so listing them and reading their
  # desiredCount is the whole AWS-side inventory — and the complement against
  # hosts/bots.json is the migration backlog.
  #
  # IAM user `deus-ecs-readonly`, inline policy `ecs-read-mallipro`: exactly
  # ecs:ListServices + ecs:DescribeServices, conditioned to the
  # malli-ai-api-prod-mallipro-orch cluster. It cannot scale a service, touch a
  # task definition, or read anything outside ECS — verified after creation by
  # calling it (lists services; AccessDenied on iam:ListUsers).
  #
  # Deliberately NOT the credentials that were already on harbor: those belong
  # to a person (IAM user Nathan), and a service that needs to read a list of
  # container names should not inherit an individual's permissions.
  sops.secrets.deus_aws_access_key_id = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };
  sops.secrets.deus_aws_secret_access_key = { sopsFile = ../../secrets/vista-deus.yaml; mode = "0400"; };
}
