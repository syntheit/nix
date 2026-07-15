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
# The VM defaults are modest. Overriding virtualisation.cores/memorySize means
# rebuilding the VM image itself for aarch64-linux — bootstrappable only once
# this default builder is already running. If it turns out to be too slow for
# Mimick's codecs, bump it in two phases (or append `-smp N -m M` via
# QEMU_OPTS in the daemon script, which the run-nixos-vm runner respects).

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
      ${pkgs.darwin.linux-builder}/bin/create-builder
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
  # maxJobs 1 matches the VM's single core. The host key is baked into the stock
  # VM image; this is the same base64 blob nix-darwin's module hardcodes.
  environment.etc."nix/machines".text = ''
    ssh-ng://builder@linux-builder aarch64-linux /etc/nix/builder_ed25519 1 1 kvm,benchmark,big-parallel - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUpCV2N4Yi9CbGFxdDFhdU90RStGOFFVV3JVb3RpQzVxQkorVXVFV2RWQ2Igcm9vdEBuaXhvcwo=
  '';
}
