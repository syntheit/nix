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

{ pkgs, inputs, vars, ... }:

let
  headscale-ui-src = pkgs.fetchzip {
    url = "https://github.com/gurucomputing/headscale-ui/releases/download/2025.01.20/headscale-ui.zip";
    hash = "sha256-eMT3/UsTYkiJFzoWlNPOM6hgbyGoBbPi3cs/u71KJ0c=";
    stripRoot = false;
  };
  headscale-ui = headscale-ui-src;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/deus 0750 root root -"
    # 0755 so the container's deus user can traverse to the world-readable token files inside.
    "d /var/lib/deus-tokens 0755 root root -"
    # 0750 — keys are root-only on the host; the container re-permissions for fleet/deus user.
    "d /var/lib/deus-keys 0750 root root -"
    # Granter master credentials. World-readable inside the container —
    # the only resident is the deus user and we want the fewest permission
    # gymnastics possible. The host-side directory is root-owned 0755 so
    # the container can traverse but unprivileged users on the host can't
    # read the files (the file mode itself is 0444).
    "d /var/lib/deus-granter 0755 root root -"
  ];

  # Sops renders to /run/secrets, a host-only tmpfs the container can't
  # follow into. Stage actual file contents into bind-mounted paths so
  # the container reads real files, not dangling symlinks.
  # mkdir here too because activation runs before systemd.tmpfiles
  # recreates dirs on first deploy.
  system.activationScripts.deus-stage = {
    deps = [ "setupSecrets" ];
    text = ''
      ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/deus-tokens
      ${pkgs.coreutils}/bin/install -d -m 0750 /var/lib/deus-keys
      ${pkgs.coreutils}/bin/install -d -m 0755 /var/lib/deus-granter
      ${pkgs.coreutils}/bin/install -m 0444 /run/secrets/deus_operator_token /var/lib/deus-tokens/operator-token
      ${pkgs.coreutils}/bin/install -m 0444 /run/secrets/deus_agent_token    /var/lib/deus-tokens/agent-token
      ${pkgs.coreutils}/bin/install -m 0400 /run/secrets/deus_deploy_key     /var/lib/deus-keys/deploy-malli-deus
      # Granter creds — best-effort install so half-configured deploys
      # leave the granter disabled rather than failing activation.
      stage_optional() {
        [ -f "$1" ] && ${pkgs.coreutils}/bin/install -m "$3" "$1" "$2" || true
      }
      stage_optional /run/secrets/twilio_master_account_sid /var/lib/deus-granter/twilio-master-sid  0444
      stage_optional /run/secrets/twilio_master_auth_token  /var/lib/deus-granter/twilio-master-auth 0444
      stage_optional /run/secrets/cloudflare_api_token      /var/lib/deus-granter/cloudflare-token   0444
      stage_optional /run/secrets/cloudflare_account_id     /var/lib/deus-granter/cf-account-id      0444
      stage_optional /run/secrets/cloudflare_zone_id        /var/lib/deus-granter/cf-zone-id         0444
      stage_optional /run/secrets/deus_malli_nix_write_key  /var/lib/deus-keys/malli-nix-write       0400
    '';
  };

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
      "/var/lib/deus" = {
        hostPath = "/var/lib/deus";
        isReadOnly = false;
      };
      "/var/lib/deus-tokens" = {
        hostPath = "/var/lib/deus-tokens";
        isReadOnly = true;
      };
      "/etc/deus-keys" = {
        hostPath = "/var/lib/deus-keys";
        isReadOnly = true;
      };
      "/etc/deus-granter" = {
        hostPath = "/var/lib/deus-granter";
        isReadOnly = true;
      };
      # Bind the malli-nix flake input (a /nix/store path on the host)
      # into the container so deus-server can read registry.nix from it.
      "/var/lib/deus-registry" = {
        hostPath = "${inputs.malli-nix}";
        isReadOnly = true;
      };
    };

    config = { pkgs, ... }: {
      imports = [
        inputs.deus.nixosModules.server
        inputs.home-manager.nixosModules.home-manager
      ];

      system.stateVersion = "23.11";

      # ── Home-manager for fleet user ──────────────────────
      # Imports the same shell.nix daniel uses on his own
      # workstations, so SSHing into the container feels like
      # an interactive shell, not a stripped-down jail.
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bkp";
      home-manager.extraSpecialArgs = { inherit inputs vars; };
      home-manager.users.fleet = { ... }: {
        imports = [
          inputs.nix-index-database.homeModules.nix-index
          ../../home/shell.nix
        ];
        home.username = "fleet";
        home.homeDirectory = "/home/fleet";
        home.stateVersion = "23.11";
      };

      # ── Deus fleet control plane ──────────────────────────
      services.deus.server = {
        enable = true;
        address = "0.0.0.0";
        port = 8086;
        registryFile = "/var/lib/deus-registry/hosts/registry.nix";
        operatorTokenFile = "/var/lib/deus-tokens/operator-token";
        agentTokenFile = "/var/lib/deus-tokens/agent-token";

        # ── Granter ──
        # Twilio + Cloudflare per-device provisioning. The four
        # credential files are populated by the activation script in
        # this same module from sops secrets defined in secrets.nix.
        # Account/zone IDs are config, not secrets.
        granter = {
          enable = true;
          domain = "themalli.ai";
          twilioMasterSIDFile = "/etc/deus-granter/twilio-master-sid";
          twilioMasterAuthFile = "/etc/deus-granter/twilio-master-auth";
          cfAPITokenFile = "/etc/deus-granter/cloudflare-token";
          cfAccountIDFile = "/etc/deus-granter/cf-account-id";
          cfZoneIDFile = "/etc/deus-granter/cf-zone-id";
          # GIT_SSH_COMMAND fully specifies the identity, so no
          # `Host github-malli-nix-write` SSH alias is needed — git just
          # invokes `ssh git@github.com` and the wrapper picks the key.
          repoURL = "git@github.com:syntheit/malli-nix.git";
          repoSSHCommand = "ssh -i /etc/deus-keys/malli-nix-write -o IdentitiesOnly=yes -o UserKnownHostsFile=/var/lib/deus/known_hosts -o StrictHostKeyChecking=accept-new";
          # The headscale CLI lives in the same container, but its socket
          # is owned by the headscale group. We expose it world-readable
          # below (`unix_socket_permission`) so the deus user can call
          # it directly.
          headscaleCommand = "headscale nodes list -o json";
        };
      };

      # Use Tailscale's DNS so tailnet hostnames resolve
      # (e.g. ssh tars@m-1w6l works inside the container).
      networking.nameservers = [ "100.100.100.100" ];
      networking.search = [ "tail.matv.io" ];

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
          # Allow the deus user (granter) to call `headscale nodes list`
          # directly. Single-tenant container, only resident processes
          # are headscale and deus-server, so 0666 is fine.
          unix_socket_permission = "0666";
        };
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

      # Fix authorized_keys.d permissions for OpenSSH 10.x.
      # Plus copy the deploy key from the host bind-mount into fleet's
      # home with strict perms so SSH accepts it as an identity file.
      # Also pre-create the git mirror dir so the systemd timers below
      # can clone into it on first run.
      systemd.tmpfiles.rules = [
        "d /etc/ssh/authorized_keys.d 0755 root root -"
        "d /home/fleet/.ssh 0700 fleet users -"
        "C+ /home/fleet/.ssh/deploy_key_deus 0600 fleet users - /etc/deus-keys/deploy-malli-deus"
        "d /var/lib/git-mirror 0755 fleet users -"
        # Granter pushes to malli-nix on GitHub from inside the deus-server
        # systemd unit. Pre-seed github.com host keys so the push doesn't
        # block on an interactive prompt. Owned by deus (the container's
        # deus user; this rule runs inside the container's NixOS, where
        # the user exists).
        "f /var/lib/deus/known_hosts 0644 deus deus - github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
      ];


      # ── Tailnet-internal git mirror ───────────────────────
      # Fleet machines fetch flake sources from `git+git://conduit/...`
      # rather than GitHub, so they never need GitHub credentials. The
      # mirror lives in this container because the deploy keys it uses
      # to fetch from upstream already live here. git:// is plaintext
      # but the wireguard-encrypted tailnet is the trust boundary.
      services.gitDaemon = {
        enable = true;
        basePath = "/var/lib/git-mirror";
        exportAll = true;
        listenAddress = "0.0.0.0";
      };

      # Mirror service writes as `fleet`, daemon reads as `git` — git's
      # safe-directory check refuses cross-owner access otherwise.
      environment.etc.gitconfig.text = ''
        [safe]
        	directory = /var/lib/git-mirror/*
      '';

      systemd.services.malli-nix-mirror = {
        description = "Mirror malli-nix from GitHub";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.git pkgs.openssh ];
        serviceConfig = {
          Type = "oneshot";
          User = "fleet";
          Group = "users";
          ExecStart = pkgs.writeShellScript "malli-nix-mirror" ''
            set -e
            cd /var/lib/git-mirror
            if [ ! -d malli-nix.git ]; then
              git clone --mirror git@github.com:syntheit/malli-nix.git
            fi
            git -C malli-nix.git fetch --all --prune
          '';
        };
      };

      systemd.timers.malli-nix-mirror = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "30s";
          OnUnitActiveSec = "5m";
        };
      };

      systemd.services.malli-deus-mirror = {
        description = "Mirror malli-deus from GitHub";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [ pkgs.git pkgs.openssh ];
        serviceConfig = {
          Type = "oneshot";
          User = "fleet";
          Group = "users";
          ExecStart = pkgs.writeShellScript "malli-deus-mirror" ''
            set -e
            cd /var/lib/git-mirror
            if [ ! -d malli-deus.git ]; then
              git clone --mirror git@github-malli-deus:syntheit/malli-deus.git
            fi
            git -C malli-deus.git fetch --all --prune
          '';
        };
      };

      systemd.timers.malli-deus-mirror = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "45s";
          OnUnitActiveSec = "5m";
        };
      };

      # ── Fleet user ────────────────────────────────────────
      users.users.fleet = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        shell = pkgs.zsh;
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
        git
      ];

      programs.zsh.enable = true;

      # GitHub deploy keys are unique per repo, so two of them under
      # the same Host don't both work — first key wins and scopes the
      # connection. Use a per-repo alias for malli-deus; keep the
      # default github.com pointing at the existing malli-nix key so
      # `git pull` on the cloned malli-nix repo still works unchanged.
      programs.ssh.extraConfig = ''
        Host github.com
          IdentityFile /home/fleet/.ssh/deploy_key
          IdentitiesOnly yes

        Host github-malli-deus
          HostName github.com
          User git
          IdentityFile /home/fleet/.ssh/deploy_key_deus
          IdentitiesOnly yes

        Host *
          IdentityFile /home/fleet/.ssh/id_ed25519
          StrictHostKeyChecking accept-new
      '';

      nix.settings.experimental-features = [ "nix-command" "flakes" ];
    };
  };

  # ── Tailscale (on host) ─────────────────────────────────────
  # Runs on the host so the tailscale0 interface is available for
  # the registry proxy and SSH routing to fleet machines.
  services.tailscale = {
    enable = true;
    authKeyFile = "/etc/tailscale/authkey";
    extraUpFlags = [
      "--login-server" "https://headscale.matv.io"
      "--hostname" "conduit"
    ];
  };

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
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 5000 8086 9418 ];

  # Open the container's SSH port to the internet
  networking.firewall.allowedTCPPorts = [ 2222 ];
}
