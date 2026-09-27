{ lib, ... }:

# swift's aarch64-darwin builds → the mini's macOS (not its Linux VM; that one
# only builds aarch64-linux).
#
# swift is a fanless M3 Air; the mini is an always-on M4 with a fan. What swift
# compiles is whatever no binary cache has: nodejs when Hydra's darwin build
# lags, neovim, marksman, direnv, foyer, yabai and the small local tools. With
# this, the Nix daemon hands those to the mini whenever it can reach it.
#
# Local builds stay on (unlike raven's max-jobs = 0): away from Tailscale or
# with the mini off, ssh gives up after ConnectTimeout and nix builds here. The
# flip side: nix sends a derivation to the mini only while one of its 2 slots
# is free and builds the rest locally, so some builds still run on swift.
#
# Path: the Determinate nix-daemon runs as root and ssh's as daniel to the
# mini's sshd over Tailscale (it listens on its Tailscale IP only). On the
# mini, this key can only run `nix-daemon --stdio`, and daniel is a trusted
# Nix user there, which ssh-ng builders require (hosts/mini/default.nix).
#
# Key: /etc/nix/mini_builder_ed25519 was generated on swift and never leaves
# it; only its public half is in the repo. To replace it:
#   sudo ssh-keygen -t ed25519 -N "" -C "swift nix-daemon -> mini" -f /etc/nix/mini_builder_ed25519
# then swap the public key in hosts/mini/default.nix and rebuild the mini.
{
  # The daemon's ssh reads /etc/ssh/ssh_config, which includes ssh_config.d/*
  # (same mechanism as hosts/mini/linux-builder.nix). HostKeyAlias makes ssh
  # check the host key nix passes in (the machines line below) under this
  # alias rather than under the IP.
  environment.etc."ssh/ssh_config.d/100-mini-builder.conf".text = ''
    Host mini-builder
      HostName 100.75.241.25
      User daniel
      HostKeyAlias mini-builder
      IdentityFile /etc/nix/mini_builder_ed25519
      IdentitiesOnly yes
      ConnectTimeout 5
      ServerAliveInterval 15
      ServerAliveCountMax 3
  '';

  # Fields: URI systems sshKey maxJobs speedFactor supported mandatory pubHostKey.
  # Nix's default is `builders = @/etc/nix/machines` and Determinate's nix.conf
  # doesn't override it. 2 jobs, not the mini's 10 cores: it has 16 GiB and
  # its Linux builder VM holds 8 of them. The host key is the base64 of the
  # mini's /etc/ssh/ssh_host_ed25519_key.pub.
  environment.etc."nix/machines".text = ''
    ssh-ng://daniel@mini-builder aarch64-darwin /etc/nix/mini_builder_ed25519 2 1 apple-virt,benchmark,big-parallel,nixos-test - c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUlTSVdtU2dZUll3RnZXSmptM2gvemQrck00NklHaGFvVDRhSUZVYmZrL1g=
  '';

  # The mini fetches build inputs from the caches itself instead of swift
  # uploading them over Tailscale. Appended after common.nix's lines.
  environment.etc."nix/nix.custom.conf".text = lib.mkAfter ''
    builders-use-substitutes = true
  '';
}
