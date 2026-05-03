# Foyer — self-hosted server dashboard
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.foyer;

  # The VM controller is enabled iff foyer-vm.enable AND libvirtd is enabled.
  vmControllerEnabled = cfg.vmController.enable && config.virtualisation.libvirtd.enable;

  configJson = builtins.toJSON {
    mode = cfg.mode;
    port = cfg.port;
    domain = cfg.domain;
    cookie_domain = cfg.cookieDomain;
    data_dir = cfg.dataDir;
    hostname = config.networking.hostName;
    api_keys = [ ]; # SSH key auth is primary; API keys loaded from files below
    api_key_files = cfg.apiKeyFiles;
    authorized_keys = cfg.authorizedKeys;
    allow_signups = cfg.allowSignups;
    services = lib.mapAttrsToList (name: svc: {
      inherit name;
      url = svc.url;
    }) cfg.services;
    hosts = lib.mapAttrsToList (name: host: {
      inherit name;
      url = host.url;
      api_key = ""; # Loaded at runtime via host API key files
    }) cfg.hosts;
    temperature_command = cfg.temperatureCommand;
    jellyfin =
      if cfg.jellyfin.enable then {
        url = cfg.jellyfin.url;
        api_key_file = cfg.jellyfin.apiKeyFile;
      } else null;
    minecraft =
      if cfg.minecraft.enable then {
        address = cfg.minecraft.address;
      } else null;
    vm_controller_socket = if vmControllerEnabled then "/run/foyer-vm/sock" else "";
  };
