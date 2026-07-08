{
  pkgs,
  lib,
  vars,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../system
    ../../services
    ../../desktop
  ];

  networking.hostName = "vista";
  networking.useDHCP = lib.mkDefault true;

  # Lean HTPC: drop Steam (enabled by the shared desktop module). vista's slim
  # package set lives in ./home.nix (it does NOT import the full ./home kitchen
  # sink), and affinity is gated off in system/default.nix.
  programs.steam.enable = lib.mkForce false;

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
  #    on a stationary home-LAN HTPC; every other host keeps strict DoT.
  services.resolved.settings.Resolve.DNSOverTLS = lib.mkForce "opportunistic";

  # ── Phone control (KDE Connect) ───────────────────────────────────────────
  # Media control / clipboard / notifications / file transfer work out of the
  # box; opens the required 1714-1764 TCP+UDP range. NOTE: using the phone as a
  # remote *mouse/keyboard* under Hyprland additionally needs hypr-kdeconnect-fix
  # — a later customization step once the desktop is dialed in.
  programs.kdeconnect.enable = true;

  # Remote input (phone as touchpad/keyboard) needs a RemoteDesktop portal
  # backend, which xdph lacks. Route RemoteDesktop to the hypr-kdeconnect bridge.
  # The bridge package itself is installed in daniel's home profile (see
  # ./home.nix) — that's the dir the NixOS xdg-desktop-portal frontend actually
  # scans (NIX_XDG_DESKTOP_PORTAL_DIR points at the user profile, not the system
  # one) — and its daemon is started from the Hyprland session (see hyprland.nix).
  xdg.portal.config.common."org.freedesktop.impl.portal.RemoteDesktop" = "hypr-kdeconnect";

  # ── Boot straight to the TV ───────────────────────────────────────────────
  # The shared desktop module sets greetd's default_session (tuigreet). Add an
  # initial_session so the box autologins into Hyprland unattended at boot; if
  # the session ever exits it falls back to the tuigreet greeter.
  services.greetd.settings.initial_session = {
    command = "Hyprland";
    user = vars.user.name;
  };

  system.stateVersion = "25.05";
}
