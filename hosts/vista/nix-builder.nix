{ config, ... }:

# aarch64-linux builds → the mini's native builder VM (hosts/mini/linux-builder.nix).
#
# harbor's own system is x86_64; the only aarch64 work here is building fajita
# (Mobile NixOS, OnePlus 6T). That used to run under qemu-user binfmt, which
# crawls and outright FAILS on heavy vendored-C / LTO builds (mimick's image
# codecs, tdlib — qemu-user chokes spawning the parallel cc jobs). Instead we
# offload every aarch64-linux derivation to the mini's always-on aarch64 VM
# over Tailscale — native, no emulation.
#
# binfmt aarch64 is deliberately NOT enabled here (see hardware.nix): with it,
# nix schedules aarch64 builds on localhost via qemu whenever it has a free
# slot — exactly the path we're trying to avoid. Without a local aarch64
# builder, nix routes every aarch64 derivation to the mini. Trade-off: fajita
# can only be built while the mini is reachable (it idles always-on). To build
# offline, re-enable binfmt.emulatedSystems in hardware.nix temporarily.
#
# Network path: the VM's SSH is behind qemu slirp on the mini's localhost:31022.
# Reaching that port DIRECTLY from harbor over Tailscale fails — slirp's
# userspace NAT doesn't clamp MSS, so the 1280-byte Tailscale MTU kills the SSH
# key-exchange packets ("timed out during banner exchange"). So we ssh through
# the mini's real sshd (port 22, rock-solid over Tailscale) and hop to
# localhost:31022 from there — a reliable loopback→slirp hop. That's the
# ProxyJump below.
#
# Auth: one key does both hops. The VM's builder key (generated on the mini by
# create-builder) is the sops secret mac_builder_ssh_key; harbor holds the
# private half, and its public half is authorized on daniel@mini
# (port-forwarding only — see hosts/mini/default.nix) for the jump, and on the
# guest for the build connection. publicHostKey is the VM's baked-in ed25519
# host key — the same base64 blob hardcoded in hosts/mini/linux-builder.nix.

{
  sops.secrets.mac_builder_ssh_key = { mode = "0400"; }; # root-owned; read by nix-daemon

  nix.distributedBuilds = true;
  nix.settings.builders-use-substitutes = true;

  nix.buildMachines = [
    {
      hostName = "mac-linux-builder";
      sshUser = "builder";
      sshKey = config.sops.secrets.mac_builder_ssh_key.path;
      protocol = "ssh-ng";
      systems = [ "aarch64-linux" ];
      maxJobs = 8;
      speedFactor = 4;
      supportedFeatures = [ "kvm" "benchmark" "big-parallel" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";
    }
  ];

  # nix-daemon (root) runs `ssh mac-linux-builder`; resolve it here. The builder
  # is reached by jumping through the mini's real sshd (mac-builder-jump), then
  # connecting to localhost:31022 on the mini → the VM. Same builder key both
  # hops. HostKeyAlias keeps the VM's host key matched to nix's publicHostKey
  # regardless of the localhost target.
  programs.ssh.extraConfig = ''
    Host mac-linux-builder
      HostName localhost
      Port 31022
      User builder
      HostKeyAlias mac-linux-builder
      IdentityFile ${config.sops.secrets.mac_builder_ssh_key.path}
      ProxyJump mac-builder-jump

    Host mac-builder-jump
      HostName 100.75.241.25
      User daniel
      IdentityFile ${config.sops.secrets.mac_builder_ssh_key.path}
      StrictHostKeyChecking accept-new
  '';
}
