{ config, ... }:

{
  # sops-nix — secrets decrypted at activation time to /run/secrets/
  sops.defaultSopsFile = ../../secrets/harbor.yaml;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.secrets.nextdns_id = { };
  sops.secrets.nextcloud_db_root_pw = { };
  sops.secrets.nextcloud_db_name = { };
  sops.secrets.nextcloud_db_user = { };
  sops.secrets.nextcloud_db_pw = { };
  sops.secrets.qbittorrent_webui_password = { };
  sops.secrets.linkding_superuser_name = { };
  sops.secrets.linkding_superuser_password = { };
  sops.secrets.bitwarden_installation_id = { };
  sops.secrets.bitwarden_installation_key = { };
  sops.secrets.bitwarden_db_password = { };
  sops.secrets.retrospend_postgres_password = { };
  sops.secrets.retrospend_auth_secret = { };
  sops.secrets.retrospend_worker_api_key = { };
  sops.secrets.retrospend_openrouter_api_key = { };
  sops.secrets.retrospend_smtp_user = { };
  sops.secrets.retrospend_smtp_password = { };
  sops.secrets.immich_db_password = { };
  sops.secrets.vpn_openvpn_user = { };
  sops.secrets.vpn_openvpn_password = { };
  sops.secrets.restic_backup_password = { };

  # qBittorrent env file
  sops.templates."qbittorrent.env".content = ''
    VPN_TYPE=wireguard
    WEBUI_PASSWORD=${config.sops.placeholder.qbittorrent_webui_password}
  '';

  # Bitwarden env file
  sops.templates."bitwarden.env".content = ''
    BW_DOMAIN=vault.matv.io
    BW_INSTALLATION_ID=${config.sops.placeholder.bitwarden_installation_id}
    BW_INSTALLATION_KEY=${config.sops.placeholder.bitwarden_installation_key}
    BW_DB_PROVIDER=mysql
    BW_DB_SERVER=bitwarden_db
    BW_DB_DATABASE=bitwarden_vault
    BW_DB_USERNAME=bitwarden
    BW_DB_PASSWORD=${config.sops.placeholder.bitwarden_db_password}
  '';

  # Bitwarden DB env file
  sops.templates."bitwarden-db.env".content = ''
    MARIADB_RANDOM_ROOT_PASSWORD=true
    MARIADB_USER=bitwarden
    MARIADB_PASSWORD=${config.sops.placeholder.bitwarden_db_password}
    MARIADB_DATABASE=bitwarden_vault
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

  # VPN (Gluetun) env file
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
