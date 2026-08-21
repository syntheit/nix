{ pkgs, lib, ... }:
# Declarative PWAs ("install site as app") for fajita.
#
# Firefox has no standalone-app-window mode (Mozilla dropped SSB years ago), and
# Epiphany web-apps are a version-fragile generated profile hash that doesn't
# reproduce cleanly in Nix. Chromium `--app=` is the robust declarative path: a
# single stable .desktop entry → frameless app window, own grid icon, and an
# isolated cookie jar per app (`--user-data-dir`) so multiple logins coexist.
#
# Adding one is a single `mkPwa { ... }` line below. Firefox stays the
# browse-anything browser; these are the tap-an-icon app-ified sites.
let
  browser = "${pkgs.chromium}/bin/chromium";

  mkPwa =
    {
      id, # slug: window class, profile dir, desktop-file name
      name, # visible app name
      url,
      icon ? "web-browser", # freedesktop icon name, or a path to a PNG we vendor later
      comment ? name,
      categories ? [ "Network" ],
      # profile: share one cookie jar between PWAs (e.g. all-Google → log in
      # once). Caveat: apps sharing a profile share one Chromium process, and
      # the process takes the --class of whichever app launched FIRST — the
      # shell may group their windows under that first app's icon.
      profile ? id,
      # dsf: force Chromium's device-scale-factor (a string, e.g. "1.3"). Only for
      # DESKTOP-ONLY sites with no mobile layout (Slack, WhatsApp): a value < the
      # compositor's 2.5 widens the CSS viewport so the site serves its full
      # desktop layout, scaled down to fit and pinch-zoomable. CSS width ≈
      # 1080 ÷ dsf (2.5→432px mobile, 1.3→~830px tablet, 1.0→1080px full desktop).
      # Leave null for responsive apps — forcing it there breaks their mobile UI.
      dsf ? null,
      # extraArgs: list of additional Chromium command-line flags for this PWA only.
      # e.g. [ "--enable-features=OverlayScrollbar" ]
      extraArgs ? [ ],
      # startFullscreen: launch in fullscreen so the Chromium CSD title bar is
      # hidden. On GNOME/Wayland the only way to suppress the client-drawn title
      # bar without compositor cooperation is a fullscreen Wayland surface.
      startFullscreen ? false,
    }:
    let
      launcher = pkgs.writeShellScript "pwa-${id}" ''
        exec ${browser} \
          --app=${lib.escapeShellArg url} \
          --class=pwa-${id} \
          --user-data-dir="$HOME/.local/share/pwa/${profile}" \
          --ozone-platform-hint=auto \
          ${lib.optionalString (dsf != null) "--force-device-scale-factor=${dsf} "}\
          ${lib.optionalString startFullscreen "--start-fullscreen "}\
          ${lib.concatStringsSep " " extraArgs}${lib.optionalString (extraArgs != [ ]) " "}"$@"
      '';
    in
    pkgs.makeDesktopItem {
      name = "pwa-${id}";
      desktopName = name;
      comment = comment;
      exec = "${launcher} %U";
      inherit icon categories;
      startupWMClass = "pwa-${id}";
    };

  pwas = [
    # ─── Self-hosted / hosted PWAs ───────────────────────────────────────────
    # Linkding + Memos PWAs dropped — replaced by the native anchorage (Linkding)
    # and jotter (Memos) GTK apps in systemPackages.
    (mkPwa {
      id = "retrospend";
      name = "Retrospend";
      url = "https://retrospend.app/dashboard";
      comment = "Expense tracker";
      icon = ./retrospend-icon.png;
    })
  ];
in
{
  environment.systemPackages = pwas;

  # Enterprise policy (/etc/chromium/policies/managed) — applies to every
  # Chromium instance regardless of --user-data-dir, so all PWAs get it.
  # uBlock Origin Lite (MV3; full uBO is MV2-dead in current Chromium).
  # Installs from the Web Store on each profile's first launch.
  programs.chromium = {
    enable = true;
    extensions = [ "ddkjiahejlhfcafbddmgiahcphecmpfh" ]; # uBlock Origin Lite
  };
}
