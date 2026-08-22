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
        held=0
        # Give the autologin session the foreground VT only until its shell has
        # started.  `pgrep -x gnome-shell` never matched the Nix wrapper on
        # fajita, so the old loop kept switching VTs for its full lifetime.
        # That starved GDM's greeter of its VT; its launch worker then could not
        # exit and GDM crashed into an autologin/session-manager restart loop.
        # A full command-line match handles both the wrapper and the real shell.
        for i in $(seq 1 60); do
          vt=""
          for s in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $1}'); do
            svc=$(${pkgs.systemd}/bin/loginctl show-session "$s" -p Service --value 2>/dev/null)
            if [ "$svc" = "gdm-autologin" ]; then
              tty=$(${pkgs.systemd}/bin/loginctl show-session "$s" -p TTY --value 2>/dev/null)
              uid=$(${pkgs.systemd}/bin/loginctl show-session "$s" -p User --value 2>/dev/null)
              vt=$(printf '%s' "$tty" | ${pkgs.gnugrep}/bin/grep -o '[0-9]*')
              break
            fi
          done
          if [ -n "$vt" ]; then
            ${pkgs.kbd}/bin/chvt "$vt" 2>/dev/null || true
            # Once the user's shell has acquired the VT, reinforce it once and
            # get out before GDM starts its separate greeter session.
            if ${pkgs.procps}/bin/pgrep -u "$uid" -f '/bin/gnome-shell' >/dev/null 2>&1; then
              ${pkgs.coreutils}/bin/sleep 1
              ${pkgs.kbd}/bin/chvt "$vt" 2>/dev/null || true
              exit 0
            fi
            # Never keep stealing VTs indefinitely if the shell fails to
            # start.  Thirty half-second attempts cover the device's
            # normal shell startup while ending well before GDM's greeter.
            held=$((held + 1))
            if [ "$held" -ge 30 ]; then
              exit 0
            fi
          fi
          ${pkgs.coreutils}/bin/sleep 0.5
        done
      '';
    };
  };

  # GDM sometimes starts its standalone greeter when boot completion releases
  # Plymouth, even though the autologin session has already registered and is
  # correctly locked by its own Shell.  On fajita that greeter takes tty1 and
  # leaves the real mobile lock screen alive but invisible on tty2.  Do not try
  # to predict the launch with another delay: observe the actual state, let the
  # greeter become active, then return the foreground to the locked user session.
  # Keep observing for the whole boot window because an incompletely initialized
  # greeter can reclaim tty1 after the first correction.  This starts as a
  # Type=simple service, so it does not hold up graphical.target while monitoring.
  systemd.services.gnome-mobile-restore-locked-vt = {
    description = "Restore the locked GNOME mobile session if GDM steals the boot VT";
    after = [ "display-manager.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "gnome-mobile-restore-locked-vt" ''
        set -u
        restorations=0
        for i in $(${pkgs.coreutils}/bin/seq 1 120); do
          user_session=""
          greeter_active=0

          for session in $(${pkgs.systemd}/bin/loginctl list-sessions --no-legend 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $1}'); do
            service=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Service --value 2>/dev/null)
            if [ "$service" = "gdm-autologin" ]; then
              user_session="$session"
            fi

            class=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Class --value 2>/dev/null)
            active=$(${pkgs.systemd}/bin/loginctl show-session "$session" -p Active --value 2>/dev/null)
            if [ "$class" = "greeter" ] && [ "$active" = "yes" ]; then
              greeter_active=1
            fi
          done

          if [ -n "$user_session" ] && [ "$greeter_active" -eq 1 ]; then
            locked=$(${pkgs.systemd}/bin/loginctl show-session "$user_session" -p LockedHint --value 2>/dev/null)
            if [ "$locked" = "yes" ]; then
              echo "GDM greeter stole the boot VT; activating locked session $user_session"
              ${pkgs.systemd}/bin/loginctl activate "$user_session" || true
              ${pkgs.coreutils}/bin/sleep 0.5
              active=$(${pkgs.systemd}/bin/loginctl show-session "$user_session" -p Active --value 2>/dev/null)
              if [ "$active" = "yes" ]; then
                restorations=$((restorations + 1))
                echo "Locked GNOME mobile session $user_session restored to foreground"
              fi
            fi
          fi

          ${pkgs.coreutils}/bin/sleep 0.5
        done

        if [ "$restorations" -eq 0 ]; then
          echo "No locked-session/GDM-greeter VT steal observed during boot window"
        else
          echo "Boot VT settled on the locked GNOME mobile session after $restorations restoration(s)"
        fi
      '';
    };
  };

  # Autologin is required for a reliable Wayland/DRM session on fajita, but it
  # must still boot locked.  The mobile Shell patch awaits GDM RegisterSession,
  # installs its own lock, and only then enables power-key handling.  Keeping
  # the handshake inside Shell avoids the external user-unit timing race that
  # intermittently switched the foreground VT to GDM's standalone greeter.
  environment.sessionVariables.GNOME_MOBILE_LOCK_ON_START = "1";

  # GNOME drives IBus directly over its D-Bus API; these envvars must NOT be set
  # or the on-screen keyboard won't pop up. This is the exact inverse of Phosh,
  # which needed GTK_IM_MODULE=wayland — do not reintroduce that here.
  environment.extraInit = ''
    unset GTK_IM_MODULE QT_IM_MODULE XMODIFIERS
  '';

  # GNOME default apps that aren't mobile-friendly yet (fajita ships adaptive
  # replacements: papers, resources/mission-center, snapshot, etc.).
  # gnome-console is excluded because Ptyxis is the configured terminal; having
  # two terminal entries in the app drawer is confusing on a phone-sized screen.
  environment.gnome.excludePackages = with pkgs; [
    gnome-console
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