in
{
  options.services.foyer = {
    enable = lib.mkEnableOption "Foyer server dashboard";

    mode = lib.mkOption {
      type = lib.types.enum [ "full" "api-only" ];
      default = "full";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8420;
    };

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public domain for this instance";
    };

    cookieDomain = lib.mkOption {
      type = lib.types.str;
      default = ".matv.io";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/foyer";
    };

    jwtSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing JWT signing key (>= 32 bytes)";
    };

    apiKeyFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys authorized for API access";
    };

    allowSignups = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.url = lib.mkOption { type = lib.types.str; };
      });
      default = { };
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.url = lib.mkOption { type = lib.types.str; };
      });
      default = { };
    };

    temperatureCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "External command that outputs CPU temperature in °C as an integer";
    };

    extraReadPaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional read-only paths for the foyer service (e.g. SSH keys for temperature_command)";
    };

    jellyfin = {
      enable = lib.mkEnableOption "Jellyfin streams API";
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8096";
      };
      apiKeyFile = lib.mkOption {
        type = lib.types.path;
        default = "";
      };
    };

    minecraft = {
      enable = lib.mkEnableOption "Minecraft Server List Ping probe";
      address = lib.mkOption {
        type = lib.types.str;
        default = "localhost:25565";
        description = "host:port of the Minecraft server to probe";
      };
    };

    vmController = {
      enable = lib.mkEnableOption ''
        the VM control privilege-separated daemon (foyer-vm-controller).

        Foyer itself is NOT given libvirt access. Instead, a small daemon runs
        as the dedicated `foyer-vm` user (which is in the libvirtd group),
        listens on a Unix socket at /run/foyer-vm/sock, and is the only path
        from the web service to virsh. Foyer connects to that socket as a
        client.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."foyer/config.json".text = configJson;

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 foyer foyer -"
      "d ${cfg.dataDir}/files 0750 foyer foyer -"
    ] ++ lib.optionals vmControllerEnabled [
      # Socket dir owned by foyer-vm:foyer; foyer can traverse and connect.
      "d /run/foyer-vm 0750 foyer-vm foyer -"
    ];

    # Foyer DOES NOT get libvirt access — that's the whole point of the
    # privilege-separated controller. Foyer can only connect to the socket
    # because foyer-vm-controller chmods it 0660 and foreshadows the foyer
    # group on the socket directory below.
    users.users.foyer = {
      isSystemUser = true;
      group = "foyer";
      extraGroups = lib.optional config.virtualisation.docker.enable "docker";
      home = cfg.dataDir;
    };
    users.groups.foyer = { };

    # Dedicated user for the VM controller. Holds libvirtd group, nothing else.
    users.users.foyer-vm = lib.mkIf vmControllerEnabled {
      isSystemUser = true;
      group = "foyer-vm";
      extraGroups = [ "libvirtd" ];
      description = "Foyer VM controller (privilege-separated)";
    };
    users.groups.foyer-vm = lib.mkIf vmControllerEnabled { };

    systemd.services.foyer = {
      description = "Foyer server dashboard";
      after = [ "network-online.target" ]
        ++ lib.optional config.virtualisation.docker.enable "docker.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = lib.optional config.virtualisation.docker.enable config.virtualisation.docker.package
        ++ lib.optional config.boot.zfs.enabled pkgs.zfs
        ++ lib.optionals (cfg.temperatureCommand != "") [ pkgs.bash pkgs.openssh pkgs.iproute2 pkgs.coreutils pkgs.gawk ];

      # If the VM controller is active, foyer should wait for its socket
      # before starting (so the first request doesn't error out).
      after = lib.optional vmControllerEnabled "foyer-vm-controller.service";
      requires = lib.optional vmControllerEnabled "foyer-vm-controller.service";

      serviceConfig = {
        Type = "simple";
        User = "foyer";
        Group = "foyer";
        ExecStart = "${pkgs.foyer}/bin/foyer --config /etc/foyer/config.json --jwt-secret-file ${cfg.jwtSecretFile}";
        Restart = "always";
        RestartSec = "5s";

        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = if cfg.extraReadPaths != [ ] then "read-only" else true;
        ReadWritePaths = [ cfg.dataDir ]
          ++ lib.optional config.virtualisation.docker.enable "/run/docker.sock";
        # Foyer can read /run/foyer-vm to connect to the controller socket
        # (no write needed; the controller owns the socket).
        BindReadOnlyPaths = lib.optional vmControllerEnabled "/run/foyer-vm";
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;

        # Read /proc and /sys for health metrics
        ReadOnlyPaths = [ "/proc" "/sys" ] ++ cfg.extraReadPaths;

        # Docker socket access for container listing
        SupplementaryGroups = lib.optional config.virtualisation.docker.enable "docker";
      };
    };

    # ----- foyer-vm-controller -----
    # Privilege boundary for VM operations. Foyer talks to this over a Unix
    # socket; this is the ONLY process on the box (in the foyer stack) with
    # libvirt access.
    systemd.services.foyer-vm-controller = lib.mkIf vmControllerEnabled {
      description = "Foyer VM controller (privilege-separated libvirt bridge)";
      after = [ "libvirtd.service" ];
      requires = [ "libvirtd.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.libvirt ];

      serviceConfig = {
        Type = "simple";
        User = "foyer-vm";
        Group = "foyer-vm";
        # Pass the foyer UID so the controller can SO_PEERCRED-check incoming
        # connections — only the foyer process itself may connect.
        # Resolves the foyer UID by username at startup so we don't have to
        # pin a numeric UID in this module.
        ExecStart = "${pkgs.foyer}/bin/foyer-vm-controller --foyer-user foyer";
        Restart = "always";
        RestartSec = "5s";

        # Sandbox: most of these are paranoia given the tiny code surface,
        # but they're cheap and they kill obvious escape paths.
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        # Only Unix sockets — no IPv4/IPv6 networking is needed by virsh
        # (qemu:///system is a Unix socket too).
        RestrictAddressFamilies = [ "AF_UNIX" ];
        # Drop all capabilities. virsh + the libvirt socket need none.
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        SystemCallFilter = [ "@system-service" "~@privileged" "~@resources" "~@mount" ];
        SystemCallArchitectures = "native";

        # Where the socket lives. /run/foyer-vm is created by tmpfiles above.
        ReadWritePaths = [ "/run/foyer-vm" ];
        # Talking to libvirtd's Unix socket.
        BindPaths = [ "/run/libvirt" ];
      };
    };

    # Daily cleanup: expired files, pastes, old service checks
    systemd.services.foyer-cleanup = {
      description = "Foyer cleanup";
      serviceConfig = {
        Type = "oneshot";
        User = "foyer";
        Group = "foyer";
        ExecStart = "${pkgs.foyer}/bin/foyer --cleanup --config /etc/foyer/config.json --jwt-secret-file ${cfg.jwtSecretFile}";
      };
    };

    systemd.timers.foyer-cleanup = {
      description = "Foyer daily cleanup";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:30:00";
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
