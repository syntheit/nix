# retrospend CI on vista: one throwaway microVM per GitHub Actions job.
#
# Threat model: every job is hostile. The realistic way in is a compromised npm
# package, not a stranger (fork PRs need approval and never come here). So:
#
#   - Each job gets a fresh cloud-hypervisor VM (./guest.nix): read-only erofs
#     store, blank work disk, no host paths. It runs one job and powers off;
#     ci-slot<N> then boots the next one.
#   - The GitHub token (sops) stays on the host. Per boot, the slot mints a
#     single-use JIT runner config and hands only that to the VM.
#   - The VMs' traffic leaves only through the Windscribe OpenVPN tunnel
#     (policy routing, table 177). The table ends in an unreachable default,
#     so with the tunnel down nothing gets out: no fallback to the home line.
#   - Firewall: from a VM, only the internet via the tunnel and the Docker Hub
#     pull cache on 10.77.0.1:5050. Not vista, the LAN, the tailnet or wg0.
#   - The slot refuses to boot a VM if that routing or firewall is missing, and
#     the VM checks it can't reach any of it before it starts the runner.
#   - Each slot's hypervisor runs as its own unprivileged user (ci-vm1, ci-vm2)
#     in a systemd sandbox.
#
# Repo side: .github/workflows/ci.yml sends push jobs to [self-hosted, vista-ci].
#
# Addresses: slot N's tap ciN is 10.77.N.1/30 (host) and 10.77.N.2 (guest).
# Logs: journalctl -u ci-slot1 (the guest console, including its self-check).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  repo = "syntheit/retrospend";
  # "ba": Buenos Aires, shared exit IP, ~6 ms. "dc": Washington DC static IP
  # 82.29.92.28, +160 ms. Both configs are in secrets/vista.yaml.
  vpn = "ba";
  table = 177;

  ci = {
    vcpu = 6;
    memMiB = 7168;
    workDiskMiB = 60 * 1024;
    cacheAddr = "10.77.0.1";
    cachePort = 5050;
    cacheGiB = 20;
  };

  slots =
    map
      (i: {
        index = i;
        tap = "ci${toString i}";
        hostIp = "10.77.${toString i}.1";
        guestIp = "10.77.${toString i}.2";
        mac = "02:00:00:77:00:0${toString i}";
      })
      [
        1
        2
      ];

  guestRunner =
    slot:
    (inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit slot ci; };
      modules = [
        inputs.microvm.nixosModules.microvm
        ./guest.nix
      ];
    }).config.microvm.declaredRunner;

  privateRanges = lib.concatStringsSep "," [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "224.0.0.0/3"
  ];

  # What a VM must NOT reach (its self-check). The slot adds its own gateway,
  # vista's LAN address and the home router at boot.
  blocked = [
    "${ci.cacheAddr}:22" # vista, through the cache address
    "10.100.0.1:22" # conduit (wg0)
    "10.100.0.4:22" # vista's wg0 address
    "100.109.63.87:22" # harbor (tailnet)
    "100.75.241.25:22" # mini (tailnet)
    "100.100.100.100:53" # tailscale DNS
    "192.168.0.100:22" # mantle (LAN)
    "169.254.169.254:80" # link-local metadata address
  ];

  scriptEnv = {
    REPO = repo;
    TABLE = toString table;
    TOKEN_FILE = config.sops.secrets.ci_runner_github_token.path;
    BLOCKED = lib.concatStringsSep "\n" blocked;
  };

  slotScript =
    name: file:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = with pkgs; [
        coreutils
        curl
        e2fsprogs
        gawk
        gnugrep
        iproute2
        iptables
        jq
        systemd
      ];
      runtimeEnv = scriptEnv;
      text = builtins.readFile file;
    };
  prepare = slotScript "ci-slot-prepare" ./slot-prepare.sh;
  cleanup = slotScript "ci-slot-cleanup" ./slot-cleanup.sh;

  cacheDir = "/var/lib/ci-registry-cache";
  cacheImage = "/var/lib/ci-registry-cache.img";
  # A fixed-size image caps what jobs can make the cache store on vista's
  # disk (it fetches whatever a VM asks for).
  cacheMount = pkgs.writeShellApplication {
    name = "ci-cache-mount";
    runtimeInputs = with pkgs; [
      coreutils
      e2fsprogs
      util-linux
    ];
    text = ''
      if [ ! -e ${cacheImage} ]; then
        touch ${cacheImage}
        chattr +C ${cacheImage} 2>/dev/null || true # no btrfs copy-on-write
        truncate -s ${toString ci.cacheGiB}G ${cacheImage}
        mkfs.ext4 -q -m 0 ${cacheImage}
      fi
      mkdir -p ${cacheDir}
      mountpoint -q ${cacheDir} || mount -o loop,nodev,nosuid,noexec ${cacheImage} ${cacheDir}
      chown ci-cache:ci-cache ${cacheDir}
      chmod 0700 ${cacheDir}
    '';
  };

  cacheConfig = pkgs.writeText "ci-registry-cache.yml" (
    builtins.toJSON {
      version = "0.1";
      log.level = "info";
      storage = {
        filesystem.rootdirectory = cacheDir;
        delete.enabled = true;
      };
      http.addr = "${ci.cacheAddr}:${toString ci.cachePort}";
      proxy = {
        remoteurl = "https://registry-1.docker.io";
        ttl = "168h";
      };
    }
  );

  # Shared by the hypervisor and the cache: neither needs anything else.
  sandbox = {
    NoNewPrivileges = true;
    ProtectSystem = "strict";
    ProtectHome = true;
    PrivateTmp = true;
    ProtectKernelTunables = true;
    ProtectKernelModules = true;
    ProtectKernelLogs = true;
    ProtectControlGroups = true;
    ProtectClock = true;
    ProtectHostname = true;
    RestrictNamespaces = true;
    RestrictRealtime = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    CapabilityBoundingSet = "";
    SystemCallArchitectures = "native";
    UMask = "0077";
  };
  slotUnit = s: {
    description = "CI runner VM, slot ${toString s.index}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network-online.target"
      "ci-net.service"
      "ci-registry-cache.service"
      "openvpn-ci.service"
      "firewall.service"
    ];
    wants = [ "network-online.target" ];
    requires = [ "ci-net.service" ];
    startLimitIntervalSec = 0;
    serviceConfig = sandbox // {
      # One user per slot: an escape from one VM can't open the other's tap,
      # disks or hypervisor.
      User = "ci-vm${toString s.index}";
      Group = "ci-vm${toString s.index}";
      StateDirectory = "ci-vm/slot${toString s.index}";
      StateDirectoryMode = "0700";
      WorkingDirectory = "/var/lib/ci-vm/slot${toString s.index}";
      ExecStartPre = "+${lib.getExe prepare} ${toString s.index}";
      ExecStart = "${guestRunner s}/bin/microvm-run";
      ExecStopPost = "+${lib.getExe cleanup} ${toString s.index}";
      Restart = "always";
      RestartSec = "30s";
      # A stuck job (or an idle VM) is recycled; GitHub fails the job.
      RuntimeMaxSec = "100min";
      LimitMEMLOCK = "infinity";
      LimitNOFILE = 1048576;
      DevicePolicy = "closed";
      DeviceAllow = [
        "/dev/kvm rw"
        "/dev/net/tun rw"
      ];
      RestrictAddressFamilies = [ "AF_UNIX" ];
      # Below the agents and services that already live here.
      MemoryMax = "${toString (ci.memMiB + 1024)}M";
      CPUWeight = 50;
      IOWeight = 50;
    };
  };
