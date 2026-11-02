# CLI release drop: mini's pipeline (hosts/mini/deus-cli-release.nix) rsyncs
# the signed deus CLI binaries and manifest into /var/lib/deus-cli-release over
# ssh. The key is forced to rrsync, write-only and confined to that directory;
# no shell commands, no forwarding, no pty. rrsync still needs a login shell to
# exec the forced command. sshd has no AllowUsers/AllowGroups on vista, so
# nothing else to open.
# -no-del refuses --delete*/--remove*; -munge neuters symlinks (review P2-5).
# --delay-updates (used by the pipeline) is allowed by rrsync 3.5.0.
{ lib, pkgs, ... }:
let
  # Public half of mini's ~/.ssh/deus-release_ed25519.
  deusReleasePubkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ2sykW4XQ5qMunHtig/T+0rinOFba73jQ/piLOisBaO deus-release@mini";
in
{
  users.groups.deus-release = { };
  users.users.deus-release = {
    isSystemUser = true;
    group = "deus-release";
    home = "/var/empty";
    shell = "${pkgs.bash}/bin/bash";
    openssh.authorizedKeys.keys = lib.optional (deusReleasePubkey != null)
      ''restrict,command="${pkgs.rrsync}/bin/rrsync -wo -no-del -munge /var/lib/deus-cli-release" ${deusReleasePubkey}'';
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/deus-cli-release 0755 deus-release deus-release -"
  ];
}
