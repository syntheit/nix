// ==UserScript==
// @name           touch-spike
// @namespace      orion-chrome/touch-spike
// @version        0.2.0
// @description    Log touch events from the nav bar and window to /tmp/ff-touch-spike.log
//                 so we can verify fx-autoconfig is working and measure touch coordinates.
// ==/UserScript==

// touch-spike: loaded once per browser window by fx-autoconfig module_loader.
// Wrapped in an async IIFE so the startup IOUtils write is properly awaited
// (fire-and-forget Promises can be GC'd before Gecko schedules them).
(async () => {
  const LOG = "/tmp/ff-touch-spike.log";

  // Startup confirmation — proves the loader fired even before any touch.
  // NOTE: overwrite (no mode option) is proven to work; { mode: "append" }
  // silently fails to CREATE a non-existent file in Firefox 150.
  try {
    await IOUtils.writeUTF8(LOG, "touch-spike loaded " + new Date().toISOString() + "\n");
  } catch (_) {}

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

  function wire() {
    const navBar = document.getElementById("nav-bar");

    if (navBar) {
      for (const type of ["touchstart", "touchmove", "touchend", "touchcancel"]) {
        navBar.addEventListener(type, logTouch, opts);
      }
    }

    // Also listen on window for broader coverage
    for (const type of ["touchstart", "touchmove", "touchend", "touchcancel"]) {
      window.addEventListener(type, logTouch, opts);
    }

    if (!navBar) {
      console.warn("[touch-spike] #nav-bar not found — only window listeners attached");
    }
  }

  // DOMContentLoaded fires before fx-autoconfig runs scripts in most cases,
  // but guard with readyState just in case.
  if (document.readyState === "complete" || document.readyState === "interactive") {
    wire();
  } else {
    window.addEventListener("DOMContentLoaded", wire, { once: true });
  }
})();
