# One CI runner VM (one slot). Booted fresh for every GitHub Actions job by
# ./default.nix and treated as hostile: no ssh, no logins, no host paths, and
# no secret beyond the single-use runner config on its jit disk.
#
# The store is a read-only erofs image of this closure only (not the host's
# /nix/store, which could hold things a job should not read). The work disk is
# blank on every boot. The job itself runs in GitHub's runner image
# (./job.sh), so the workflows see an Ubuntu userland, not NixOS.
{
  lib,
  pkgs,
  slot,
  ci,
  ...
}:
{
  system.stateVersion = "25.05";

  microvm = {
    hypervisor = "cloud-hypervisor";
    inherit (ci) vcpu;
    mem = ci.memMiB;
    # Free page reporting: memory the guest frees goes back to vista.
    balloon = true;
    shares = [ ];
    storeOnDisk = true;
    storeDiskType = "erofs";
    interfaces = [
      {
        type = "tap";
        id = slot.tap;
        inherit (slot) mac;
      }
    ];
    volumes = [
      {
        # Created blank by microvm-run; the slot deletes it after every job.
        image = "work.img";
        label = "ciwork";
        mountPoint = "/var/lib/ci";
        size = ci.workDiskMiB;
        # O_DIRECT: the job's writes don't fill vista's page cache, which
        # counts against the slot's MemoryMax and pushed the VM into swap.
        direct = true;
      }
      {
        # Written by the slot before boot: runner config and self-check targets.
        # ext4 labelled cijit by the slot's mkfs; job.sh mounts it by label.
        image = "jit.img";
        mountPoint = null;
        readOnly = true;
        autoCreate = false;
        size = 16;
      }
    ];
  };

  networking = {
    hostName = "vista-ci-${toString slot.index}";
    useDHCP = false;
    useNetworkd = true;
    enableIPv6 = false;
    # Public resolvers, reached through the tunnel like everything else.
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
  };
  services.resolved.enable = false;
  systemd.network.networks."10-ci" = {
    matchConfig.MACAddress = slot.mac;
    address = [ "${slot.guestIp}/30" ];
    gateway = [ slot.hostIp ];
    networkConfig = {
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
  };

  users.mutableUsers = false;
  users.users.root.hashedPassword = "!";
  # Nobody logs in, by design.
  users.allowNoPasswordLogin = true;
  services.openssh.enable = false;
  systemd.services."serial-getty@ttyS0".enable = false;
  nix.enable = false;

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      data-root = "/var/lib/ci/docker";
      # Docker Hub pulls go through vista's cache; the tunnel's shared exit IP
      # would hit Docker Hub's anonymous rate limit.
      registry-mirrors = [ "http://${ci.cacheAddr}:${toString ci.cachePort}" ];
      insecure-registries = [ "${ci.cacheAddr}:${toString ci.cachePort}" ];
      ipv6 = false;
      dns = [
        "1.1.1.1"
        "9.9.9.9"
      ];
    };
  };
  systemd.services.docker.unitConfig.RequiresMountsFor = [ "/var/lib/ci" ];

  systemd.services.ci-job = {
    description = "Isolation self-check, then one GitHub Actions job";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    path = with pkgs; [
      coreutils
      curl
      docker
      systemd
      util-linux
    ];
    serviceConfig.StandardOutput = "journal+console";
    serviceConfig.StandardError = "journal+console";
    script = builtins.readFile ./job.sh;
  };
}
