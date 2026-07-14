# GNOME Shell Mobile session — applies the mobile overlay
# (packages/gnome-mobile) and configures a GNOME Wayland session: GDM +
# gnome-shell-mobile + mutter-mobile.
#
# Vendored/adapted from chuangzhu/nixpkgs-gnome-mobile (0BSD). Differences:
#   - logind power-key handling is left to the host (fajita owns it, with
#     SDM845 suspend fully disabled), so it is NOT set here.
#   - totem is not excluded (fajita installs it explicitly).
#
# REQUIRES a GNOME-49 nixpkgs base (flake input nixpkgs-gnome49) — the overlay
# pins verdre's mobile-shell-devel-49 sources and will not build on GNOME 50.
{ pkgs, ... }:
{
  nixpkgs.overlays = [ (import ../packages/gnome-mobile/overlay.nix) ];

  # Wayland-only GNOME session (no Xorg; XWayland is pulled in by GNOME itself).
  services.displayManager.gdm.enable = true;
  # REQUIRED for autologin: with two GNOME wayland sessions registered
  # (gnome, gnome-wayland) and no default, GDM autologin opens the PAM/Wayland
  # session but launches no desktop → drops to a getty tty. Pin the session.
  services.displayManager.defaultSession = "gnome";
  services.desktopManager.gnome = {
    enable = true;
    # Mobile model: one fullscreen app per workspace, created on demand.
    extraGSettingsOverrides = ''
      [org.gnome.mutter]
      dynamic-workspaces=true
    '';
    extraGSettingsOverridePackages = [ pkgs.mutter ];
  };

  # VT-foreground workaround. The mobile-nixos boot cmdline pins `console=tty2`,
  # so VT2 stays the foreground console. GDM launches its Wayland session on a
  # VT and VT_ACTIVATEs it, but on this device the activation doesn't stick —
  # the session stays inactive, so gnome-shell can't acquire DRM master and the
  # display drops to a getty tty. Hold the GDM session's VT in the foreground
  # through the startup window so gnome-shell wins the race and becomes DRM
  # master. (Confirmed fix; candidate for a cleaner upstream/mobile-nixos
  # solution — e.g. dropping console=tty2 or pinning GDM's VT.)
  systemd.services.gnome-mobile-vt-hold = {
    description = "Hold the GDM/GNOME session VT in foreground during startup (SDM845 console=tty2 workaround)";
    after = [ "display-manager.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gnome-mobile-vt-hold" ''
        set -u
        for i in $(seq 1 60); do
          vt=""
          for s in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $1}'); do
            svc=$(${pkgs.systemd}/bin/loginctl show-session "$s" -p Service --value 2>/dev/null)
            if [ "$svc" = "gdm-autologin" ]; then
              tty=$(${pkgs.systemd}/bin/loginctl show-session "$s" -p TTY --value 2>/dev/null)
              vt=$(printf '%s' "$tty" | ${pkgs.gnugrep}/bin/grep -o '[0-9]*')
              break
            fi
          done
          if [ -n "$vt" ]; then
            ${pkgs.kbd}/bin/chvt "$vt" 2>/dev/null || true
            # once gnome-shell holds the VT, a couple more switches then stop
            if ${pkgs.procps}/bin/pgrep -x gnome-shell >/dev/null 2>&1; then
              ${pkgs.coreutils}/bin/sleep 1
              ${pkgs.kbd}/bin/chvt "$vt" 2>/dev/null || true
              exit 0
            fi
          fi
          ${pkgs.coreutils}/bin/sleep 0.5
        done
      '';
    };
  };

  # Boot to the lock screen. Autologin (needed for a reliable boot on this
  # device) would otherwise open straight to an unlocked desktop. Lock the
  # session as soon as the shell is up; unlocking with the user password also
  # unlocks the login keyring, so there's no separate keyring prompt.
  systemd.user.services.gnome-mobile-lock-on-start = {
    description = "Lock the GNOME session on login (boot to the lock screen)";
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "gnome-mobile-lock-on-start" ''
        # Wait for gnome-shell's ScreenSaver interface to appear, then lock.
        for i in $(${pkgs.coreutils}/bin/seq 1 30); do
          if ${pkgs.glib}/bin/gdbus call --session \
              --dest org.gnome.ScreenSaver \
              --object-path /org/gnome/ScreenSaver \
              --method org.gnome.ScreenSaver.SetActive true >/dev/null 2>&1; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
      '';
    };
  };

  # GNOME drives IBus directly over its D-Bus API; these envvars must NOT be set
  # or the on-screen keyboard won't pop up. This is the exact inverse of Phosh,
  # which needed GTK_IM_MODULE=wayland — do not reintroduce that here.
  environment.extraInit = ''
    unset GTK_IM_MODULE QT_IM_MODULE XMODIFIERS
  '';

  # GNOME default apps that aren't mobile-friendly yet (fajita ships adaptive
  # replacements: papers, resources/mission-center, snapshot, etc.).
  environment.gnome.excludePackages = with pkgs; [
    simple-scan
    gnome-system-monitor
    yelp
    gnome-music
    baobab
    evince
    gnome-connections
    gnome-tour
  ];
}
