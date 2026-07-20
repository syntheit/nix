// ==UserScript==
// @name           tab-grid
// @namespace      orion-chrome/tab-grid
// @version        1.2.0
// @description    Orion-iOS-style tab grid overlay for Firefox on the fajita
//                 phone (432×936 logical, touch, dark theme).  Intercepts the
//                 #alltabs-button click, shows a full-screen 2-column card grid
//                 with live PageThumbs thumbnails, close ✕ per card, and a
//                 bottom bar with [+ New Tab] / [Done].
//                 All events (click + touchend) logged to /tmp/ff-grid-touch.log.
//                 All errors appended to /tmp/ff-grid-errors.log.
//                 Also wires a guaranteed floating ▦ button so the grid opens
//                 even if #alltabs-button interception fails.
// ==/UserScript==

(async () => {
  // ── ABSOLUTE FIRST STATEMENT: unconditional eval-start log ─────────────────
  // Written before ANY helper, import, or DOM access.
  // Uses plain IOUtils.writeUTF8 (no mode option) — the only form proven to
  // create a new file from chrome modules in FF 150 (same idiom as loader-proof).
  try {
    await IOUtils.writeUTF8(
      "/tmp/ff-grid-errors.log",
      "tab-grid eval start " + new Date().toISOString() + "\n"
    );
  } catch (_) {}

  // ── wrap ENTIRE remaining body to catch any top-level throw ────────────────
  try {

  // ── helpers ────────────────────────────────────────────────────────────────

  // Whether we have written the first byte to each log file this session.
  // We use overwrite for the first write (proven to work in FF150 from chrome
  // modules) and append thereafter.  { mode: "append" } silently fails to
  // CREATE a file that does not yet exist, so the first write must be plain.
  //
  // NOTE: ff-grid-errors.log was already overwrite-created above (eval-start),
  // so mark it as initialised so subsequent writes use append.
  const _logInit = { "/tmp/ff-grid-errors.log": true };

  async function appendLog(path, msg) {
    try {
      const line = msg + "\n";
      if (_logInit[path]) {
        await IOUtils.writeUTF8(path, line, { mode: "append" });
      } else {
        _logInit[path] = true;
        await IOUtils.writeUTF8(path, line);
      }
    } catch (_) {}
  }

  function logTouch(msg) {
    appendLog("/tmp/ff-grid-touch.log", new Date().toISOString() + " " + msg);
  }

  function logError(msg) {
    appendLog("/tmp/ff-grid-errors.log", new Date().toISOString() + " " + msg);
  }

  // ── PageThumbs (LAZY) ──────────────────────────────────────────────────────
  // Do NOT call ChromeUtils.importESModule at eval time — it can throw or
  // silently abort the entire module.  Import on first thumbnail capture only.
  let _PageThumbs = null;
  let _PageThumbsTried = false;

  async function getPageThumbs() {
    if (_PageThumbsTried) return _PageThumbs;
    _PageThumbsTried = true;
    try {
      const mod = ChromeUtils.importESModule(
        "resource://gre/modules/PageThumbs.sys.mjs"
      );
      _PageThumbs = mod.PageThumbs;
    } catch (err) {
      logError("PageThumbs lazy import failed: " + err);
      _PageThumbs = null;
    }
    return _PageThumbs;
  }

  // Capture a thumbnail for a browser tab → data-URL string, or "" on failure.
  async function captureThumbnail(browser) {
    try {
      const PT = await getPageThumbs();
      if (!PT) return "";
      const canvas = document.createElementNS(
        "http://www.w3.org/1999/xhtml",
        "canvas"
      );
      canvas.width = 400;
      canvas.height = 660;
      await PT.captureToCanvas(browser, canvas);
      return canvas.toDataURL("image/jpeg", 0.8);
    } catch (err) {
      logError("captureThumbnail: " + err);
      return "";
    }
  }

  // ── CSS (injected once) ────────────────────────────────────────────────────

  function ensureStyles() {
    if (document.getElementById("orion-tab-grid-styles")) return;
    try {
      const style = document.createElement("style");
      style.id = "orion-tab-grid-styles";
      style.textContent = `
        #orion-tab-grid-overlay {
          position: fixed;
          inset: 0;
          z-index: 2147483647;
          background: var(--arrowpanel-background, #1c1b22);
          display: flex;
          flex-direction: column;
          overflow: hidden;
          font-family: system-ui, sans-serif;
          color: #fff;
        }

        #orion-tab-grid-scroll {
          flex: 1;
          overflow-y: auto;
          overflow-x: hidden;
          padding: 12px;
          -webkit-overflow-scrolling: touch;
        }

        #orion-tab-grid-cards {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 12px;
        }

        .orion-tab-card {
          position: relative;
          background: #2b2a33;
          border-radius: 8px;
          border: 1px solid rgba(255,255,255,0.1);
          overflow: hidden;
          aspect-ratio: 3/5;
          cursor: pointer;
          -webkit-tap-highlight-color: transparent;
          touch-action: manipulation;
        }

        .orion-tab-card.active {
          border: 2px solid #00b3f4;
        }

        .orion-tab-thumb {
          width: 100%;
          height: calc(100% - 32px);
          object-fit: cover;
          display: block;
          background: #38383d;
        }

        .orion-tab-thumb-placeholder {
          width: 100%;
          height: calc(100% - 32px);
          background: #38383d;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 28px;
        }

        .orion-tab-title-strip {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          height: 32px;
          background: rgba(28,27,34,0.85);
          display: flex;
          align-items: center;
          padding: 0 6px;
          gap: 4px;
          overflow: hidden;
        }

        .orion-tab-favicon {
          width: 16px;
          height: 16px;
          flex-shrink: 0;
          border-radius: 2px;
        }

        .orion-tab-label {
          font-size: 13px;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
          flex: 1;
          color: #ccc;
        }

        .orion-tab-close {
          position: absolute;
          top: 4px;
          right: 4px;
          width: 28px;
          height: 28px;
          background: rgba(28,27,34,0.75);
          border-radius: 50%;
          border: none;
          color: #fff;
          font-size: 16px;
          display: flex;
          align-items: center;
          justify-content: center;
          cursor: pointer;
          padding: 0;
          line-height: 1;
          -webkit-tap-highlight-color: transparent;
          touch-action: manipulation;
        }

        #orion-tab-grid-bottom {
          flex-shrink: 0;
          display: flex;
          gap: 12px;
          padding: 12px 16px;
          background: rgba(28,27,34,0.95);
          border-top: 1px solid rgba(255,255,255,0.1);
        }

        #orion-tab-grid-new,
        #orion-tab-grid-done {
          flex: 1;
          padding: 12px 0;
          border-radius: 8px;
          border: none;
          font-size: 15px;
          font-weight: 600;
          cursor: pointer;
          -webkit-tap-highlight-color: transparent;
          touch-action: manipulation;
        }

        #orion-tab-grid-new {
          background: #00b3f4;
          color: #fff;
        }

        #orion-tab-grid-done {
          background: #38383d;
          color: #fff;
        }

        #orion-tab-grid-fab {
          position: fixed;
          bottom: 72px;
          left: 8px;
          width: 36px;
          height: 36px;
          border-radius: 8px;
          background: rgba(0,179,244,0.85);
          color: #fff;
          font-size: 20px;
          display: flex;
          align-items: center;
          justify-content: center;
          z-index: 2147483646;
          cursor: pointer;
          touch-action: manipulation;
          -webkit-tap-highlight-color: transparent;
          user-select: none;
          box-shadow: 0 2px 8px rgba(0,0,0,0.4);
        }
      `;
      (document.head || document.documentElement).appendChild(style);
    } catch (err) {
      logError("ensureStyles: " + err);
    }
  }

  // ── grid state ─────────────────────────────────────────────────────────────

  let overlayEl = null;

  function closeOverlay() {
    try {
      if (overlayEl && overlayEl.parentNode) {
        overlayEl.parentNode.removeChild(overlayEl);
      }
      overlayEl = null;
      logTouch("overlay closed");
    } catch (err) {
      logError("closeOverlay: " + err);
    }
  }

  // Register both click and touchend; log which fires.
  function addTapHandler(el, handler) {
    el.addEventListener("click", (e) => {
      logTouch("click on " + (el.id || el.className || "?"));
      try { handler(e); } catch (err) { logError("click handler: " + err); }
    }, { capture: true });
    el.addEventListener("touchend", (e) => {
      e.preventDefault(); // prevent ghost click
      logTouch("touchend on " + (el.id || el.className || "?"));
      try { handler(e); } catch (err) { logError("touchend handler: " + err); }
    }, { capture: true, passive: false });
  }

  async function buildCardForTab(tab) {
    try {
      const card = document.createElement("div");
      card.className = "orion-tab-card" +
        (tab === gBrowser.selectedTab ? " active" : "");

      // thumbnail
      const browser = tab.linkedBrowser;
      let thumb = null;
      if (browser) {
        const dataUrl = await captureThumbnail(browser);
        if (dataUrl) {
          thumb = document.createElement("img");
          thumb.className = "orion-tab-thumb";
          thumb.src = dataUrl;
          card.appendChild(thumb);
        }
      }
      if (!thumb) {
        const ph = document.createElement("div");
        ph.className = "orion-tab-thumb-placeholder";
        ph.textContent = "🌐";
        card.appendChild(ph);
      }

      // title strip
      const strip = document.createElement("div");
      strip.className = "orion-tab-title-strip";

      const favicon = document.createElement("img");
      favicon.className = "orion-tab-favicon";
      try {
        const iconUrl = tab.getAttribute("image");
        favicon.src = iconUrl || "chrome://global/skin/icons/defaultFavicon.svg";
      } catch (_) {
        favicon.src = "chrome://global/skin/icons/defaultFavicon.svg";
      }
      favicon.onerror = () => {
        favicon.src = "chrome://global/skin/icons/defaultFavicon.svg";
      };

      const label = document.createElement("span");
      label.className = "orion-tab-label";
      label.textContent = tab.getAttribute("label") || "New Tab";

      strip.appendChild(favicon);
      strip.appendChild(label);
      card.appendChild(strip);

      // close button
      const closeBtn = document.createElement("button");
      closeBtn.className = "orion-tab-close";
      closeBtn.textContent = "✕";
      closeBtn.setAttribute("aria-label", "Close tab");
      addTapHandler(closeBtn, (e) => {
        e.stopPropagation();
        try {
          gBrowser.removeTab(tab);
        } catch (err) {
          logError("removeTab: " + err);
        }
        rerenderGrid();
      });
      card.appendChild(closeBtn);

      // tap card → switch to tab
      addTapHandler(card, (e) => {
        // Don't trigger if the close button was tapped (stopPropagation handled above)
        if (e.target === closeBtn) return;
        try {
          gBrowser.selectedTab = tab;
        } catch (err) {
          logError("selectedTab set: " + err);
        }
        closeOverlay();
      });

      return card;
    } catch (err) {
      logError("buildCardForTab: " + err);
      return document.createElement("div"); // empty fallback
    }
  }

  async function rerenderGrid() {
    try {
      if (!overlayEl) return;
      const grid = overlayEl.querySelector("#orion-tab-grid-cards");
      if (!grid) return;

      // Clear existing cards
      while (grid.firstChild) {
        grid.removeChild(grid.firstChild);
      }

      const tabs = gBrowser.tabs;
      logTouch("rerenderGrid: " + tabs.length + " tabs");

      // Build cards in order (await each thumbnail sequentially to avoid
      // hammering the compositor; for v1 this is fine at <10 tabs)
      for (const tab of tabs) {
        try {
          const card = await buildCardForTab(tab);
          grid.appendChild(card);
        } catch (err) {
          logError("card build loop: " + err);
        }
      }
    } catch (err) {
      logError("rerenderGrid: " + err);
    }
  }

  async function openOverlay() {
    try {
      if (overlayEl) {
        closeOverlay();
        return;
      }

      logTouch("openOverlay");
      ensureStyles();

      const overlay = document.createElement("div");
      overlay.id = "orion-tab-grid-overlay";
      overlayEl = overlay;

      // Scroll container
      const scrollEl = document.createElement("div");
      scrollEl.id = "orion-tab-grid-scroll";

      // Card grid
      const gridEl = document.createElement("div");
      gridEl.id = "orion-tab-grid-cards";
      scrollEl.appendChild(gridEl);
      overlay.appendChild(scrollEl);

      // Bottom bar
      const bottomBar = document.createElement("div");
      bottomBar.id = "orion-tab-grid-bottom";

      const newTabBtn = document.createElement("button");
      newTabBtn.id = "orion-tab-grid-new";
      newTabBtn.textContent = "+ New Tab";
      addTapHandler(newTabBtn, () => {
        try {
          const tab = gBrowser.addTab("about:newtab", {
            triggeringPrincipal:
              Services.scriptSecurityManager.getSystemPrincipal(),
          });
          gBrowser.selectedTab = tab;
        } catch (err) {
          logError("addTab: " + err);
        }
        closeOverlay();
      });

      const doneBtn = document.createElement("button");
      doneBtn.id = "orion-tab-grid-done";
      doneBtn.textContent = "Done";
      addTapHandler(doneBtn, () => closeOverlay());

      bottomBar.appendChild(newTabBtn);
      bottomBar.appendChild(doneBtn);
      overlay.appendChild(bottomBar);

      // Tap on empty area of overlay (not cards/buttons) closes it
      overlay.addEventListener("click", (e) => {
        if (e.target === overlay || e.target === scrollEl || e.target === gridEl) {
          logTouch("click overlay bg → close");
          closeOverlay();
        }
      });
      overlay.addEventListener("touchend", (e) => {
        if (e.target === overlay || e.target === scrollEl || e.target === gridEl) {
          e.preventDefault();
          logTouch("touchend overlay bg → close");
          closeOverlay();
        }
      }, { passive: false });

      // Attach to document
      (document.body || document.documentElement).appendChild(overlay);

      // Populate cards after DOM is live
      await rerenderGrid();
    } catch (err) {
      logError("openOverlay: " + err);
    }
  }

  // ── trigger interception ───────────────────────────────────────────────────

  function wireAlltabsButton() {
    try {
      const btn = document.getElementById("alltabs-button");
      if (!btn) {
        logTouch("wireAlltabsButton: #alltabs-button not found");
        return false;
      }

      btn.addEventListener("click", (e) => {
        logTouch("alltabs-button click intercepted");
        e.preventDefault();
        e.stopPropagation();
        openOverlay().catch((err) => logError("openOverlay (promise): " + err));
      }, { capture: true });

      btn.addEventListener("touchend", (e) => {
        logTouch("alltabs-button touchend intercepted");
        e.preventDefault();
        e.stopPropagation();
        openOverlay().catch((err) => logError("openOverlay (promise): " + err));
      }, { capture: true, passive: false });

      logTouch("wireAlltabsButton: wired #alltabs-button");
      return true;
    } catch (err) {
      logError("wireAlltabsButton: " + err);
      return false;
    }
  }

  // Fallback keyboard shortcut (F6) for desktop-side testing
  function wireKeyboard() {
    try {
      window.addEventListener("keydown", (e) => {
        if (e.key === "F6" && !e.ctrlKey && !e.altKey && !e.metaKey) {
          logTouch("F6 keydown → openOverlay");
          e.preventDefault();
          e.stopPropagation();
          openOverlay().catch((err) => logError("openOverlay (F6): " + err));
        }
      }, { capture: true });
    } catch (err) {
      logError("wireKeyboard: " + err);
    }
  }

  // ── floating fallback button ───────────────────────────────────────────────
  // Always-visible ▦ button (bottom-left, fixed) so the grid can be opened
  // even if the #alltabs-button interception fails.
  // Polls for document.body if not yet available.

  function ensureFloatingButton() {
    try {
      if (document.getElementById("orion-tab-grid-fab")) return;
      const target = document.body || document.documentElement;
      if (!target) {
        // document.body not yet available — poll
        logError("ensureFloatingButton: body not ready, will retry via poll");
        return false;
      }
      const fab = document.createElement("div");
      fab.id = "orion-tab-grid-fab";
      fab.textContent = "▦";
      fab.title = "Open tab grid";
      addTapHandler(fab, () => {
        logTouch("fab tapped → openOverlay");
        openOverlay().catch((err) => logError("openOverlay (fab): " + err));
      });
      target.appendChild(fab);
      logError("floating button added");  // goes to errors log so it's visible
      logTouch("ensureFloatingButton: ▦ fab added");
      return true;
    } catch (err) {
      logError("ensureFloatingButton: " + err);
      return false;
    }
  }

  // ── MutationObserver fallback for #alltabs-button ─────────────────────────
  // The button is built lazily by Firefox — retry until found.

  let _alltabsObserver = null;

  function watchForAlltabsButton() {
    try {
      if (_alltabsObserver) return; // already watching
      _alltabsObserver = new MutationObserver(() => {
        if (wireAlltabsButton()) {
          _alltabsObserver.disconnect();
          _alltabsObserver = null;
          logTouch("watchForAlltabsButton: wired #alltabs-button via observer");
        }
      });
      _alltabsObserver.observe(document.documentElement, {
        childList: true,
        subtree: true,
      });
    } catch (err) {
      logError("watchForAlltabsButton: " + err);
    }
  }

  // ── boot ───────────────────────────────────────────────────────────────────
  // Mirror urlbar-inspect exactly: check readyState, or defer to DOMContentLoaded.
  // All window/gBrowser/document access is inside start() — never at eval time.

  function start() {
    try {
      logTouch("tab-grid start() " + new Date().toISOString());
      logError("tab-grid start() reached " + new Date().toISOString());

      wireKeyboard();

      if (!wireAlltabsButton()) {
        // Button not yet in DOM — watch for it via MutationObserver.
        logTouch("start: #alltabs-button not found, starting observer");
        watchForAlltabsButton();
      }

      // Always add the floating ▦ fallback button.
      if (!ensureFloatingButton()) {
        // body not ready — poll via setInterval (same pattern as urlbar-inspect)
        const fabPollId = setInterval(() => {
          try {
            if (ensureFloatingButton()) {
              clearInterval(fabPollId);
            }
          } catch (err) {
            logError("fab poll: " + err);
            clearInterval(fabPollId);
          }
        }, 500);
      }
    } catch (err) {
      logError("start: " + err);
    }
  }

  // Exact copy of urlbar-inspect's readyState guard:
  if (document.readyState === "complete" || document.readyState === "interactive") {
    start();
  } else {
    window.addEventListener("DOMContentLoaded", start, { once: true });
  }

  } catch (outerErr) {
    // Catch any top-level throw that escaped the inner try blocks.
    // Append to the errors log (already created by the eval-start write above).
    try {
      await IOUtils.writeUTF8(
        "/tmp/ff-grid-errors.log",
        new Date().toISOString() + " TOP-LEVEL THROW: " + outerErr + "\n" +
        (outerErr && outerErr.stack ? outerErr.stack + "\n" : ""),
        { mode: "append" }
      );
    } catch (_) {}
  }
})();
