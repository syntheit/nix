{ config, ... }:

# raven's builds → the mini's native aarch64 builder VM (hosts/mini/linux-builder.nix).
#
# raven is aarch64-linux, the same as the mini's VM, so nothing needs emulating:
# this only moves the work off the phone, which compiles a lot per nixpkgs bump:
# nixos-avf builds a patched 6.1 kernel (avf.useGenericKernel is off), a patched
# systemd and four Rust guest agents, none of which is on cache.nixos.org, plus
# direnv (overlay) and the foyer package. All of that compiled inside the AVF VM,
# alongside the services it hosts (website, status page, foyer dashboard).
#
# max-jobs = 0: raven builds nothing itself. Leaving local builds on is not
# "remote with a fallback": nix sends a derivation to the builder only while
# one of its slots is free and builds the rest locally, and a nixpkgs bump
# makes systemd, the Rust agents, direnv and foyer ready at the same moment,
# so several of them would still build on the phone. The cost is that trivial
# derivations (unit files, /etc, the toplevel) make the ssh trip too.
#
# With the mini down, builds fail with "local builds are disabled (max-jobs =
# 0)". To build on the phone anyway, pass `--max-jobs auto` to nixos-rebuild
# or nix build; the daemon honours it from droid as well as root.
#
# Network path: identical to harbor's (see hosts/harbor/nix-builder.nix).
# raven's VM sits behind the phone's NAT rather than on the LAN, which doesn't
# matter here: it only makes outbound ssh over Tailscale to the mini's sshd
# (which listens on its Tailscale IP only), then hops to the VM on the mini's
# localhost:31022.
#
# Auth: the same builder key harbor and vista hold (sops mac_builder_ssh_key,
# copied into secrets/raven.yaml). Its public half is already authorized on
# daniel@mini (port-forwarding only) and in the guest, so the mini needs no
# change.

{
  sops.secrets.mac_builder_ssh_key = { mode = "0400"; }; # root-owned; read by nix-daemon

  nix.distributedBuilds = true;
  nix.settings = {
    builders-use-substitutes = true;
    max-jobs = 0;
  };

  nix.buildMachines = [
    {
      hostName = "mac-linux-builder";
      sshUser = "builder";
      sshKey = config.sops.secrets.mac_builder_ssh_key.path;
      protocol = "ssh-ng";
      systems = [ "aarch64-linux" ];
      # 2, not harbor's 4: slots are counted per client, so raven's jobs stack
      # on top of harbor's (and vista's) in the same 8 GiB guest, and harbor
      # saw OOM-killed builds at 8 concurrent jobs. harbor's 4 + raven's 2
      # stays under that. raven's heavy set (kernel, systemd, the Rust agents)
      # is only a handful of derivations, so 2 costs little.
      maxJobs = 2;
      speedFactor = 4;
      supportedFeatures = [ "kvm" "benchmark" "big-parallel" ];
      publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=";
    }
  ];

  # nix-daemon (root) runs `ssh mac-linux-builder`; same two hops as harbor.
  # The timeouts are new: with max-jobs = 0 every build waits on this
  # connection, so fail fast instead of hanging. ConnectTimeout also bounds
  # the ssh handshake, which covers the VM's known hang (port 31022 LISTENs but
  # never answers, see the watchdog in hosts/mini/linux-builder.nix), and
  # ServerAlive drops a connection that goes silent mid-build.
  programs.ssh.extraConfig = ''
    Host mac-linux-builder
      HostName localhost
      Port 31022
      User builder
      HostKeyAlias mac-linux-builder
      IdentityFile ${config.sops.secrets.mac_builder_ssh_key.path}
      ProxyJump mac-builder-jump
      ConnectTimeout 10
      ServerAliveInterval 15
      ServerAliveCountMax 3

    Host mac-builder-jump
      HostName 100.75.241.25
      User daniel
      IdentityFile ${config.sops.secrets.mac_builder_ssh_key.path}
      StrictHostKeyChecking accept-new
      ConnectTimeout 10
  '';
}
