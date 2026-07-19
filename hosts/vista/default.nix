{
  pkgs,
  lib,
  vars,
  ...
}:
{
  # Headless server: deliberately does NOT import ../../desktop (Hyprland,
  # greetd, Steam, the full font set). vista runs console-only and is managed
  # over SSH/Tailscale. Its slim package set lives in ./home.nix (it does NOT
  # import the full ./home kitchen sink either), and affinity is gated off in
  # system/default.nix.
  imports = [
    ./hardware.nix
    ./disko.nix
    ./secrets.nix
    ./invidious.nix
    ./nix-builder.nix
    ../../system
    ../../services
  ];

  networking.hostName = "vista";
  networking.useDHCP = lib.mkDefault true;

  # Passwordless sudo for the wheel user — matches mantle/harbor/conduit/fajita.
  security.sudo.wheelNeedsPassword = false;

  # ── Network / remote access ───────────────────────────────────────────────
  services.tailscale.enable = true;
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  # SSH: key-only. openFirewall=true keeps it reachable on the LAN for the
  # bootstrap phase (and it's a stationary box on a trusted home LAN). Tighten
  # to Tailscale-only later by flipping this to false — Tailscale traffic
  # already bypasses the firewall via trustedInterfaces above.
  services.openssh = {
    enable = true;
    openFirewall = true;
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
    # Initial console/sudo password so the box is usable on first boot. SSH is
    # key-only regardless. Change it after install with `passwd`.
    initialPassword = lib.mkDefault "vista";
  };

  # ── Clock / DNS resilience (T2 RTC comes up at 1970 every boot) ────────────
  # This MacBook's hardware clock reads the Unix epoch on every cold boot — a
  # known T2-under-Linux quirk (the RTC isn't persisted/read the way a PC's CMOS
  # clock is). A 1970 clock is normally self-healing once NTP syncs, but here it
  # deadlocks against our DNS stack:
  #
  #   wrong clock → every TLS cert is "not yet valid" → NextDNS DNS-over-TLS
  #   (system/default.nix, strict) can't handshake → ALL system DNS dies →
  #   systemd-timesyncd can't resolve the NTP *pool hostnames* → clock never
  #   gets corrected → tailscaled can't reach controlplane.tailscale.com (its
  #   HTTPS bootstrap also fails cert validation) → the box drops off Tailscale
  #   and is unreachable. (Diagnosed 2026-07-07: vista had been offline 22d.)
  #
  # Two independent breaks so a reboot can't re-enter the deadlock:
  #
  # 1) Sync time WITHOUT DNS. Pin NTP servers by IP (Google + Cloudflare
  #    anycast) so timesyncd sets a correct clock from a raw UDP/123 exchange —
  #    no name resolution, no TLS, works fine at 1970. This is the real fix.
  #    (cf. fajita's swclock-offset, which solves the same 1970 RTC problem
  #    from disk; NTP-by-IP is the network-side equivalent.)
  services.timesyncd.servers = [
    # Google Public NTP (time.google.com anycast)
    "216.239.35.0"
    "216.239.35.4"
    "216.239.35.8"
    "216.239.35.12"
    # Cloudflare NTP (time.cloudflare.com anycast)
    "162.159.200.1"
    "162.159.200.123"
  ];
  # Once the clock is sane and DNS is back, the normal pool is fine too.
  services.timesyncd.settings.Time.FallbackNTP = [
    "0.nixos.pool.ntp.org"
    "1.nixos.pool.ntp.org"
    "2.nixos.pool.ntp.org"
    "3.nixos.pool.ntp.org"
  ];

  # 2) Keep DNS alive during the brief boot window before timesyncd's first
  #    sync (and if the NTP IPs are ever unreachable). Downgrade DoT from strict
  #    to opportunistic ON THIS HOST ONLY: resolved still encrypts to NextDNS,
  #    but no longer requires a valid certificate, so a 1970 clock (or a blocked
  #    :853) transparently falls back instead of nuking resolution. Acceptable
  #    on a stationary home-LAN server; every other host keeps strict DoT.
  services.resolved.settings.Resolve.DNSOverTLS = lib.mkForce "opportunistic";

  system.stateVersion = "25.05";
}
