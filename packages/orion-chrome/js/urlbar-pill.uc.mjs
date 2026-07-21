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
        "pointer-events:none",
      ].join(";");
      img.addEventListener("error", () => { img.src = GLOBE_ICON; });

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
      flashCopied();
    } catch (err) {
      log("copyCurrentURL error: " + err);
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
        /* Copy button: visible only while editing the pill. */
        #urlbar[focused] #orion-pill-copy,
        #urlbar[breakout-extend] #orion-pill-copy {
          display: flex !important;
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
          if (okF && okC && !injected) {
            injected = true;
            wireEvents();
            updateFavicon();
          }
          if (okF && okC) clearInterval(injId);
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
