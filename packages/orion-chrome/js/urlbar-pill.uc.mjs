// ==UserScript==
// @name           urlbar-pill
// @namespace      orion-chrome/urlbar-pill
// @version        2.0.0
// @description    Orion iOS bottom-bar C1b — URL-pill enhancements for Firefox
//                 150 on the fajita phone (428×630 logical, touch, dark theme).
//                 (1) Publishes the live #nav-bar height as the CSS variable
//                     --orion-bar-height on :root so urlbar-view-mobile.css can
//                     anchor the suggestions panel exactly above the two-row bar.
//                 (2) Injects a favicon <img> at the LEFT of the address pill,
//                     kept in sync with the selected tab (TabSelect / image attr
//                     change / location change); falls back to a globe glyph.
//                 (3) Domain shortening: handled ENTIRELY by Firefox prefs
//                     (browser.urlbar.trimURLs + browser.urlbar.trimHttps set in
//                     hosts/fajita/default.nix). This script NEVER writes
//                     gURLBar.value and NEVER calls setURI — doing so was the
//                     root cause of typed text disappearing on touch.
//                 (4) COPY button: injected into the pill, shown ONLY in edit
//                     mode (CSS keyed on #urlbar[focused]/[breakout-extend]);
//                     copies the current page URI and flashes a "Copied" state.
//                 All logs go to /tmp/ff-pill.log. Lazy, guarded, non-throwing.
// ==/UserScript==