in
{
  sops.secrets.ci_runner_github_token = { };
  sops.secrets."windscribe_ci_${vpn}_ovpn" = { };
  sops.secrets."windscribe_ci_${vpn}_auth" = { };

  users.groups =
    lib.listToAttrs (map (s: lib.nameValuePair "ci-vm${toString s.index}" { }) slots)
    // {
      ci-cache = { };
    };
  users.users =
    lib.listToAttrs (
      map (
        s:
        lib.nameValuePair "ci-vm${toString s.index}" {
          isSystemUser = true;
          group = "ci-vm${toString s.index}";
          extraGroups = [ "kvm" ];
        }
      ) slots
    )
    // {
      ci-cache = {
        isSystemUser = true;
        group = "ci-cache";
      };
    };

  # ── Tunnel ────────────────────────────────────────────────────────────────
  # Takes no routes or DNS from the server, so vista's own traffic is
  # untouched; the up script puts the tunnel in table 177 only.
  services.openvpn.servers.ci = {
    autoStart = true;
    updateResolvConf = false;
    config = ''
      config ${config.sops.secrets."windscribe_ci_${vpn}_ovpn".path}
      dev tunci
      dev-type tun
      route-nopull
      pull-filter ignore "dhcp-option"
      pull-filter ignore "block-outside-dns"
      user nobody
      group nogroup
    '';
    authUserPass = config.sops.secrets."windscribe_ci_${vpn}_auth".path;
    up = "ip route replace default dev $dev table ${toString table}";
  };

  # Table 177 for everything the VMs send, ending in the killswitch. Rules
  # match by incoming tap, so the host's own traffic never uses the table.
  systemd.services.ci-net = {
    description = "CI VM routing: table ${toString table} and the cache address";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ip addr replace ${ci.cacheAddr}/32 dev lo
      ip route replace unreachable default metric 4294967295 table ${toString table}
    ''
    + lib.concatMapStrings (s: ''
      ip rule del iif ${s.tap} lookup ${toString table} 2>/dev/null || true
      ip rule add iif ${s.tap} lookup ${toString table} priority 100
    '') slots;
    preStop = lib.concatMapStrings (s: ''
      ip rule del iif ${s.tap} lookup ${toString table} 2>/dev/null || true
    '') slots;
  };

  # ── Firewall ──────────────────────────────────────────────────────────────
  # raw PREROUTING runs before conntrack and before Docker's DNAT, so nothing
  # published by a container here is reachable from a VM either.
  #
  # The CI chains deliberately outlive `systemctl stop firewall` (no
  # extraStopCommands): a VM that is running stays fenced in. A start or reload
  # rebuilds each chain without a moment where it is empty: fill a new copy,
  # hook it in first, then unhook and drop the old one.
  networking.firewall.extraCommands = ''
    ci_chain() { # table chain rules-fn hook match...
      t=$1 c=$2 fill=$3 hook=$4
      shift 4
      iptables -t "$t" -N "$c-new" 2>/dev/null || iptables -t "$t" -F "$c-new"
      "$fill" "$t" "$c-new"
      iptables -t "$t" -I "$hook" 1 "$@" -j "$c-new"
      while iptables -t "$t" -D "$hook" "$@" -j "$c" 2>/dev/null; do :; done
      iptables -t "$t" -F "$c" 2>/dev/null || true
      iptables -t "$t" -X "$c" 2>/dev/null || true
      iptables -t "$t" -E "$c-new" "$c"
    }

    ci_raw_rules() {
      # Each tap may only send from its own guest address: no slot can
      # speak for the other one.
    ${
      lib.concatMapStrings (
        s: "  iptables -t \"$1\" -A \"$2\" -i ${s.tap} ! -s ${s.guestIp} -j DROP\n"
      ) slots
    }  iptables -t "$1" -A "$2" -d ${ci.cacheAddr} -p tcp --dport ${toString ci.cachePort} -j RETURN
      iptables -t "$1" -A "$2" -d ${privateRanges} -j DROP
    }
    ci_in_rules() {
      iptables -t "$1" -A "$2" -d ${ci.cacheAddr} -p tcp --dport ${toString ci.cachePort} -j ACCEPT
      iptables -t "$1" -A "$2" -j DROP
    }
    ci_fwd_rules() {
      iptables -t "$1" -A "$2" -o tunci -j ACCEPT
      iptables -t "$1" -A "$2" -j DROP
    }
    ci_fwd_in_rules() {
      iptables -t "$1" -A "$2" -i tunci -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
      iptables -t "$1" -A "$2" -j DROP
    }

    ci_chain raw ci-raw ci_raw_rules PREROUTING -i ci+
    ci_chain filter ci-in ci_in_rules INPUT -i ci+
    ci_chain filter ci-fwd ci_fwd_rules FORWARD -i ci+
    ci_chain filter ci-fwd-in ci_fwd_in_rules FORWARD -o ci+
    ip6tables -t raw -C PREROUTING -i ci+ -j DROP 2>/dev/null || ip6tables -t raw -I PREROUTING 1 -i ci+ -j DROP

    iptables -t nat -C POSTROUTING -s 10.77.0.0/16 -o tunci -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s 10.77.0.0/16 -o tunci -j MASQUERADE
    iptables -t mangle -C FORWARD -o tunci -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
      || iptables -t mangle -A FORWARD -o tunci -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  '';

  # ── Docker Hub pull cache ─────────────────────────────────────────────────
  # Pull-only (a proxy registry refuses pushes), so a job can't poison it. It
  # fetches over vista's own line; only the VMs' traffic uses the tunnel.
  # The mountpoint has to exist before systemd builds the cache's sandbox, and
  # the mount has to be made outside that sandbox: its own unit, not an
  # ExecStartPre (a "+" ExecStartPre's mount did not reach the registry).
  systemd.tmpfiles.rules = [ "d ${cacheDir} 0700 ci-cache ci-cache -" ];
  systemd.services.ci-registry-cache-mount = {
    description = "Fixed-size disk for the CI Docker Hub cache";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe cacheMount;
      ExecStop = "${pkgs.util-linux}/bin/umount ${cacheDir}";
    };
  };
  systemd.services.ci-registry-cache = {
    description = "Docker Hub pull cache for the CI VMs";
    wantedBy = [ "multi-user.target" ];
    after = [
      "ci-net.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "ci-net.service" ];
    bindsTo = [ "ci-registry-cache-mount.service" ];
    serviceConfig = sandbox // {
      ExecStart = "${pkgs.distribution}/bin/registry serve ${cacheConfig}";
      User = "ci-cache";
      Group = "ci-cache";
      ReadWritePaths = [ cacheDir ];
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      Restart = "on-failure";
    };
  };

  # ── Job slots ─────────────────────────────────────────────────────────────
  systemd.services.ci-slot1 = slotUnit (builtins.elemAt slots 0);
  systemd.services.ci-slot2 = slotUnit (builtins.elemAt slots 1);
}
