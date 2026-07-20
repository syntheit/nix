// ==UserScript==
// @name           urlbar-inspect
// @namespace      orion-chrome/urlbar-inspect
// @version        0.1.0
// @description    DOM geometry inspector for the urlbar suggestions panel.
//                 Polls every 2 s; when the urlbar popup is open, dumps
//                 BoundingClientRect + computed styles for each relevant
//                 element to /tmp/ff-urlbar-dump.json, then backs off 30 s.
// ==/UserScript==

// Runs in the browser window (default @include = browser.xhtml).
// Wrapped in an async IIFE so top-level await is not needed.
(async () => {
  const DUMP_PATH = "/tmp/ff-urlbar-dump.json";
  const POLL_MS   = 2000;
  const BACKOFF_MS = 30000;

  const STYLE_PROPS = [
    "position", "top", "bottom", "left", "right",
    "width", "height", "minHeight", "maxHeight",
    "margin", "padding",
    "backgroundColor", "display",
    "flexDirection", "alignItems", "flexGrow",
    "overflow",
  ];

  function getElementData(el, label) {
    try {
      const r = el.getBoundingClientRect();
      const cs = window.getComputedStyle(el);
      const styles = {};
      for (const prop of STYLE_PROPS) {
        try { styles[prop] = cs[prop]; } catch (_) {}
      }
      return {
        label,
        rect: { x: r.x, y: r.y, w: r.width, h: r.height },
        styles,
      };
    } catch (err) {
      return { label, error: String(err) };
    }
  }

  async function dump() {
    try {
      const data = {
        ts: new Date().toISOString(),
        innerWidth:  window.innerWidth,
        innerHeight: window.innerHeight,
        elements: [],
      };

      const selectors = [
        { sel: ".urlbarView",             label: ".urlbarView" },
        { sel: ".urlbarView-body-outer",  label: ".urlbarView-body-outer" },
        { sel: ".urlbarView-body-inner",  label: ".urlbarView-body-inner" },
        { sel: ".urlbarView-results",     label: ".urlbarView-results" },
      ];

      for (const { sel, label } of selectors) {
        const el = document.querySelector(sel);
        if (el) {
          data.elements.push(getElementData(el, label));
        } else {
          data.elements.push({ label, error: "not found" });
        }
      }

      // First 8 rows
      const rows = document.querySelectorAll(".urlbarView-row");
      let rowIdx = 0;
      for (const row of rows) {
        if (rowIdx >= 8) break;
        data.elements.push(getElementData(row, `.urlbarView-row[${rowIdx}]`));
        rowIdx++;
      }

      await IOUtils.writeUTF8(DUMP_PATH, JSON.stringify(data, null, 2));
    } catch (err) {
      try {
        await IOUtils.writeUTF8(DUMP_PATH, JSON.stringify({ error: String(err) }));
      } catch (_) {}
    }
  }

  let backoffUntil = 0;

  function poll() {
    try {
      const now = Date.now();
      if (now < backoffUntil) return;

      // Check if urlbar is open: #urlbar[open] or .urlbarView visible
      const urlbar = document.getElementById("urlbar");
      const view   = document.querySelector(".urlbarView");

      const isOpen = urlbar && urlbar.hasAttribute("open") && view;
      if (isOpen) {
        dump().catch(() => {});
        backoffUntil = now + BACKOFF_MS;
      }
    } catch (_) {}
  }

  // Start polling after the window is ready
  function start() {
    window.setInterval(poll, POLL_MS);
  }

  if (document.readyState === "complete" || document.readyState === "interactive") {
    start();
  } else {
    window.addEventListener("DOMContentLoaded", start, { once: true });
  }
})();
