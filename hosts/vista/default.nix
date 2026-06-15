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
