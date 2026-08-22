# GNOME Shell Mobile overlay — vendored fork of chuangzhu/nixpkgs-gnome-mobile
# (0BSD), adapted so we own the pins and can bump verdre's branches ourselves.
#
# Tracks verdre's `mobile-shell-devel-49` for both mutter-mobile and
# gnome-shell-mobile. As of 2026-06 that is the NEWEST mobile branch verdre has
# — there is no GNOME 50 mobile branch yet (last touched 2026-01-30). Therefore
# this MUST be applied on top of a GNOME-49 nixpkgs (see flake input
# `nixpkgs-gnome49`); applying it to GNOME 50 nixpkgs will fail (49 source vs
# 50 derivation/patches).
#
# To bump: when verdre pushes a newer branch (e.g. mobile-shell-devel-50),
# update the three `rev`/`hash` pins below AND repin `nixpkgs-gnome49` to a
# matching GNOME major.
#
# Upstream refs:
#   https://gitlab.gnome.org/verdre/gnome-shell-mobile  (mobile-shell-devel-49)
#   https://gitlab.gnome.org/verdre/mutter-mobile        (mobile-shell-devel-49)
#   https://gitlab.gnome.org/verdre/gnome-settings-daemon-mobile (gnome-49-mobile)
#   https://github.com/chuangzhu/nixpkgs-gnome-mobile    (original overlay)

self: super:

let
  gvc = super.fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "GNOME";
    repo = "libgnome-volume-control";
    rev = "5f9768a2eac29c1ed56f1fbb449a77a3523683b6";
    hash = "sha256-gdgTnxzH8BeYQAsvv++Yq/8wHi7ISk2LTBfU8hk12NM=";
  };
  libshew = super.fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "GNOME";
    repo = "libshew";
    rev = "ed782477cb5164320ae4f731d49bc5d475ab2a52";
    hash = "sha256-auv5JsQUkytLLAAJzZlCDw4+v9/JfsCV1hKTa3Ku/Jg=";
  };
  gvdb = super.fetchFromGitLab {
    domain = "gitlab.gnome.org";
    owner = "GNOME";
    repo = "gvdb";
    rev = "b54bc5da25127ef416858a3ad92e57159ff565b3";
    hash = "sha256-c56yOepnKPEYFcU1B1TrDl8ydU0JU+z6R8siAQP4d2A=";
  };
in

