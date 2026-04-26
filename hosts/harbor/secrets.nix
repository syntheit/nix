{ config, ... }:

{
  # sops-nix — secrets decrypted at activation time to /run/secrets/
  sops.defaultSopsFile = ../../secrets/harbor.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.foyer_jwt_secret = { owner = "foyer"; };
  sops.secrets.foyer_api_key = { owner = "foyer"; };
  sops.secrets.foyer_jellyfin_api_key = { owner = "foyer"; };
  sops.secrets.nextdns_id = { };
  sops.secrets.nextcloud_db_root_pw = { };
  sops.secrets.nextcloud_db_name = { };
  sops.secrets.nextcloud_db_user = { };
  sops.secrets.nextcloud_db_pw = { };
  sops.secrets.qbittorrent_webui_password = { };
  sops.secrets.linkding_superuser_name = { };
  sops.secrets.linkding_superuser_password = { };
  sops.secrets.vaultwarden_admin_token = { };
  sops.secrets.retrospend_postgres_password = { };
  sops.secrets.retrospend_auth_secret = { };
  sops.secrets.retrospend_worker_api_key = { };
  sops.secrets.retrospend_openrouter_api_key = { };
  sops.secrets.retrospend_smtp_user = { };
  sops.secrets.retrospend_smtp_password = { };
  sops.secrets.immich_db_password = { };
  sops.secrets.vpn_openvpn_user = { };
  sops.secrets.vpn_openvpn_password = { };
  sops.secrets.vpn_wireguard_private_key = { };
  sops.secrets.vpn_wireguard_address = { };
  sops.secrets.vpn_wireguard_public_key = { };
  sops.secrets.vpn_wireguard_endpoint = { };
  sops.secrets.vpn_wireguard_preshared_key = { };
  sops.secrets.restic_backup_password = { };
  sops.secrets.wg_conduit_private_key = { };
  sops.secrets.paperless_admin_password = {
    mode = "0444"; # readable by paperless service user
  };
  sops.secrets.karakeep_nextauth_secret = { };
  sops.secrets.karakeep_meili_master_key = { };
  sops.secrets.docmost_app_secret = { };
  sops.secrets.docmost_db_password = { };
  sops.secrets.elliot_telegram_token = { owner = "elliot"; };
  sops.secrets.grafana_secret_key = {
    owner = "grafana";
    group = "grafana";
  };
  sops.secrets.pelican_db_root_pw = { };
  sops.secrets.pelican_db_pw = { };
  sops.secrets.seafile_mysql_root_pw = { };
  sops.secrets.seafile_mysql_db_pw = { };
  sops.secrets.seafile_jwt_private_key = { };
  sops.secrets.seafile_admin_email = { };
  sops.secrets.seafile_admin_password = { };

  # qBittorrent env file
  sops.templates."qbittorrent.env".content = ''
    VPN_TYPE=wireguard
    WEBUI_PASSWORD=${config.sops.placeholder.qbittorrent_webui_password}
  '';

  # Vaultwarden env file
  sops.templates."vaultwarden.env".content = ''
    ADMIN_TOKEN=${config.sops.placeholder.vaultwarden_admin_token}
    DOMAIN=https://vault.matv.io
    SIGNUPS_ALLOWED=false
  '';

  # Retrospend env file (shared by app + sidecar)
  sops.templates."retrospend.env".content = ''
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.retrospend_postgres_password}
    POSTGRES_DB_NAME=retrospend
    DATABASE_URL=postgresql://postgres:${config.sops.placeholder.retrospend_postgres_password}@postgres:5432/retrospend
    AUTH_SECRET=${config.sops.placeholder.retrospend_auth_secret}
    WORKER_API_KEY=${config.sops.placeholder.retrospend_worker_api_key}
    OPENROUTER_API_KEY=${config.sops.placeholder.retrospend_openrouter_api_key}
    OPENROUTER_MODEL=qwen/qwen-2.5-7b-instruct
    SIDECAR_URL=http://sidecar:8080
    PUBLIC_URL=https://retrospend.app
    UPLOAD_DIR=/data/uploads
    SHOW_LANDING_PAGE=true
    ENABLE_LEGAL_PAGES=true
    AUDIT_PRIVACY_MODE=anonymized
    SMTP_HOST=smtppro.zoho.com
    SMTP_PORT=587
    SMTP_USER=${config.sops.placeholder.retrospend_smtp_user}
    SMTP_PASSWORD=${config.sops.placeholder.retrospend_smtp_password}
    EMAIL_FROM=Retrospend <noreply@retrospend.app>
  '';

  # Retrospend Postgres env file
  sops.templates."retrospend-postgres.env".content = ''
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.retrospend_postgres_password}
    POSTGRES_DB=retrospend
  '';

  # Immich env file (shared by server + ML + postgres)
  sops.templates."immich.env".content = ''
    DB_USERNAME=postgres
    DB_PASSWORD=${config.sops.placeholder.immich_db_password}
    DB_DATABASE_NAME=immich
    IMMICH_VERSION=release
    UPLOAD_LOCATION=/arespool/nextcloud/data/topikzero/files/ImmichUpload
  '';

  # Immich Postgres env file
  sops.templates."immich-postgres.env".content = ''
    POSTGRES_USER=postgres
    POSTGRES_PASSWORD=${config.sops.placeholder.immich_db_password}
    POSTGRES_DB=immich
    POSTGRES_INITDB_ARGS=--data-checksums
    DB_STORAGE_TYPE=SSD
  '';

  # VPN (Gluetun) env file — OpenVPN (required for Windscribe static IP port forwarding)
  sops.templates."vpn.env".content = ''
    VPN_SERVICE_PROVIDER=custom
    VPN_TYPE=openvpn
    OPENVPN_CUSTOM_CONFIG=/gluetun/custom.conf
    OPENVPN_USER=${config.sops.placeholder.vpn_openvpn_user}
    OPENVPN_PASSWORD=${config.sops.placeholder.vpn_openvpn_password}
    FIREWALL_VPN_INPUT_PORTS=2283,5096
    FIREWALL_OUTBOUND_SUBNETS=172.24.0.0/16
    PUID=1000
    PGID=1000
  '';

  # Linkding env file
  sops.templates."linkding.env".content = ''
    LD_SUPERUSER_NAME=${config.sops.placeholder.linkding_superuser_name}
    LD_SUPERUSER_PASSWORD=${config.sops.placeholder.linkding_superuser_password}
    LD_CSRF_TRUSTED_ORIGINS=https://links.matv.io
    LD_DISABLE_BACKGROUND_TASKS=False
    LD_DISABLE_URL_VALIDATION=False
  '';

  # Nextcloud MariaDB env file — rendered from sops secrets at boot
  sops.templates."nextcloud-db.env".content = ''
    PUID=1000
    PGID=1000
    MYSQL_ROOT_PASSWORD=${config.sops.placeholder.nextcloud_db_root_pw}
    TZ=America/New_York
    MYSQL_DATABASE=${config.sops.placeholder.nextcloud_db_name}
    MYSQL_USER=${config.sops.placeholder.nextcloud_db_user}
    MYSQL_PASSWORD=${config.sops.placeholder.nextcloud_db_pw}
  '';

  # Karakeep env file
  sops.templates."karakeep.env".content = ''
    NEXTAUTH_SECRET=${config.sops.placeholder.karakeep_nextauth_secret}
    NEXTAUTH_URL=https://keep.matv.io
    MEILI_ADDR=http://karakeep_meilisearch:7700
    MEILI_MASTER_KEY=${config.sops.placeholder.karakeep_meili_master_key}
    DATA_DIR=/data
    BROWSER_WEB_URL=http://karakeep_chrome:9222
    CRAWLER_FULL_PAGE_ARCHIVE=true
    CRAWLER_FULL_PAGE_SCREENSHOT=true
    OLLAMA_BASE_URL=http://ollama:11434
    INFERENCE_TEXT_MODEL=qwen2.5:7b
    DISABLE_SIGNUPS=true
  '';

  # Karakeep Meilisearch env file
  sops.templates."karakeep-meilisearch.env".content = ''
    MEILI_MASTER_KEY=${config.sops.placeholder.karakeep_meili_master_key}
    MEILI_NO_ANALYTICS=true
  '';

  # Docmost env file
  sops.templates."docmost.env".content = ''
    APP_URL=https://docs.matv.io
    APP_SECRET=${config.sops.placeholder.docmost_app_secret}
    DATABASE_URL=postgresql://docmost:${config.sops.placeholder.docmost_db_password}@docmost_postgres:5432/docmost
    REDIS_URL=redis://docmost_redis:6379
  '';

  # Docmost Postgres env file
  sops.templates."docmost-postgres.env".content = ''
    POSTGRES_USER=docmost
    POSTGRES_PASSWORD=${config.sops.placeholder.docmost_db_password}
    POSTGRES_DB=docmost
  '';

  # Seafile env file
  sops.templates."seafile.env".content = ''
    SEAFILE_MYSQL_DB_PASSWORD=${config.sops.placeholder.seafile_mysql_db_pw}
    JWT_PRIVATE_KEY=${config.sops.placeholder.seafile_jwt_private_key}
    INIT_SEAFILE_MYSQL_ROOT_PASSWORD=${config.sops.placeholder.seafile_mysql_root_pw}
    INIT_SEAFILE_ADMIN_EMAIL=${config.sops.placeholder.seafile_admin_email}
    INIT_SEAFILE_ADMIN_PASSWORD=${config.sops.placeholder.seafile_admin_password}
  '';

  # Seafile MariaDB env file
  sops.templates."seafile-db.env".content = ''
    MYSQL_ROOT_PASSWORD=${config.sops.placeholder.seafile_mysql_root_pw}
  '';

  # Pelican Panel DB env file
  sops.templates."pelican-db.env".content = ''
    MYSQL_ROOT_PASSWORD=${config.sops.placeholder.pelican_db_root_pw}
    MYSQL_PASSWORD=${config.sops.placeholder.pelican_db_pw}
  '';

  # Pelican Panel env file (DB password for the app)
  sops.templates."pelican-panel.env".content = ''
    DB_PASSWORD=${config.sops.placeholder.pelican_db_pw}
  '';

  # NextDNS resolved config
  sops.templates."nextdns-resolved.conf".content = ''
    [Resolve]
    DNS=45.90.28.0#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNS=2a07:a8c0::#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNS=45.90.30.0#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNS=2a07:a8c1::#${config.sops.placeholder.nextdns_id}.dns.nextdns.io
    DNSOverTLS=yes
  '';
}
