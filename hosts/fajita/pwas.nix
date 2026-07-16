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
    # ─── Chromium-required ───────────────────────────────────────────────────
    (mkPwa {
      id = "gmaps";
      name = "Google Maps";
      url = "https://maps.google.com/";
      comment = "Google Maps (needs Chromium for vector maps)";
      profile = "google"; # shared Google login with gvoice
    })

    # ─── Chat / comms ────────────────────────────────────────────────────────
    # Slack & WhatsApp have no mobile web layout — force a desktop-width viewport
    # (scaled down, pinch-zoomable) instead of a cramped/broken narrow one. Tune
    # dsf lower for more desktop / higher toward mobile once tested on the phone.
    (mkPwa {
      id = "slack";
      name = "Slack";
      url = "https://app.slack.com/client";
      dsf = "1.3";
    })
    (mkPwa {
      id = "telegram";
      name = "Telegram";
      url = "https://web.telegram.org/k/";
    })
    (mkPwa {
      id = "gvoice";
      name = "Google Voice";
      url = "https://voice.google.com/u/0/messages";
      profile = "google"; # shared Google login with gmaps
    })
    # Stopgap for WhatsApp — the better long-term answer is a mautrix-whatsapp
    # bridge on your server surfaced through Fractal. Web logs out periodically.
    (mkPwa {
      id = "whatsapp";
      name = "WhatsApp";
      url = "https://web.whatsapp.com/";
      dsf = "1.3";
    })

    # ─── Finance (low priority — "deal with it / web") ───────────────────────
    (mkPwa {
      id = "yahoo-finance";
      name = "Yahoo Finance";
      url = "https://finance.yahoo.com/portfolios";
      comment = "Stocks";
    })
    (mkPwa {
      id = "fidelity";
      name = "Fidelity";
      url = "https://digital.fidelity.com/";
      comment = "Brokerage — verify mobile-web fit on device; add dsf if desktop-only";
    })

    # ─── News ────────────────────────────────────────────────────────────────
    (mkPwa {
      id = "wsj";
      name = "WSJ";
      url = "https://www.wsj.com/";
      comment = "The Wall Street Journal";
      icon = ./wsj-icon.png;
      # Overlay scrollbars: auto-hiding, zero layout width (Fluent style on Linux).
      # kOverlayScrollbar is FEATURE_DISABLED_BY_DEFAULT on desktop; must be set
      # explicitly. "FluentOverlayScrollbars" is not a real BASE_FEATURE string.
      extraArgs = [ "--enable-features=OverlayScrollbar" ];
      # Title bar kept (not fullscreen): Daniel prefers the window title bar +
      # GNOME status bar visible over the fullscreen-hides-both tradeoff. The
      # overlay scrollbars above stay regardless.
    })

    # ─── Fitness ─────────────────────────────────────────────────────────────
    (mkPwa {
      id = "strava";
      name = "Strava";
      url = "https://www.strava.com/dashboard";
    })

    # ─── Auth / AI ───────────────────────────────────────────────────────────
    (mkPwa {
      id = "bitwarden";
      name = "Bitwarden";
      url = "https://vault.matv.io/";
      comment = "Self-hosted Vaultwarden";
    })
    (mkPwa {
      id = "claude";
      name = "Claude";
      url = "https://claude.ai/new";
    })

    # ─── Self-hosted / hosted PWAs ───────────────────────────────────────────
    # Immich viewer; auto-backup is a separate CLI-on-a-timer job (medium task).
    (mkPwa {
      id = "immich";
      name = "Immich";
      url = "https://photos.matv.io/";
      comment = "Photos (viewer — backup via immich CLI, tracked separately)";
    })
    # Linkding + Memos PWAs dropped — replaced by the native anchorage (Linkding)
    # and jotter (Memos) GTK apps in systemPackages.
    (mkPwa {
      id = "retrospend";
      name = "Retrospend";
      url = "https://retrospend.app/dashboard";
      comment = "Expense tracker";
    })

    # ─── Media ───────────────────────────────────────────────────────────────
    # YouTube via self-hosted Invidious on vista, reached over Tailscale. Uses
    # the node's stable 100.x IP (MagicDNS `vista:3000` also works if resolvable).
    # Invidious streams are DRM-free, so unlike Spotify web this plays fine in a
    # Chromium wrapper, and its web UI is genuinely responsive on a phone screen.
    (mkPwa {
      id = "invidious";
      name = "Invidious";
      url = "http://100.96.21.56:3000/";
      comment = "YouTube (self-hosted Invidious on vista, via Tailscale)";
      categories = [ "AudioVideo" ];
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