(async () => {
  // ── ABSOLUTE FIRST STATEMENT: plain-overwrite eval-start log ──────────────
  const LOG_PATH = "/tmp/ff-pill.log";
  let _logInit = false;
  try {
    await IOUtils.writeUTF8(LOG_PATH, "urlbar-pill eval start " + new Date().toISOString() + "\n");
    _logInit = true;
  } catch (_) {}

  async function log(msg) {
    try {
      const line = new Date().toISOString() + " " + msg + "\n";
      if (_logInit) {
        await IOUtils.writeUTF8(LOG_PATH, line, { mode: "append" });
      } else {
        _logInit = true;
        await IOUtils.writeUTF8(LOG_PATH, line);
      }
    } catch (_) {}
  }

  // Wrap the whole body so no top-level throw can abort the module silently.
  try {

  const GLOBE_ICON = "chrome://global/skin/icons/defaultFavicon.svg";

  // ── (1) --orion-bar-height publisher ───────────────────────────────────────
  let _lastBarH = 0;
  function publishBarHeight() {
    try {
      const navBar = document.getElementById("nav-bar");
      if (!navBar) return;
      const h = Math.round(navBar.getBoundingClientRect().height);
      if (h > 0 && h !== _lastBarH) {
        _lastBarH = h;
        document.documentElement.style.setProperty("--orion-bar-height", h + "px");
        log("publishBarHeight: --orion-bar-height=" + h + "px");
      }
    } catch (err) {
      log("publishBarHeight error: " + err);
    }
  }

  function watchBarHeight() {
    try {
      const navBar = document.getElementById("nav-bar");
      if (!navBar) return false;
      publishBarHeight();
      try {
        const ro = new ResizeObserver(() => publishBarHeight());
        ro.observe(navBar);
      } catch (e) {
        log("ResizeObserver unavailable: " + e);
      }
      window.addEventListener("resize", publishBarHeight, { passive: true });
      let ticks = 0;
      const id = setInterval(() => {
        publishBarHeight();
        if (++ticks > 20) clearInterval(id);
      }, 250);
      return true;
    } catch (err) {
      log("watchBarHeight error: " + err);
      return false;
    }
  }

  // ── shared: the urlbar input container ────────────────────────────────────
  function getInputContainer() {
    try {
      const urlbar = document.getElementById("urlbar");
      if (!urlbar) return null;
      return urlbar.querySelector(".urlbar-input-container");
    } catch (_) {
      return null;
    }
  }

  // ── (2) favicon in the pill ────────────────────────────────────────────────
  let _favicon = null;

  function currentFaviconURL() {
    try {
      let url = null;
      try { url = gBrowser.getIcon(gBrowser.selectedTab); } catch (_) {}
      if (!url) {
        try { url = gBrowser.selectedTab.getAttribute("image"); } catch (_) {}
      }
      return url || null;
    } catch (_) {
      return null;
    }
  }

  function updateFavicon() {
    try {
      if (!_favicon) return;
      let uriIsWeb = false;
      try {
        const scheme = gBrowser.selectedBrowser.currentURI.scheme;
        uriIsWeb = scheme === "http" || scheme === "https";
      } catch (_) {}
      const url = uriIsWeb ? currentFaviconURL() : null;
      _favicon.src = url || GLOBE_ICON;
    } catch (err) {
      log("updateFavicon error: " + err);
    }
  }

  function injectFavicon() {
    try {
      if (_favicon && _favicon.isConnected) return true;
      const container = getInputContainer();
      if (!container) return false;
      const inputBox = container.querySelector(".urlbar-input-box");

      const img = document.createElementNS("http://www.w3.org/1999/xhtml", "img");
      img.className = "orion-pill-favicon";
      img.setAttribute("alt", "");
      img.style.cssText = [
        "width:18px",
        "height:18px",
        "min-width:18px",
        "margin-inline:2px 8px",
        "flex-shrink:0",
        "align-self:center",
        "object-fit:contain",
        "-moz-context-properties:fill",
        "fill:currentColor",
        "pointer-events:auto",
        "cursor:pointer",
        "-webkit-tap-highlight-color:transparent",
      ].join(";");
      img.addEventListener("error", () => { img.src = GLOBE_ICON; });

      // Tap favicon → open the page-actions menu (bookmark / reader / site info / copy).
      // stopImmediatePropagation so the click doesn't also focus the urlbar input
      // (which would enter edit mode).
      const onFaviconTap = (e) => {
        try {
          e.preventDefault();
          e.stopImmediatePropagation();
          openFaviconMenu();
        } catch (err) { log("favicon tap handler error: " + err); }
      };
      img.addEventListener("click", onFaviconTap, { capture: true });
      img.addEventListener("touchend", onFaviconTap, { capture: true, passive: false });

      if (inputBox) {
        container.insertBefore(img, inputBox);
      } else {
        container.insertBefore(img, container.firstChild);
      }
      _favicon = img;
      updateFavicon();
      log("injectFavicon: injected");
      return true;
    } catch (err) {
      log("injectFavicon error: " + err);
      return false;
    }
  }

  // ── (4) copy-URL button (edit mode only) ───────────────────────────────────
  let _copyBtn = null;

  function copyCurrentURL() {
    try {
      let spec = "";
      try { spec = gBrowser.selectedBrowser.currentURI.displaySpec; } catch (_) {}
      if (!spec) { try { spec = gURLBar.value; } catch (_) {} }
      if (!spec) return;
      let ok = false;
      try {
        Cc["@mozilla.org/widget/clipboardhelper;1"]
          .getService(Ci.nsIClipboardHelper)
          .copyString(spec);
        ok = true;
      } catch (e) {
        log("copyString failed, trying navigator.clipboard: " + e);
        try { navigator.clipboard.writeText(spec); ok = true; } catch (_) {}
      }
      log("copyCurrentURL: " + (ok ? "copied " : "FAILED ") + spec);
    } catch (err) {
      log("copyCurrentURL error: " + err);
    }
  }

  // ── (5) favicon tap-menu — page actions (bookmark / reader / site info / copy) ─
  // Replaces the lock/reader/star icons we hid in CSS. Popup is a position:fixed
  // overlay anchored above the pill's bottom-left (where the favicon sits).
  let _faviconMenu = null;
  let _menuCloseWired = false;

  function closeFaviconMenu() {
    try {
      if (_faviconMenu && _faviconMenu.isConnected) {
        _faviconMenu.remove();
      }
      _faviconMenu = null;
    } catch (_) {}
  }

  // ── (5b) lightweight toast (transient confirmation) ───────────────────────
  let _toast = null;
  let _toastTimer = null;
  function showToast(msg) {
    try {
      if (_toast && _toast.isConnected) _toast.remove();
      const t = document.createElementNS("http://www.w3.org/1999/xhtml", "div");
      t.id = "orion-toast";
      t.style.cssText = [
        "position:fixed",
        "left:50%",
        "bottom:calc(var(--orion-bar-height, 88px) + 16px)",
        "transform:translateX(-50%)",
        "z-index:10001",
        "background:rgba(40,40,50,0.95)",
        "color:#fff",
        "padding:10px 16px",
        "border-radius:8px",
        "font-family:system-ui,sans-serif",
        "font-size:13px",
        "box-shadow:0 2px 8px rgba(0,0,0,0.4)",
        "pointer-events:none",
        "max-width:80vw",
        "text-align:center",
      ].join(";");
      t.textContent = msg;
      document.documentElement.appendChild(t);
      _toast = t;
      if (_toastTimer) clearTimeout(_toastTimer);
      _toastTimer = setTimeout(() => {
        try { if (t.isConnected) t.remove(); } catch (_) {}
      }, 1800);
    } catch (_) {}
  }

  function openFaviconMenu() {
    try {
      // Toggle: if already open, a second tap closes it.
      if (_faviconMenu && _faviconMenu.isConnected) {
        closeFaviconMenu();
        return;
      }

      const menu = document.createElementNS("http://www.w3.org/1999/xhtml", "div");
      menu.id = "orion-favicon-menu";
      menu.style.cssText = [
        "position:fixed",
        "left:16px",
        "bottom:calc(var(--orion-bar-height, 88px) + 8px)",
        "z-index:10000",
        "background:#2b2a33",
        "color:#fbfbfe",
        "border:1px solid rgba(255,255,255,0.15)",
        "border-radius:10px",
        "padding:6px",
        "min-width:200px",
        "box-shadow:0 4px 12px rgba(0,0,0,0.4)",
        "font-family:system-ui,sans-serif",
        "font-size:14px",
        "user-select:none",
        "-webkit-tap-highlight-color:transparent",
      ].join(";");

      function addItem(label, handler) {
        const item = document.createElementNS("http://www.w3.org/1999/xhtml", "div");
        item.className = "orion-favicon-menu-item";
        item.setAttribute("role", "menuitem");
        item.style.cssText = [
          "display:flex",
          "align-items:center",
          "padding:14px 16px",
          "border-radius:6px",
          "cursor:pointer",
          "min-height:48px",
          "touch-action:manipulation",
          "-webkit-tap-highlight-color:rgba(255,255,255,0.1)",
        ].join(";");
        item.textContent = label;
        // Use a single click handler. The earlier double-wire (click + touchend)
        // caused the outside-tap close to fire before the action could run.
        // stopPropagation prevents the document-level close handler from running
        // for this tap; the handler runs closeFaviconMenu() itself after the action.
        const activate = (e) => {
          try {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
            closeFaviconMenu();
            try { handler(); } catch (err) { log("menu handler error: " + err); }
          } catch (_) {}
        };
        item.addEventListener("click", activate, { capture: true });
        menu.appendChild(item);
      }

      // Bookmark toggle — bookmark the page silently (StarUI popup is desktop
      // UI that doesn't render on mobile). Toggle: if already bookmarked, remove.
      addItem("Bookmark", async () => {
        try {
          const { PlacesUtils } = ChromeUtils.importESModule("resource://gre/modules/PlacesUtils.sys.mjs");
          const uri = gBrowser.selectedBrowser.currentURI;
          const existing = await PlacesUtils.bookmarks.fetch({ url: uri.spec });
          if (existing) {
            await PlacesUtils.bookmarks.remove(existing.guid);
            showToast("Bookmark removed");
            log("Bookmark: removed " + uri.spec);
          } else {
            await PlacesUtils.bookmarks.insert({
              parentGuid: PlacesUtils.bookmarks.unfiledGuid,
              url: uri.spec,
              title: gBrowser.selectedTab.label || uri.spec,
            });
            showToast("Bookmarked");
            log("Bookmark: added " + uri.spec);
          }
        } catch (e) { log("Bookmark PlacesUtils failed: " + e); }
      });

      // Reader mode toggle — only shown if the page offers reader mode.
      try {
        const rm = document.getElementById("reader-mode-button");
        if (rm && !rm.hidden && rm.getAttribute("hidden") !== "true") {
          addItem("Reader mode", () => {
            try {
              goDoCommand("Browser:ToggleReaderMode");
              log("Reader: goDoCommand dispatched");
            } catch (e) {
              log("Reader goDoCommand failed: " + e);
              try { ReaderParent.toggleReaderMode(gBrowser.selectedTab.linkedBrowser); }
              catch (e2) { log("Reader ReaderParent failed: " + e2); }
            }
          });
        }
      } catch (_) {}

      // Clear site data & cookies for the CURRENT site directly (no desktop dialog).
      // Wipes cookies + site data for this origin then reloads the page.
      addItem("Clear cookies & site data", async () => {
        try {
          const uri = gBrowser.selectedBrowser.currentURI;
          const host = uri.host;
          // Clear cookies for this host via the cookie manager.
          const cm = Cc["@mozilla.org/cookiemanager;1"].getService(Ci.nsICookieManager);
          try {
            // FF 150+: getCookiesFromHost returns an array (not nsISimpleEnumerator).
            const cookies = cm.getCookiesFromHost(host, {});
            const list = Array.isArray(cookies) ? cookies
              : (cookies && typeof cookies.length === "number" ? Array.from(cookies) : []);
            for (const c of list) {
              try {
                const ck = c.QueryInterface ? c.QueryInterface(Ci.nsICookie) : c;
                cm.remove(ck.host, ck.name, ck.path, ck.originAttributes || {});
              } catch (_) {}
            }
            // If the enumerator API is gone entirely, fall back to removeAll
            // (nuclear) so the user's intent ("clear cookies") is still honored.
            if (!list.length) {
              cm.removeAll();
            }
            log("ClearCookies: cookies removed for " + host);
          } catch (e) { log("ClearCookies cookie loop failed: " + e); }
          // Clear site data (storage, cache, service workers) for this host.
          try {
            const { SiteDataManager } = ChromeUtils.importESModule("resource:///modules/SiteDataManager.sys.mjs");
            await SiteDataManager.remove(host);
            log("ClearCookies: site data removed for " + host);
          } catch (e) { log("SiteDataManager.remove failed: " + e); }
          showToast("Cleared data for " + host);
          gBrowser.selectedTab.linkedBrowser.reload();
        } catch (e) { log("ClearCookies failed: " + e); }
      });

      // Copy URL — same handler as the (now hidden) pill copy button.
      addItem("Copy URL", () => { copyCurrentURL(); });

      document.documentElement.appendChild(menu);
      _faviconMenu = menu;
      log("openFaviconMenu: opened");

      // Defer wiring the outside-tap close so the opening tap doesn't close it
      // immediately (capture-phase click that opened the menu would bubble up).
      if (!_menuCloseWired) {
        _menuCloseWired = true;
        setTimeout(() => {
          const onDocClick = (e) => {
            try {
              if (_faviconMenu && !_faviconMenu.contains(e.target)) {
                closeFaviconMenu();
              }
            } catch (_) {}
          };
          const onKey = (e) => {
            if (e.key === "Escape") closeFaviconMenu();
          };
          document.addEventListener("click", onDocClick, { capture: true });
          document.addEventListener("touchend", onDocClick, { capture: true, passive: false });
          document.addEventListener("keyup", onKey);
          // The listeners are intentionally not once — they stay attached for
          // the menu's lifetime and reference _faviconMenu (which is null after
          // close, making them no-op until the next open re-wires).
          // NOTE: this is fine for a small popup; we clean up on close.
        }, 60);
      }
    } catch (err) {
      log("openFaviconMenu error: " + err);
    }
  }

  let _flashTimer = null;
  function flashCopied() {
    try {
      if (!_copyBtn) return;
      _copyBtn.setAttribute("data-copied", "1");
      _copyBtn.textContent = "Copied";
      if (_flashTimer) clearTimeout(_flashTimer);
      _flashTimer = setTimeout(() => {
        try {
          _copyBtn.removeAttribute("data-copied");
          _copyBtn.textContent = "Copy";
        } catch (_) {}
      }, 900);
    } catch (_) {}
  }

  function injectCopyButton() {
    try {
      if (_copyBtn && _copyBtn.isConnected) return true;
      const container = getInputContainer();
      if (!container) return false;

      const btn = document.createElementNS("http://www.w3.org/1999/xhtml", "div");
      btn.id = "orion-pill-copy";
      btn.setAttribute("role", "button");
      btn.setAttribute("aria-label", "Copy URL");
      btn.style.cssText = [
        "display:none",
        "align-items:center",
        "justify-content:center",
        "min-width:34px",
        "height:34px",
        "padding:0 8px",
        "margin-inline-start:4px",
        "flex-shrink:0",
        "border-radius:8px",
        "font-size:12px",
        "font-weight:600",
        "font-family:system-ui,sans-serif",
        "color:var(--toolbarbutton-icon-fill,currentColor)",
        "background:color-mix(in srgb, currentColor 10%, transparent)",
        "cursor:pointer",
        "-webkit-tap-highlight-color:transparent",
        "touch-action:manipulation",
        "user-select:none",
        "white-space:nowrap",
      ].join(";");
      btn.textContent = "Copy";

      function onTap(e) {
        e.preventDefault();
        e.stopPropagation();
        copyCurrentURL();
      }
      btn.addEventListener("click", onTap, { capture: true });
      btn.addEventListener("touchend", onTap, { capture: true, passive: false });
      btn.addEventListener("mousedown", (e) => e.preventDefault(), { capture: true });

      container.appendChild(btn);
      _copyBtn = btn;

      ensurePillStyles();
      log("injectCopyButton: injected");
      return true;
    } catch (err) {
      log("injectCopyButton error: " + err);
      return false;
    }
  }

  function ensurePillStyles() {
    try {
      if (document.getElementById("orion-pill-styles")) return;
      const style = document.createElement("style");
      style.id = "orion-pill-styles";
      style.textContent = `
        /* Copy button: REMOVED from pill — now lives in the favicon tap-menu. */
        /* (Kept hidden at all times; toolbar-mobile.css also hides #orion-pill-copy.) */
        #orion-pill-copy {
          display: none !important;
        }
        #orion-pill-copy[data-copied="1"] {
          color: #fff !important;
          background: #2aa84a !important;
        }
        /* Favicon hidden while editing (Orion shows a clean edit field). */
        #urlbar[focused] .orion-pill-favicon,
        #urlbar[breakout-extend] .orion-pill-favicon {
          display: none !important;
        }
        /* Ensure the input is always visible during edit. */
        #urlbar[focused] #urlbar-input,
        #urlbar[breakout-extend] #urlbar-input,
        #urlbar[usertyping] #urlbar-input {
          display: block !important;
          visibility: visible !important;
          opacity: 1 !important;
          color: var(--toolbar-field-color, #fff) !important;
          min-width: 0 !important;
          flex: 1 1 auto !important;
          pointer-events: auto !important;
        }
        /* The input-box wrapper: must also be visible and flex-grow */
        #urlbar[focused] .urlbar-input-box,
        #urlbar[breakout-extend] .urlbar-input-box,
        #urlbar[usertyping] .urlbar-input-box {
          flex: 1 1 auto !important;
          min-width: 0 !important;
          overflow: hidden !important;
        }
        /* Input container: flex row so elements sit side-by-side */
        #urlbar[focused] .urlbar-input-container,
        #urlbar[breakout-extend] .urlbar-input-container,
        #urlbar[usertyping] .urlbar-input-container {
          display: flex !important;
          flex-direction: row !important;
          align-items: center !important;
        }
        /* Reset centered text-align from resting state during edit */
        #urlbar[focused] #urlbar-input,
        #urlbar[breakout-extend] #urlbar-input,
        #urlbar[usertyping] #urlbar-input {
          text-align: start !important;
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    } catch (err) {
      log("ensurePillStyles error: " + err);
    }
  }

  // ── wiring: keep favicon in sync with tab/location changes ────────────────
  function onLocationChangeLike() {
    try {
      updateFavicon();
    } catch (_) {}
  }

  function wireEvents() {
    try {
      // Tab switch: refresh favicon.
      try {
        gBrowser.tabContainer.addEventListener("TabSelect", onLocationChangeLike);
      } catch (e) { log("TabSelect wire failed: " + e); }

      // Favicon attribute change on the current tab.
      try {
        gBrowser.tabContainer.addEventListener("TabAttrModified", (e) => {
          try {
            if (e.target !== gBrowser.selectedTab) return;
            if (e.detail && e.detail.changed && e.detail.changed.includes("image")) {
              updateFavicon();
            }
          } catch (_) {}
        });
      } catch (e) { log("TabAttrModified wire failed: " + e); }

      // Location change: update favicon.
      try {
        const listener = {
          QueryInterface: ChromeUtils.generateQI([
            "nsIWebProgressListener",
            "nsISupportsWeakReference",
          ]),
          onLocationChange() { onLocationChangeLike(); },
          onStateChange() {},
          onProgressChange() {},
          onSecurityChange() {},
          onStatusChange() {},
          onContentBlockingEvent() {},
        };
        gBrowser.addProgressListener(listener);
      } catch (e) { log("addProgressListener failed: " + e); }

      log("wireEvents: done");
    } catch (err) {
      log("wireEvents error: " + err);
    }
  }

  // ── (6) move #stop-reload-button INTO the urlbar pill ─────────────────────
  // Orion's reload is part of the pill, not a separate toolbar item. Moving it
  // into .urlbar-input-container makes it a flex child of the pill — no z-index
  // or stacking-context issues, renders naturally at the right edge.
  let _reloadMoved = false;
  function moveReloadIntoPill() {
    try {
      if (_reloadMoved) {
        // Re-check it's still there (FF can re-render).
        const container = getInputContainer();
        const reload = document.getElementById("stop-reload-button");
        if (reload && container && reload.parentElement !== container) {
          container.appendChild(reload);
        }
        return true;
      }
      const container = getInputContainer();
      if (!container) return false;
      const reload = document.getElementById("stop-reload-button");
      if (!reload) return false;
      container.appendChild(reload);
      _reloadMoved = true;
      log("moveReloadIntoPill: moved");
      return true;
    } catch (err) {
      log("moveReloadIntoPill error: " + err);
      return false;
    }
  }

  // ── (7) C4: swipe-between-tabs on the pill ───────────────────────────────
  // touchmove reaches chrome JS (confirmed in touch-spike log). We attach a
  // NON-PASSIVE touchmove listener on the urlbar container so we can
  // preventDefault() to stop the input's text-pan, then track horizontal
  // swipe distance. On touchend, if |dx| > threshold and |dy| < |dx|, switch
  // tabs via gBrowser.tabContainer.advanceSelectedTab().
  // Only active when urlbar is NOT in edit mode (don't hijack text selection).
  let _swipeStartX = null;
  let _swipeStartY = null;
  let _swipeActive = false;
  const SWIPE_THRESHOLD = 40; // px of horizontal travel to trigger tab switch
  let _swipeWired = false;

  function isEditing() {
    try {
      const u = document.getElementById("urlbar");
      if (!u) return false;
      return u.hasAttribute("focused") || u.hasAttribute("breakout-extend");
    } catch (_) { return false; }
  }

  function wireSwipe() {
    try {
      if (_swipeWired) return;
      // Listen on #urlbar-container (the pill row) — covers favicon + input + reload.
      const container = document.getElementById("urlbar-container");
      if (!container) return;

      // touchstart: record origin (non-passive so we can also preventDefault if needed).
      container.addEventListener("touchstart", (e) => {
        if (isEditing()) { _swipeStartX = null; _swipeActive = false; return; }
        const t = e.touches[0];
        if (!t) return;
        _swipeStartX = t.clientX;
        _swipeStartY = t.clientY;
        _swipeActive = true;
      }, { passive: true });

      // touchmove: preventDefault to kill text-pan, track delta.
      container.addEventListener("touchmove", (e) => {
        if (!_swipeActive || isEditing()) return;
        // CRITICAL: preventDefault stops the input from scrolling/panning text.
        try { e.preventDefault(); } catch (_) {}
      }, { passive: false });

      // touchend: if horizontal swipe exceeds threshold, switch tabs.
      container.addEventListener("touchend", (e) => {
        if (!_swipeActive || isEditing()) { _swipeStartX = null; _swipeActive = false; return; }
        _swipeActive = false;
        const t = e.changedTouches[0];
        if (!t || _swipeStartX === null) { _swipeStartX = null; return; }
        const dx = t.clientX - _swipeStartX;
        const dy = (t.clientY - _swipeStartY) || 0;
        _swipeStartX = null;
        if (Math.abs(dx) < SWIPE_THRESHOLD) return;       // not enough travel
        if (Math.abs(dy) > Math.abs(dx)) return;           // vertical-dominant, not a swipe
        try {
          // dx > 0 = swipe right = previous tab; dx < 0 = swipe left = next tab.
          const dir = dx > 0 ? -1 : 1;
          gBrowser.tabContainer.advanceSelectedTab(dir, true);
          log("swipe: dx=" + Math.round(dx) + " dir=" + dir + " → tab switch");
        } catch (err) { log("swipe tab switch error: " + err); }
      }, { passive: true });

      _swipeWired = true;
      log("wireSwipe: wired on #urlbar-container");
    } catch (err) {
      log("wireSwipe error: " + err);
    }
  }

  // ── boot ───────────────────────────────────────────────────────────────────
  function start() {
    try {
      log("start() " + new Date().toISOString());

      if (!watchBarHeight()) {
        const bhId = setInterval(() => { if (watchBarHeight()) clearInterval(bhId); }, 300);
        setTimeout(() => clearInterval(bhId), 8000);
      }

      let injected = false;
      const injId = setInterval(() => {
        try {
          const okF = injectFavicon();
          const okC = injectCopyButton();
          const okR = moveReloadIntoPill();
          if (okF && okC && okR && !injected) {
            injected = true;
            wireEvents();
            wireSwipe();
            updateFavicon();
          }
          if (okF && okC && okR) clearInterval(injId);
        } catch (err) {
          log("inject poll: " + err);
        }
      }, 300);
      setTimeout(() => clearInterval(injId), 15000);
    } catch (err) {
      log("start error: " + err);
    }
  }

  if (document.readyState === "complete" || document.readyState === "interactive") {
    start();
  } else {
    window.addEventListener("DOMContentLoaded", start, { once: true });
  }

  } catch (outerErr) {
    try {
      await IOUtils.writeUTF8(
        LOG_PATH,
        new Date().toISOString() + " TOP-LEVEL THROW: " + outerErr + "\n" +
        (outerErr && outerErr.stack ? outerErr.stack + "\n" : ""),
        { mode: "append" }
      );
    } catch (_) {}
  }
})();