{
  # gnome-keyring's global prompt queue can be corrupted when a no-prompt
  # unlock completes while another unlock is active.  That is the
  # perform_next_unlock() assertion seen during Fajita's boot-lock login.
  gnome-keyring = super.gnome-keyring.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [
      ./patches/gnome-keyring-serialize-unlock-completion.patch
    ];
  });

  gnome-shell =
    (super.gnome-shell.override {
      gnome-settings-daemon = self.gnome-settings-daemon-mobile;
      mutter = self.mutter;
    }).overrideAttrs
      (old: {
        version = "49.mobile.0-unstable-2026-01-30";
        src = super.fetchFromGitLab {
          domain = "gitlab.gnome.org";
          owner = "verdre";
          repo = "gnome-shell-mobile";
          rev = "f9e97c2f43827f22a1a3d7bbda8f8c7e88b450f9"; # mobile-shell-devel-49
          hash = "sha256-XafMWhohuET+1S3At+I+wykqHaL7cM+bYYmTYt74hNs=";
          fetchSubmodules = true;
        };
        # Local fixes on top of verdre's mobile branch (device-usability;
        # upstream separately later). Each patch = `git diff <file>` from the
        # matching checkout in ~/Projects/gnome-shell-mobile.
        patches = (old.patches or [ ]) ++ [
          ./patches/enable-swipe-to-close.patch # swipe a window preview up to close it
          ./patches/enable-appgrid-reorder.patch # let an icon drag win over the long-press menu
          ./patches/osk-strut-keep-maximized.patch # OSK reserves space via strut; windows stay maximized (no floating-CSD look)
          ./patches/auto-rotate-toggle.patch # QS Auto Rotate toggle → orientation-lock gsetting (fajita-autorotate daemon reads it)
          ./patches/osk-mobile-hide-button.patch # add hide-keyboard button to us-mobile layout (mobile layout omits it; swipe-down has no visual affordance)
          ./patches/powerkey-wake-brightness.patch # panel on BEFORE brightness restore (EINVAL race = wake-to-black); power key = Phosh-style press-state snapshot (replaces debounce+grace)
          ./patches/powerkey-screenshot-chord.patch # Volume-Up + Power = full-screen screenshot + iOS-style flash (coordinates the Vol-Up accelerator via shellDBus; withholds the gsd forward during the chord so the volume never moves / no OSD; suppresses the blank). MUST stay after powerkey-wake-brightness (same file); pairs with shelldbus-volume-chord.patch
          ./patches/powerkey-startup-guard.patch # ignore power presses until Shell startup + async GDM registration settle; prevents an early LockedHint from switching the VT to GDM. MUST stay after the two power-key patches above (same file)
          ./patches/autobacklight-fajita.patch # oneplus,fajita brightness curves (default linear = pwm 1 in the dark, visually OFF); ALS deadband + write rate-limit + retry
          ./patches/topbar-no-tap.patch # top bar = passive status bar: no tap-to-open calendar/QS (swipe-down still opens QS)
          ./patches/lockscreen-no-blur.patch # lock-screen wallpaper shown sharp + bright (no Gaussian blur/dim); scoped to UnlockDialog only
          ./patches/topbar-icons.patch # iOS/Android status bar: battery %-inside-outline, no sound icon, cellular = bars + "4G" text, cell hidden when wifi active (shown when QS open)
          ./patches/topbar-base-css.patch # the top-bar CSS (battery pill, inset, overview invert, charging, lock-screen shadows, clock shadow) baked into the BASE theme so it also applies on the lock/login screen (User Themes ext is off there)
          ./patches/shelldbus-volume-chord.patch # withhold Vol-Up accelerator from gsd during the screenshot chord (no volume bump / OSD)
          ./patches/osk-spacebar-cursor-slide.patch # spacebar long-press → cursor-slide mode: horizontal drag emits Left/Right; keyboard dims; finger-up suppresses the space
          ./patches/osk-autocaps-committed-tail.patch # auto-cap: replace dead surrounding-text dance with synchronous committedTail from _onCommitText (inputMethod.js); backspace/Enter handled
          ./patches/osk-swipe-typing.patch # swipe typing: letter-key glide → symbolic trace → PUA-framed emission to engine decoder (MUST stay after osk-spacebar-cursor-slide + osk-autocaps)
          ./patches/osk-strip-longpress-forget.patch # strip long-press → forget word: 600 ms hold on suggestion pill → candidate_clicked CONTROL_MASK → remove_candidate_from_user_database + flash
          ./patches/osk-tap-coords.patch # per-tap (col,row) coords → engine via press-only PUA markers (mirrors swipe channel; feeds spatial autocorrect). MUST stay after osk-swipe-typing + osk-autocaps (same files)
          ./patches/ios-home-appswitcher.patch # iOS home + app-switcher: full swipe-up = pure app-grid home (no window strip); half swipe-up = window-picker card switcher (re-adds WINDOW_PICKER snap point on phone, card layout, grid⇄cards crossfade, rounded cards)
          ./patches/widget-framework.patch # native St widget base + registry + settings-backed host; first slice mounts a clock card above the lock-screen clock
          ./patches/lockscreen-ios-controls.patch # transparent widget clock, phone lock shortcuts, no swipe hint; camera remains authentication-gated
          ./patches/today-view.patch # Today View sibling left of app-grid page 1; shared WidgetHost + boundary-gated horizontal paging
          ./patches/widget-scroll-safety.patch # WidgetHost/Today are plain BoxLayouts; clamp page height so no non-StScrollable/negative allocation can crash Shell
          ./patches/today-view-polish.patch # hide search on Today, reset to app grid on lock, and prevent zero-size pager NaNs
          ./patches/calendar-widget.patch # native local month calendar; Today-only default and compact card styling
          ./patches/agenda-timeline-widget.patch # replace month grid with a local Today/Tomorrow five-hour agenda; bounded native GridLayout, live now line
          ./patches/agenda-hairlines.patch # keep hour separators and current-time marker at true 1px height instead of GridLayout row-fill thickness
          ./patches/agenda-scroll-actions.patch # vertically scroll the agenda through the day via an explicit St.Viewport; date/event buttons open GNOME Calendar
          ./patches/solar-widget.patch # compact local sunrise/sunset card using Shell's weather location, libgweather astronomy, and a segmented daylight-progress track
          ./patches/weather-widget-lockscreen-complications.patch # compact five-hour Weather card + lock-screen next-event/weather/solar dot rows
          ./patches/appgrid-folder-drop.patch # drop an app onto an EXISTING folder now adds it (FolderIcon.acceptDrop persists to the folder's apps list instead of the throwing reorder path); guard _removeItem so redisplay can't throw "not part of the IconGridLayout". MUST stay after enable-appgrid-reorder + today-view (same file)
          ./patches/appgrid-drag-null-app.patch # drag-begin builds a placeholder AppIcon from lookup_app(id); Waydroid/PWA/folder ids don't resolve → AppIcon(null) threw & aborted the drag. Prefer source.app + null-guard. MUST stay after appgrid-folder-drop (same file)
          ./patches/appgrid-home-on-empty.patch # phone: closing the last window in the app-switcher lands on the home app-grid instead of an empty picker (adds a last-window-removed → APP_GRID transition; upstream has none). MUST stay after ios-home-appswitcher + today-view (same file)
        ]
        ++ [
          ./patches/android-quick-settings.patch # Nix-driven 4-column QS grid, compact/custom tiles, long-press settings, robust app focus, persistent mobile data
          ./patches/android-quick-settings-compact-grid.patch # compact Flashlight menu, stable configured ordering, and native Hotspot toggle
          ./patches/android-quick-settings-collapse.patch # two-row Android-style collapsed grid with an animated expand control
          ./patches/android-quick-settings-pull-expand.patch # pull down to reveal overflow rows; swipe up to collapse before closing
          ./patches/android-quick-settings-content-height.patch # keep auxiliary controls expanded-only and give notifications the collapsed shade remainder
          ./patches/android-quick-settings-gesture-polish.patch # gesture-only expansion; fast up-fling closes, deliberate up-drag collapses
          ./patches/android-quick-settings-interactive-drag.patch # finger-tracked expansion with position/velocity snapping
          ./patches/android-quick-settings-haptics.patch # subtle feedbackd pulse on tile activation and expansion snap changes
          ./patches/android-quick-settings-initial-clip.patch # clip collapsed overflow before the first allocation/open
          ./patches/mobile-control-polish.patch # stable DND/rotation icons and fully passive top-bar indicators
          ./patches/osk-clipboard.patch # clipboard foundation + Phase 1: in-shell history engine (owner-changed capture, cap/dedup/pin, secret-mimetype gating, async-persist) + terminal-aware paste/copy/cut chords via one Clutter virtual device + always-there 📋 paste button leading the OSK suggestion strip. New js/misc/clipboardHistory.js (pure) + js/ui/clipboardManager.js (glue); does not touch the 3-pill prediction logic
          ./patches/text-select.patch # long-press any on-screen text → highlight → Copy (MVP, line granularity). New js/ui/textSelect.js: ultra-conservative global Clutter.LongPressGesture on the stage (yields to all app/shell gestures, cancel-on-move), app-id blocklist + TEXT_SELECT_ENABLED kill-switch, AT-SPI (native GTK) → OCR fallback via fajita-textgrab-{atspi,ocr} helpers, scrim+highlight+Copy pill, set_text→clipboard-history. Crash/input-safe (every step try/catch → console.warn, fail-safe no-op)
          ./patches/startup-lock-after-gdm.patch # await GDM RegisterSession inside Shell, apply the configured autologin lock, then enable power keys. Replaces the racy external user unit; MUST stay after text-select (same main.js)
        ];
        prePatch = ''
          cp -r ${libshew} subprojects/libshew
          chmod -R u+w subprojects/libshew
          cp -r ${gvc} subprojects/gvc
          chmod -R u+w subprojects/gvc
        '';
        postPatch = ''
          patchShebangs \
            src/data-to-c.py \
            build-aux/generate-app-list.py

          # We can generate it ourselves.
          rm -f man/gnome-shell.1

          substituteInPlace js/ui/keyboard.js --replace-fail \
            "            const focus = global.display.focus_window;" \
            "            const _gd = global.display.focus_window; const focus = (_gd && _gd.maximized_vertically) ? _gd : this._focusWindow;"

          substituteInPlace js/ui/keyboard.js --replace-fail \
            "                focus.move_resize_frame(false, fr.x, wa.y, fr.width, wa.height);" \
            "                { focus.unmaximize(Meta.MaximizeFlags.VERTICAL); focus.move_resize_frame(false, fr.x, wa.y, fr.width, wa.height); focus.maximize(Meta.MaximizeFlags.VERTICAL); }"
        '';
        buildInputs = old.buildInputs ++ [
          super.modemmanager # /org/gnome/shell/misc/modemManager.js
          super.libgudev # /org/gnome/gjs/modules/esm/gi.js
        ];
        postFixup = old.postFixup + ''
          wrapGApp $out/share/gnome-shell/org.gnome.Shell.SensorDaemon
        '';
      });

  gnome-settings-daemon-mobile = super.gnome-settings-daemon.overrideAttrs (old: {
    version = "49.mobile.0-unstable-2026-01-30";
    src = super.fetchFromGitLab {
      domain = "gitlab.gnome.org";
      owner = "verdre";
      repo = "gnome-settings-daemon-mobile";
      rev = "11b4c4a7812a9ad6cca4796b715e6ec8b7c55c3e"; # gnome-49-mobile
      hash = "sha256-Lv79Vx7D7eAVC8alWA8V1aBOmhgXf5mtvZgpPiqx3dk=";
    };
    prePatch = ''
      rm -r subprojects/gvc
      cp -r ${gvc} subprojects/gvc
      chmod -R u+w subprojects/gvc
    '';
  });

  mutter =
    (super.mutter.override { gnome-settings-daemon = self.gnome-settings-daemon-mobile; }).overrideAttrs
      (old: {
        version = "49.mobile.0-unstable-2026-01-30";
        src = super.fetchFromGitLab {
          domain = "gitlab.gnome.org";
          owner = "verdre";
          repo = "mutter-mobile";
          rev = "3d1ac0577cb13baa11e8fe6ee4b192d4b26c7a7a"; # mobile-shell-devel-49
          hash = "sha256-qVwH3/HhxcgyGAbWMYI7t2tJLSNLT9ktJZrwlMonAes=";
        };
        postPatch = old.postPatch + ''
          ln -sf ${gvdb} subprojects/gvdb
        '';
      });
}
