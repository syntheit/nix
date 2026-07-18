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

          # Auto-GC INSIDE the guest. The stock darwin.linux-builder ships NO gc
          # timer, so every fajita aarch64 rebuild piles up in the guest store
          # and the qcow2 grows toward its 100 GiB ceiling until the mini's APFS
          # container fills and the VM's /nix goes read-only (this is exactly
          # what wedged the builder 2026-07-18). Weekly GC keeping 14 days is the
          # real safety net. min-free/max-free make the daemon also GC when the
          # guest store gets low — but note the guest can't see the *host* APFS
          # running out, so it can't rely on that alone; the timer is primary.
          nix.gc = {
            automatic = true;
            dates = "weekly";
            options = "--delete-older-than 14d";
          };
          # The nix-builder-vm profile already pins min-free/max-free at normal
          # priority, so these need mkForce (same as the sizing options above).
          nix.settings = {
            min-free = lib.mkForce (1024 * 1024 * 1024); # 1 GiB
            max-free = lib.mkForce (5 * 1024 * 1024 * 1024); # 5 GiB
          };
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
      # Pin the builder identity. add-keys (inside create-builder) generates a
      # FRESH keypair whenever ./keys is empty — and the keys dir gets wiped by
      # disk-full recoveries and even darwin-rebuild switch (both observed
      # 2026-07-18). Every regeneration silently desyncs harbor's sops-pinned
      # copy of this key → "Permission denied" on all remote builds.
      # /etc/nix/builder_ed25519 is the canonical copy; reseed ./keys from it
      # (cwd is /var/lib/linux-builder) so add-keys never regenerates. A new
      # key can now only appear if BOTH copies are lost — if you ever rotate
      # it on purpose, update harbor's sops secret mac_builder_ssh_key too.
      if [ -f /etc/nix/builder_ed25519 ] && [ -f /etc/nix/builder_ed25519.pub ]; then
        mkdir -p keys
        cp -f /etc/nix/builder_ed25519 keys/builder_ed25519
        cp -f /etc/nix/builder_ed25519.pub keys/builder_ed25519.pub
        chmod 600 keys/builder_ed25519
        chmod 644 keys/builder_ed25519.pub
      fi
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
