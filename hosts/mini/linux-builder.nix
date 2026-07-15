{ pkgs, ... }:

# Native aarch64-linux builder VM (QEMU + hvf), replicating what nix-darwin's
# nix.linux-builder module does — that module asserts `nix.enable`, which is
# off here because Determinate nix owns /etc/nix/nix.conf. The three pieces it
# would have wired up, wired by hand:
#
#   1. launchd daemon runs darwin.linux-builder's create-builder: generates
#      /etc/nix/builder_ed25519{,.pub} on first boot, then keeps a NixOS VM
#      (1 core / 3 GiB / 20 GiB qcow2 in /var/lib/linux-builder) listening on
#      ssh localhost:31022.
#   2. /etc/nix/machines registers the builder with the daemon. Nix's default
#      is `builders = @/etc/nix/machines` and Determinate's nix.conf doesn't
#      override `builders`, so no nix.conf change is needed.
#   3. /etc/ssh/ssh_config.d alias so ssh resolves the `linux-builder` host
#      (macOS's stock ssh_config includes ssh_config.d/*).
#
# `builders-use-substitutes = true` lives in /etc/nix/nix.custom.conf, the
# Determinate-designated file for manual settings (connect-timeout etc. are
# already there).
#
# The stock VM is 1 core / 3 GiB / 20 GiB; this mini idles most of the time,
# so give the builder most of the machine (10 cores / 16 GiB host). QEMU only
# faults guest RAM in as it's used and the qcow2 is sparse, so the idle cost
# is a mostly-sleeping QEMU process. NOTE: diskSize only applies when
# run-nixos-vm creates the image — to grow an existing builder, stop the
# daemon, delete /var/lib/linux-builder/nixos.qcow2, start it again (wipes
# the VM's build cache, nothing else).

let
  linux-builder = pkgs.darwin.linux-builder.override (old: {
    modules = (old.modules or [ ]) ++ [
      (
        { lib, ... }:
        {
          # the nix-builder-vm profile pins all three at normal priority
          virtualisation.cores = lib.mkForce 8;
          virtualisation.memorySize = lib.mkForce 8192;
          virtualisation.diskSize = lib.mkForce (100 * 1024);
        }
      )
    ];
  });
in
{
  system.activationScripts.preActivation.text = ''
    mkdir -p /var/lib/linux-builder
  '';

  launchd.daemons.linux-builder = {
    # The VM shares host CA certs via TMPDIR; macOS purges /tmp files idle for
    # 3+ days (sleeping laptop → vanished certs), so use /run instead.
    environment.NIX_SSL_CERT_FILE = "/etc/nix/macos-keychain.crt";
    script = ''
      export TMPDIR=/run/org.nixos.linux-builder USE_TMPDIR=1
      rm -rf $TMPDIR
      mkdir -p $TMPDIR
      trap "rm -rf $TMPDIR" EXIT
      ${linux-builder}/bin/create-builder
    '';
    serviceConfig = {
      KeepAlive = true;
      RunAtLoad = true;
      WorkingDirectory = "/var/lib/linux-builder";
    };
  };

  environment.etc."ssh/ssh_config.d/100-linux-builder.conf".text = ''
    Host linux-builder
      User builder
      Hostname localhost
      HostKeyAlias linux-builder
      Port 31022
      IdentityFile /etc/nix/builder_ed25519
  '';

  # Fields: URI systems sshKey maxJobs speedFactor supported mandatory pubHostKey.
  # maxJobs matches the VM's cores. The host key is baked into the stock
  # VM image; this is the same base64 blob nix-darwin's module hardcodes.
  environment.etc."nix/machines".text = ''
    ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 8 1 kvm,benchmark,big-parallel - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=
  '';
}
