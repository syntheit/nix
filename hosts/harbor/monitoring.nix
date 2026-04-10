{ config, ... }:

{
  # Prometheus — metrics collection
  services.prometheus = {
    enable = true;
    port = 9090;
    listenAddress = "127.0.0.1";
    retentionTime = "30d";
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{
          targets = [ "127.0.0.1:9100" ];
        }];
      }
      {
        job_name = "prometheus";
        static_configs = [{
          targets = [ "127.0.0.1:9090" ];
        }];
      }
    ];
  };

  # Node exporter — system metrics (CPU, RAM, disk, network, ZFS)
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    listenAddress = "127.0.0.1";
    enabledCollectors = [ "systemd" "zfs" ];
  };

  # Grafana — metrics visualization (default login: admin/admin, forced change on first login)
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3100;
        domain = "grafana.matv.io";
        root_url = "https://grafana.matv.io";
      };
      security.secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
    };
  };
}
