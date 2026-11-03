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
#   - The hypervisor runs as the unprivileged ci-vm user in a systemd sandbox.
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

  cacheConfig = pkgs.writeText "ci-registry-cache.yml" (
    builtins.toJSON {
      version = "0.1";
      log.level = "info";
      storage = {
        filesystem.rootdirectory = "/var/lib/ci-registry-cache";
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
      User = "ci-vm";
      Group = "ci-vm";
      StateDirectory = "ci-vm/slot${toString s.index}";
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

  users.groups.ci-vm = { };
  users.users.ci-vm = {
    isSystemUser = true;
    group = "ci-vm";
    extraGroups = [ "kvm" ];
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
      pull-filter ignore "redirect-gateway"
      pull-filter ignore "route"
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
  networking.firewall.extraCommands = ''
    iptables -t raw -N ci-raw 2>/dev/null || iptables -t raw -F ci-raw
    iptables -t raw -A ci-raw -d ${ci.cacheAddr} -p tcp --dport ${toString ci.cachePort} -j RETURN
    iptables -t raw -A ci-raw -d 0.0.0.0/8,10.0.0.0/8,100.64.0.0/10,127.0.0.0/8,169.254.0.0/16,172.16.0.0/12,192.168.0.0/16,224.0.0.0/3 -j DROP
    iptables -t raw -C PREROUTING -i ci+ -j ci-raw 2>/dev/null || iptables -t raw -I PREROUTING 1 -i ci+ -j ci-raw
    ip6tables -t raw -C PREROUTING -i ci+ -j DROP 2>/dev/null || ip6tables -t raw -I PREROUTING 1 -i ci+ -j DROP

    iptables -N ci-in 2>/dev/null || iptables -F ci-in
    iptables -A ci-in -d ${ci.cacheAddr} -p tcp --dport ${toString ci.cachePort} -j ACCEPT
    iptables -A ci-in -j DROP
    iptables -C INPUT -i ci+ -j ci-in 2>/dev/null || iptables -I INPUT 1 -i ci+ -j ci-in

    iptables -N ci-fwd 2>/dev/null || iptables -F ci-fwd
    iptables -A ci-fwd -o tunci -j ACCEPT
    iptables -A ci-fwd -j DROP
    iptables -C FORWARD -i ci+ -j ci-fwd 2>/dev/null || iptables -I FORWARD 1 -i ci+ -j ci-fwd
    iptables -N ci-fwd-in 2>/dev/null || iptables -F ci-fwd-in
    iptables -A ci-fwd-in -i tunci -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A ci-fwd-in -j DROP
    iptables -C FORWARD -o ci+ -j ci-fwd-in 2>/dev/null || iptables -I FORWARD 1 -o ci+ -j ci-fwd-in

    iptables -t nat -C POSTROUTING -s 10.77.0.0/16 -o tunci -j MASQUERADE 2>/dev/null \
      || iptables -t nat -A POSTROUTING -s 10.77.0.0/16 -o tunci -j MASQUERADE
    iptables -t mangle -C FORWARD -o tunci -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null \
      || iptables -t mangle -A FORWARD -o tunci -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
  '';
  networking.firewall.extraStopCommands = ''
    iptables -t raw -D PREROUTING -i ci+ -j ci-raw 2>/dev/null || true
    ip6tables -t raw -D PREROUTING -i ci+ -j DROP 2>/dev/null || true
    iptables -D INPUT -i ci+ -j ci-in 2>/dev/null || true
    iptables -D FORWARD -i ci+ -j ci-fwd 2>/dev/null || true
    iptables -D FORWARD -o ci+ -j ci-fwd-in 2>/dev/null || true
  '';

  # ── Docker Hub pull cache ─────────────────────────────────────────────────
  # Pull-only (a proxy registry refuses pushes), so a job can't poison it. It
  # fetches over vista's own line; only the VMs' traffic uses the tunnel.
  systemd.services.ci-registry-cache = {
    description = "Docker Hub pull cache for the CI VMs";
    wantedBy = [ "multi-user.target" ];
    after = [
      "ci-net.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "ci-net.service" ];
    serviceConfig = sandbox // {
      ExecStart = "${pkgs.distribution}/bin/registry serve ${cacheConfig}";
      DynamicUser = true;
      StateDirectory = "ci-registry-cache";
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
