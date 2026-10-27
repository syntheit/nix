{ pkgs, ... }:

# Retrospend dev: the next release on a copy of prod data, at https://dev.retrospend.app.
# Same image build as prod, its own Postgres, sidecar (rate sync, imports,
# backups), volumes and network. No email: it never contacts anyone. Env files are written by
# ~/Projects/retrospend/docs/ui-overhaul/ops/dev/seed-dev.sh (not sops).
# Images retrospend:dev and retrospend-sidecar:dev are built locally by ops/dev/deploy-dev.sh.
{
  virtualisation.oci-containers.containers = {
    retrospend_dev = {
      image = "retrospend:dev";
      environmentFiles = [ "/var/lib/retrospend-dev/app.env" ];
      ports = [ "127.0.0.1:1998:1997" ];
      volumes = [
        "retrospend_dev_uploads:/data/uploads"
        "retrospend_dev_exports:/data/exports"
      ];
      dependsOn = [ "retrospend_dev_postgres" "retrospend_dev_sidecar" ];
      extraOptions = [ "--network=retrospend_dev" ];
    };
    retrospend_dev_sidecar = {
      image = "retrospend-sidecar:dev";
      environmentFiles = [ "/var/lib/retrospend-dev/app.env" ];
      volumes = [
        "retrospend_dev_sidecar_data:/app/data"
        "retrospend_dev_backup_data:/backups"
      ];
      dependsOn = [ "retrospend_dev_postgres" ];
      extraOptions = [
        "--network=retrospend_dev"
        "--network-alias=sidecar"
      ];
    };
    retrospend_dev_postgres = {
      image = "postgres:16-alpine";
      environmentFiles = [ "/var/lib/retrospend-dev/postgres.env" ];
      volumes = [ "retrospend_dev_postgres_data:/var/lib/postgresql/data" ];
      extraOptions = [
        "--network=retrospend_dev"
        "--network-alias=postgres"
      ];
    };
  };

  systemd.services.docker-retrospend_dev_postgres.preStart =
    "${pkgs.docker}/bin/docker network create retrospend_dev || true";

  # Nightly dump of the dev DB, kept 14 days (it holds real data while in use).
  systemd.services.retrospend-dev-backup = {
    serviceConfig.Type = "oneshot";
    path = [ pkgs.docker pkgs.coreutils pkgs.findutils ];
    script = ''
      dir=/var/backups/retrospend-dev
      mkdir -p "$dir"
      docker exec retrospend_dev_postgres sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' \
        > "$dir/$(date +%F).dump.tmp" && mv "$dir/$(date +%F).dump.tmp" "$dir/$(date +%F).dump"
      find "$dir" -name '*.dump' -mtime +14 -delete
    '';
  };
  systemd.timers.retrospend-dev-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:30";
      Persistent = true;
    };
  };
}
