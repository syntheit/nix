{
  lib,
  pkgs,
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

  # SSH on two ports, deliberately:
  #   22   — reachable only over tailscale0 (a trusted interface, so the
  #          firewall lets it through without an explicit allow).
  #   4040 — reachable from the public internet, as a SECOND way in whose
  #          failure domain is independent of tailscale.com. The NUC has no
  #          IPMI, so if tailscaled wedges or tailscale.com has an outage, the
  #          only remaining path would be someone physically at the colo. 4040
  #          rather than 22 purely to cut brute-force log noise — that is not a
  #          security control; the real controls are key-only auth, no root
  #          login, no passwords over the network, plus fail2ban below.
  # NB: this needs colobarn to allow inbound TCP 4040.
  services.openssh = {
    enable = true;
    openFirewall = false;
    ports = [
      22
      4040
    ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };
  # Only 4040 is opened to every interface; 22 stays tailscale-only via
  # trustedInterfaces above.
  networking.firewall.allowedTCPPorts = [ 4040 ];

  # Public SSH means continuous credential-stuffing traffic. Key-only auth
  # already makes that futile, but fail2ban keeps the journal readable and
  # drops the obvious floods.
  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
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

  # ── Tailscale self-heal ───────────────────────────────────────────────────
  # This box has no IPMI and may be moved between networks, so the thing that
  # must never happen is "tailscaled is wedged and nobody is on site". systemd
  # already restarts the daemon if it *exits*, but it does not notice the
  # failure mode that actually strands you: the process alive but the backend
  # stuck in NeedsLogin/Stopped after a network change or a DHCP flap.
  #
  # Deliberately conservative: it only acts when the backend is NOT Running,
  # so a healthy node is never touched, and it only bounces the service — it
  # never re-runs `tailscale up` or re-reads the authkey, so it cannot
  # re-register the node or change its identity.
  systemd.services.tailscale-selfheal = {
    description = "Restart tailscaled if the backend is not Running";
    after = [ "tailscaled.service" ];
    path = [
      pkgs.tailscale
      pkgs.jq
    ];
    serviceConfig.Type = "oneshot";
    script = ''
      state=$(tailscale status --json 2>/dev/null | jq -r '.BackendState' 2>/dev/null || echo Unknown)
      if [ "$state" = "Running" ]; then
        echo "tailscale backend Running — nothing to do"
        exit 0
      fi
      echo "tailscale backend is '$state' — restarting tailscaled"
      systemctl restart tailscaled.service
    '';
  };
  systemd.timers.tailscale-selfheal = {
    description = "Periodically check that tailscale is actually up";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      # First check shortly after boot, then every 5 min. Persistent so a box
      # that was powered off through a scheduled run still checks on wake.
      OnBootSec = "3min";
      OnUnitActiveSec = "5min";
      Persistent = true;
    };
  };

  # Allow remote deploys from vista/harbor (`nixos-rebuild --target-host`).
  # Without this, pushing a locally-built closure fails with "lacks a signature
  # by a trusted key", because only root is trusted by default and root SSH is
  # (correctly) disabled on this host.
  nix.settings.trusted-users = [
    "root"
    "@wheel"
  ];

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "26.05";
}
