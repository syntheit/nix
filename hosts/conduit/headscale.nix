# Headscale — open-source Tailscale coordination server.
# Runs inside a NixOS container (systemd-nspawn) for isolation.
# Coworkers SSH into the container to manage the fleet, without
# access to the host system.
#
# Migration: headscale data is bind-mounted from the host at
# /var/lib/headscale. Backup at /var/backups/headscale.
#
# Usage (from anywhere):
#   ssh fleet@headscale.matv.io -p 2222    # SSH into container
#   headscale nodes list                    # view fleet
#   ssh tars@m-1w6l                         # SSH to Mac Mini (via tailnet)
#   ssh lima@m-1w6l-vm                      # SSH to VM (via tailnet)

{ pkgs, ... }:

let
  headscale-ui-src = pkgs.fetchzip {
    url = "https://github.com/gurucomputing/headscale-ui/releases/download/2025.01.20/headscale-ui.zip";
    hash = "sha256-eMT3/UsTYkiJFzoWlNPOM6hgbyGoBbPi3cs/u71KJ0c=";
    stripRoot = false;
  };
  headscale-ui = headscale-ui-src;
in
{
  # ── Headscale container ────────────────────────────────────
  containers.headscale = {
    autoStart = true;

    # Use host networking so headscale binds to localhost:8085
    # (Caddy on the host proxies to it) and tailscale can reach
    # the fleet directly.
    privateNetwork = false;

    # Bind-mount headscale state from the host so data persists
    # across container rebuilds and is easy to back up.
    bindMounts = {
      "/var/lib/headscale" = {
        hostPath = "/var/lib/headscale";
        isReadOnly = false;
      };
      "/var/lib/tailscale" = {
        hostPath = "/var/lib/tailscale-container";
        isReadOnly = false;
      };
    };

    config = { pkgs, ... }: {
      system.stateVersion = "23.11";

      # ── Headscale ────────────────────────────────────────
      services.headscale = {
        enable = true;
        address = "127.0.0.1";
        port = 8085;

        settings = {
          server_url = "https://headscale.matv.io";
          dns = {
            magic_dns = true;
            base_domain = "tail.matv.io";
            override_local_dns = true;
            nameservers.global = [ "1.1.1.1" "1.0.0.1" ];
          };
          prefixes = {
            v4 = "100.64.0.0/10";
            v6 = "fd7a:115c:a1e0::/48";
            allocation = "sequential";
          };
          derp = {
            urls = [ "https://controlplane.tailscale.com/derpmap/default" ];
            auto_update_enabled = true;
            update_frequency = "3h";
          };
          database = {
            type = "sqlite";
            sqlite = {
              path = "/var/lib/headscale/db.sqlite";
              write_ahead_log = true;
            };
          };
          logtail.enabled = false;
          disable_check_updates = true;
          node.expiry = 0;
        };
      };

      # ── Tailscale (inside container) ──────────────────────
      # Connected to the headscale network so users who SSH in
      # can reach all fleet machines directly.
      services.tailscale = {
        enable = true;
        authKeyFile = "/var/lib/tailscale/authkey";
        extraUpFlags = [
          "--login-server" "https://headscale.matv.io"
          "--hostname" "conduit"
        ];
      };

      # ── SSH for fleet operators ───────────────────────────
      services.openssh = {
        enable = true;
        ports = [ 2222 ];
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
        extraConfig = "UsePAM yes";
      };

      # PAM fix for OpenSSH 10.x (same as fleet VMs)
      security.pam.services.sshd.rules.auth.permit_pubkey = {
        order = 12400;
        control = "sufficient";
        modulePath = "pam_permit.so";
      };

      # Fix authorized_keys.d permissions for OpenSSH 10.x
      systemd.tmpfiles.rules = [
        "d /etc/ssh/authorized_keys.d 0755 root root -"
      ];

      # ── Fleet user ────────────────────────────────────────
      users.users.fleet = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEODivGUKMXoxIyGkw6BWN023G2N1SL2yDi8lpulnc7R alan_ps@hotmail.com"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDTZdD7pKHnM5C/9WLs5SJbOSdW8Ee2H4GMi6rXcxM3FPXz5Md47zeBAsoQulFFGWDe5VaIueyt7ILXoSqMonz1kNDBjeGY0DCpVozd9iobzLRaoet3fKlvxvr35h/Z99YgltEWR/N/Dir7+4Mk2Tl80RWTx0RA6s3IHUsstCFWAxh175Maydspmaq0l1gsqvWEB1MZwGMUuZjGI53WKaQBRgHGMqBSoSANWpPrAdTYemkvf53RJiNuHHhZ5t5M73oCHvLviJ48FIWpOaKBp2l+b1R6fB6MBmCMoVUxgQYUZTyOyS81+wVKqjYWY19jfDRLH972cA679pm9y/+xnoNaAmdQ77qppbr+pEFxQmNQrNCggdpAyZKGl2Kfsp0guqWnG7sm7AjKMV2AF8hMSAp8vh9CGjEA4pu1vpHlZVOXRTAeT6pavmfbPDnBgOulALkRWydWGwMJkyoMnSyYo0Z+PxzgtHTlfeCYE19pOnnKqyIlUHpVP9M4kN1EluZT51c="
        ];
      };

      security.sudo.wheelNeedsPassword = false;

      # ── Packages available to fleet operators ─────────────
      environment.systemPackages = with pkgs; [
        htop
        jq
        curl
        vim
        bat
        tmux
      ];

      programs.zsh.enable = true;
    };
  };

  # ── Create container tailscale state directory ─────────────
  systemd.tmpfiles.rules = [
    "d /var/lib/tailscale-container 0700 root root -"
  ];

  # ── Caddy reverse proxy (on host) ─────────────────────────
  # Proxies to headscale inside the container. Since the container
  # uses host networking, headscale is still at localhost:8085.
  services.caddy.virtualHosts."headscale.matv.io" = {
    extraConfig = ''
      handle /web/* {
        root * ${headscale-ui}
        file_server
        try_files {path} /web/index.html
      }
      redir /web /web/ permanent
      handle /api/* {
        @options method OPTIONS
        header @options Access-Control-Allow-Origin "*"
        header @options Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header @options Access-Control-Allow-Headers "Authorization, Content-Type"
        header @options Access-Control-Max-Age "86400"
        respond @options 204
        reverse_proxy localhost:8085
      }
      handle {
        reverse_proxy localhost:8085
      }
    '';
  };

  # ── Docker Registry proxy (on host) ────────────────────────
  # Forwards port 5000 from Tailscale interface to harbor's registry
  # over WireGuard. Only Headscale fleet machines can reach it.
  systemd.services.registry-proxy = {
    description = "Proxy Docker registry to harbor over WireGuard";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.socat}/bin/socat TCP-LISTEN:5000,fork,reuseaddr TCP:10.100.0.2:5000";
      Restart = "always";
      RestartSec = "5s";
    };
  };

  # Only open port 5000 on the Tailscale interface — blocked from the internet
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5000 ];

  # Open the container's SSH port to the internet
  networking.firewall.allowedTCPPorts = [ 2222 ];
}
