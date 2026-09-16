{
  lib,
  vars,
  ...
}:
{
  # Colo NUC — phase 1 scope only: boot, get on the network, be reachable.
  # No fleet role yet (no wg0 mesh, no Headscale tailnet, no secrets/sops) —
  # see plans/ for the eventual "transplant the fleet control plane here"
  # follow-up. Deliberately does NOT import ../../desktop (headless, no GUI),
  # matching vista's pattern.
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../system
    ../../services
  ];

  networking.hostName = "nuc";
  networking.useDHCP = lib.mkDefault true;

  # Real Tailscale (tailscale.com, the existing personal "syntheit" tailnet) —
  # NOT the fleet's self-hosted Headscale, NOT the wg0 mesh. Same "own
  # out-of-band tailnet, kept separate from whatever fleet role this box ends
  # up with" pattern vista/harbor already use for their own tailscale0.
  #
  # authKeyFile deliberately points outside the Nix store: it's a plain file
  # placed on disk by `disko-install --extra-files` at install time (copied
  # from the live installer ISO, which itself never commits the raw key into
  # this git repo — see the nuc-installer ISO module in flake.nix). Matches
  # the "manually placed for now, sops later" precedent conduit's original wg
  # key used (hosts/conduit/default.nix).
  #
  # NB: /var/lib, NOT /etc. NixOS's /etc activation owns that whole tree and
  # deletes files it doesn't declare — verified the hard way in the QEMU
  # rehearsal, where a key installed to /etc/tailscale-authkey was removed
  # during activation ("removing obsolete symlink") and the installed system
  # came up unable to join the tailnet. On a colo box with no out-of-band
  # console that failure mode is unrecoverable, hence the explicit path.
  services.tailscale = {
    enable = true;
    authKeyFile = "/var/lib/tailscale-authkey";
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  users.users."${vars.user.name}" = {
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej daniel@matv.io"
    ];
    # Console-login fallback, same idea as vista's initialPassword. SSH here is
    # key-only AND firewalled to tailscale0, so without a password there is no
    # way into this box at all if tailscaled fails to come up (expired/revoked
    # authkey, a colo network that blocks the join) — and the colo has no IPMI.
    # That combination is an unrecoverable brick, so keep a password that works
    # on a directly-attached keyboard+HDMI. CHANGE IT WITH `passwd` AFTER
    # BRING-UP — it is a bootstrap credential, not a permanent one.
    initialPassword = lib.mkDefault "tech123";
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.05";
}
