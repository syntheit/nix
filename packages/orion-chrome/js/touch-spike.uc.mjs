// ==UserScript==
// @name           touch-spike
// @namespace      orion-chrome/touch-spike
// @version        0.1.0
// @description    Log touch events from the nav bar and tab strip to /tmp/ff-touch-spike.log
//                 so we can verify fx-autoconfig is working and measure touch coordinates.
// ==/UserScript==

// touch-spike: loaded once per browser window (DOMContentLoaded on browser.xhtml).
// Attaches passive touch listeners to #nav-bar and the tab strip container,
// appending "type x y timestamp\n" lines to /tmp/ff-touch-spike.log via IOUtils.

(function () {
  const LOG = "/tmp/ff-touch-spike.log";

  // Startup confirmation — proves the loader fired even before any touch.
  console.log("[touch-spike] loaded");
  IOUtils.writeUTF8(LOG, "touch-spike loaded\n", { mode: "append" }).catch(() => {});

  async function logTouch(evt) {
    const t = evt.touches[0] ?? evt.changedTouches[0];
    if (!t) return;
    const line = `${evt.type} ${Math.round(t.clientX)} ${Math.round(t.clientY)} ${Date.now()}\n`;
    console.log("[touch-spike]", line.trimEnd());
    try {
      await IOUtils.writeUTF8(LOG, line, { mode: "append" });
    } catch (_) {}
  }

  const opts = { passive: true, capture: false };

  // Wait until the window's document is fully ready so #nav-bar and
  // gBrowser.tabContainer are guaranteed to exist.
  function wire() {
    const navBar = document.getElementById("nav-bar");
    const tabContainer = window.gBrowser?.tabContainer;

    if (navBar) {
      for (const type of ["touchstart", "touchmove", "touchend"]) {
        navBar.addEventListener(type, logTouch, opts);
      }
    }

    if (tabContainer) {
      for (const type of ["touchstart", "touchmove", "touchend"]) {
        tabContainer.addEventListener(type, logTouch, opts);
      }
    }

    if (!navBar && !tabContainer) {
      console.warn("[touch-spike] neither #nav-bar nor tabContainer found — skipping");
    }
  }

  // DOMContentLoaded fires before this script is invoked per fx-autoconfig
  // semantics, but guard with readyState just in case.
  if (document.readyState === "complete" || document.readyState === "interactive") {
    wire();
  } else {
    window.addEventListener("DOMContentLoaded", wire, { once: true });
  }
})();
