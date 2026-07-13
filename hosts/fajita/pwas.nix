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
    }:
    let
      launcher = pkgs.writeShellScript "pwa-${id}" ''
        exec ${browser} \
          --app=${lib.escapeShellArg url} \
          --class=pwa-${id} \
          --user-data-dir="$HOME/.local/share/pwa/${id}" \
          --ozone-platform-hint=auto \
          "$@"
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
    })

    # ─── Chat / comms ────────────────────────────────────────────────────────
    (mkPwa {
      id = "slack";
      name = "Slack";
      url = "https://app.slack.com/client";
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
    })
    # Stopgap for WhatsApp — the better long-term answer is a mautrix-whatsapp
    # bridge on your server surfaced through Fractal. Web logs out periodically.
    (mkPwa {
      id = "whatsapp";
      name = "WhatsApp";
      url = "https://web.whatsapp.com/";
    })

    # ─── Finance (low priority — "deal with it / web") ───────────────────────
    (mkPwa {
      id = "yahoo-finance";
      name = "Yahoo Finance";
      url = "https://finance.yahoo.com/portfolios";
      comment = "Stocks";
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
      url = "https://vault.bitwarden.com/";
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
    (mkPwa {
      id = "linkding";
      name = "Linkding";
      url = "https://links.matv.io/";
      comment = "Bookmarks";
    })
    (mkPwa {
      id = "memos";
      name = "Memos";
      url = "https://notes.matv.io/";
    })
    (mkPwa {
      id = "retrospend";
      name = "Retrospend";
      url = "https://retrospend.app/";
      comment = "Expense tracker";
    })
  ];
in
{
  environment.systemPackages = pwas;
}
