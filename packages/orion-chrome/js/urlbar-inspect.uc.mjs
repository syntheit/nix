// ==UserScript==
// @name           urlbar-inspect
// @namespace      orion-chrome/urlbar-inspect
// @version        0.5.0
// @description    DOM geometry inspector for the urlbar suggestions panel.
//                 Polls every 2 s; when the urlbar popup is open, dumps
//                 BoundingClientRect + computed styles for each relevant
//                 element to /tmp/ff-urlbar-dump.json, then backs off 30 s.
//                 v0.2: also dumps #urlbar and #urlbar-input-container with
//                 the containing-block properties (transform/willChange/
//                 contain/filter/backdropFilter) to verify the will-change fix.
//                 v0.3: also dumps full toolbar structure at startup to
//                 /tmp/ff-toolbar-dump.json (always present, no interaction needed).
//                 v0.5: NEW — edit-mode continuous dump to /tmp/ff-urlbar-edit.json
//                 every ~600 ms while #urlbar has [open] or [focused]; captures
//                 geometry + key computed styles for urlbar, input container,
//                 input field, input box, injected favicon/copy, and suggestions
//                 panel, plus inline style attr and breakout attribute list.
// ==/UserScript==

// Runs in the browser window (default @include = browser.xhtml).
// Wrapped in an async IIFE so top-level await is not needed.
(async () => {
  const DUMP_PATH         = "/tmp/ff-urlbar-dump.json";
  const TOOLBAR_DUMP_PATH = "/tmp/ff-toolbar-dump.json";
  const EDIT_DUMP_PATH    = "/tmp/ff-urlbar-edit.json";
  const POLL_MS      = 2000;
  const BACKOFF_MS   = 30000;
  const EDIT_POLL_MS = 600;

  const STYLE_PROPS = [
    "position", "top", "bottom", "left", "right",
    "width", "height", "minHeight", "maxHeight",
    "margin", "padding",
    "backgroundColor", "display",
    "flexDirection", "alignItems", "flexGrow",
    "overflow",
  ];

  // Extra properties that can create a containing block for fixed descendants.
  const CONTAINING_BLOCK_PROPS = [
    "transform", "willChange", "contain", "filter",
    "backdropFilter", "perspective",
  ];

  // Computed style props for toolbar elements.
  const TOOLBAR_STYLE_PROPS = [
    "display", "visibility", "position", "order",
    "flexGrow", "width", "height", "marginInline",
  ];

  // Computed style props for edit-mode capture.
  const EDIT_STYLE_PROPS = [
    "position", "left", "right", "width", "height",
    "display", "visibility", "opacity", "color",
    "overflow", "transform", "zIndex", "marginInline",
  ];

  // Breakout attributes to check on #urlbar.
  const URLBAR_BREAKOUT_ATTRS = [
    "breakout", "breakout-extend", "open", "focused", "usertyping",
  ];

  function getElementData(el, label, extraProps) {
    try {
      const r = el.getBoundingClientRect();
      const cs = window.getComputedStyle(el);
      const styles = {};
      for (const prop of STYLE_PROPS) {
        try { styles[prop] = cs[prop]; } catch (_) {}
      }
      if (extraProps) {
        for (const prop of extraProps) {
          try { styles[prop] = cs[prop]; } catch (_) {}
        }
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

  // Collect geometry + computed styles for a toolbar element by id.
  function getToolbarElementData(id) {
    try {
      const el = document.getElementById(id);
      if (!el) return { id, present: false };
      const r = el.getBoundingClientRect();
      const cs = window.getComputedStyle(el);
      const computed = {};
      for (const prop of TOOLBAR_STYLE_PROPS) {
        try { computed[prop] = cs[prop]; } catch (_) {}
      }
      const visible = r.width > 0 && r.height > 0 && computed.display !== "none";
      return {
        id,
        tagName: el.tagName,
        present: true,
        visible,
        rect: { x: r.x, y: r.y, w: r.width, h: r.height },
        computed,
      };
    } catch (err) {
      return { id, present: false, error: String(err) };
    }
  }

  // List direct children ids (in DOM order) for a toolbar container.
  function getDirectChildrenIds(containerId) {
    try {
      const el = document.getElementById(containerId);
      if (!el) return null;
      const ids = [];
      for (const child of el.children) {
        ids.push(child.id || ("(no-id:" + child.tagName +
          (child.className ? "." + String(child.className).split(" ")[0] : "") + ")"));
      }
      return ids;
    } catch (_) {
      return null;
    }
  }

  // Same as getDirectChildrenIds but takes a CSS selector root.
  function getDirectChildrenIdsSel(sel) {
    try {
      const el = document.querySelector(sel);
      if (!el) return null;
      const ids = [];
      for (const child of el.children) {
        ids.push(child.id || ("(no-id:" + child.tagName +
          (child.className ? "." + String(child.className).split(" ")[0] : "") + ")"));
      }
      return ids;
    } catch (_) {
      return null;
    }
  }

  // Collect geometry + computed styles for an element by CSS selector.
  function getSelElementData(sel) {
    try {
      const el = document.querySelector(sel);
      if (!el) return { sel, present: false };
      const r = el.getBoundingClientRect();
      const cs = window.getComputedStyle(el);
      const computed = {};
      for (const prop of TOOLBAR_STYLE_PROPS) {
        try { computed[prop] = cs[prop]; } catch (_) {}
      }
      const visible = r.width > 0 && r.height > 0 && computed.display !== "none";
      return {
        sel,
        id: el.id || null,
        tagName: el.tagName,
        className: String(el.className || ""),
        present: true,
        visible,
        rect: { x: r.x, y: r.y, w: r.width, h: r.height },
        computed,
      };
    } catch (err) {
      return { sel, present: false, error: String(err) };
    }
  }

  // Capture one element's edit-mode data (geometry + EDIT_STYLE_PROPS).
  // Returns { present, rect, computed } or { present: false }.
  function captureEditElement(el) {
    if (!el) return { present: false };
    try {
      const r = el.getBoundingClientRect();
      const cs = window.getComputedStyle(el);
      const computed = {};
      for (const prop of EDIT_STYLE_PROPS) {
        try { computed[prop] = cs[prop]; } catch (_) {}
      }
      return {
        present: true,
        rect: { x: r.x, y: r.y, w: r.width, h: r.height },
        computed,
      };
    } catch (err) {
      return { present: false, error: String(err) };
    }
  }

  // ── v0.5: Edit-mode continuous dump ─────────────────────────────────────────

  async function dumpEditMode() {
    const errors = [];
    const data = {
      ts: new Date().toISOString(),
      innerWidth:  window.innerWidth,
      innerHeight: window.innerHeight,
      orionTabgridOpen: null,
      urlbarAttrs: [],
      elements: {},
      errors,
    };

    try {
      data.orionTabgridOpen =
        document.documentElement.getAttribute("orion-tabgrid-open");
    } catch (err) {
      errors.push({ ctx: "orionTabgridOpen", error: String(err) });
    }

    // #urlbar — id-based + inline style + breakout attr list
    try {
      const urlbar = document.getElementById("urlbar");
      const entry = captureEditElement(urlbar);
      if (urlbar) {
        try {
          entry.inlineStyle = urlbar.getAttribute("style");
        } catch (err) {
          errors.push({ ctx: "#urlbar inlineStyle", error: String(err) });
        }
        try {
          for (const attr of URLBAR_BREAKOUT_ATTRS) {
            if (urlbar.hasAttribute(attr)) data.urlbarAttrs.push(attr);
          }
        } catch (err) {
          errors.push({ ctx: "#urlbar attrs", error: String(err) });
        }
      }
      data.elements["#urlbar"] = entry;
    } catch (err) {
      errors.push({ ctx: "#urlbar", error: String(err) });
      data.elements["#urlbar"] = { present: false, error: String(err) };
    }

    // .urlbar-input-container — via querySelector (or gURLBar if available)
    try {
      let root = null;
      try { root = window.gURLBar ? window.gURLBar.querySelector(".urlbar-input-container") : null; } catch (_) {}
      if (!root) root = document.querySelector(".urlbar-input-container");
      data.elements[".urlbar-input-container"] = captureEditElement(root);
    } catch (err) {
      errors.push({ ctx: ".urlbar-input-container", error: String(err) });
      data.elements[".urlbar-input-container"] = { present: false, error: String(err) };
    }

    // #urlbar-input — the actual editable input
    try {
      const input = document.getElementById("urlbar-input");
      const entry = captureEditElement(input);
      if (input) {
        try { entry.valueLength = input.value ? input.value.length : 0; } catch (_) {}
        try { entry.selectionStart = input.selectionStart; } catch (_) {}
      }
      data.elements["#urlbar-input"] = entry;
    } catch (err) {
      errors.push({ ctx: "#urlbar-input", error: String(err) });
      data.elements["#urlbar-input"] = { present: false, error: String(err) };
    }

    // .urlbar-input-box
    try {
      data.elements[".urlbar-input-box"] =
        captureEditElement(document.querySelector(".urlbar-input-box"));
    } catch (err) {
      errors.push({ ctx: ".urlbar-input-box", error: String(err) });
      data.elements[".urlbar-input-box"] = { present: false, error: String(err) };
    }

    // .orion-pill-favicon — our injected favicon
    try {
      data.elements[".orion-pill-favicon"] =
        captureEditElement(document.querySelector(".orion-pill-favicon"));
    } catch (err) {
      errors.push({ ctx: ".orion-pill-favicon", error: String(err) });
      data.elements[".orion-pill-favicon"] = { present: false, error: String(err) };
    }

    // #orion-pill-copy — our injected copy button
    try {
      data.elements["#orion-pill-copy"] =
        captureEditElement(document.getElementById("orion-pill-copy"));
    } catch (err) {
      errors.push({ ctx: "#orion-pill-copy", error: String(err) });
      data.elements["#orion-pill-copy"] = { present: false, error: String(err) };
    }

    // .urlbarView — suggestions panel
    try {
      data.elements[".urlbarView"] =
        captureEditElement(document.querySelector(".urlbarView"));
    } catch (err) {
      errors.push({ ctx: ".urlbarView", error: String(err) });
      data.elements[".urlbarView"] = { present: false, error: String(err) };
    }

    try {
      await IOUtils.writeUTF8(EDIT_DUMP_PATH, JSON.stringify({ writing: true }));
      await IOUtils.writeUTF8(EDIT_DUMP_PATH, JSON.stringify(data, null, 2));
    } catch (err) {
      try {
        await IOUtils.writeUTF8(EDIT_DUMP_PATH,
          JSON.stringify({ error: String(err), ts: new Date().toISOString() }));
      } catch (_) {}
    }
  }

  function isEditMode() {
    try {
      const urlbar = document.getElementById("urlbar");
      if (!urlbar) return false;
      return urlbar.hasAttribute("open") || urlbar.hasAttribute("focused");
    } catch (_) {
      return false;
    }
  }

  function pollEditMode() {
    try {
      if (isEditMode()) {
        dumpEditMode().catch(() => {});
      }
    } catch (_) {}
  }

  // ── END v0.5 ─────────────────────────────────────────────────────────────────

  async function dumpToolbar() {
    try {
      const TOOLBAR_IDS = [
        "TabsToolbar",
        "tabbrowser-tabs",
        "nav-bar",
        "back-button",
        "forward-button",
        "reload-button",
        "stop-reload-button",
        "urlbar",
        "urlbar-container",
        "urlbar-input-container",
        "identity-box",
        "page-action-buttons",
        "alltabs-button",
        "PanelUI-menu-button",
        "unified-extensions-button",
        "new-tab-button",
        "tabs-newtab-button",
      ];

      const data = {
        ts: new Date().toISOString(),
        innerWidth:  window.innerWidth,
        innerHeight: window.innerHeight,
        elements: {},
        childOrder: {},
        errors: [],
      };

      for (const id of TOOLBAR_IDS) {
        try {
          data.elements[id] = getToolbarElementData(id);
        } catch (err) {
          data.errors.push({ id, error: String(err) });
        }
      }

      // v0.4: urlbar internals — these are CLASS-based in FF150, not IDs, so
      // capture them via querySelector. Confirms where to inject the favicon
      // (before .urlbar-input-box) and the copy button (in .urlbar-input-container).
      const SEL_TARGETS = [
        ".urlbar-input-container",
        ".urlbar-input-box",
        "#urlbar-input",
        "#identity-box",
        "#identity-icon",
        "#page-action-buttons",
        "#userContext-icons",
        ".urlbar-go-button",
        "#star-button-box",
        "#nav-bar-customization-target",
      ];
      data.urlbarInternals = {};
      for (const sel of SEL_TARGETS) {
        try {
          data.urlbarInternals[sel] = getSelElementData(sel);
        } catch (err) {
          data.errors.push({ sel, error: String(err) });
        }
      }

      // Direct children DOM order for the key containers.
      data.childOrder["TabsToolbar"] = getDirectChildrenIds("TabsToolbar");
      data.childOrder["nav-bar"]     = getDirectChildrenIds("nav-bar");
      data.childOrder["nav-bar-customization-target"] =
        getDirectChildrenIds("nav-bar-customization-target");
      data.childOrder[".urlbar-input-container"] =
        getDirectChildrenIdsSel(".urlbar-input-container");

      // Plain overwrite first (proven pattern): write a sentinel, then the real data.
      await IOUtils.writeUTF8(TOOLBAR_DUMP_PATH, JSON.stringify({ writing: true }));
      await IOUtils.writeUTF8(TOOLBAR_DUMP_PATH, JSON.stringify(data, null, 2));
    } catch (err) {
      try {
        await IOUtils.writeUTF8(TOOLBAR_DUMP_PATH, JSON.stringify({ error: String(err) }));
      } catch (_) {}
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

      // Ancestor elements: dump with containing-block props to verify the fix.
      const ancestorSelectors = [
        { sel: "#urlbar",                   label: "#urlbar" },
        { sel: "#urlbar-input-container",   label: "#urlbar-input-container" },
      ];

      for (const { sel, label } of ancestorSelectors) {
        const el = document.getElementById
          ? (sel.startsWith("#") ? document.getElementById(sel.slice(1)) : document.querySelector(sel))
          : document.querySelector(sel);
        if (el) {
          data.elements.push(getElementData(el, label, CONTAINING_BLOCK_PROPS));
        } else {
          data.elements.push({ label, error: "not found" });
        }
      }

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

  // Start polling after the window is ready; also fire the one-shot toolbar dump.
  function start() {
    // Toolbar dump: run immediately (toolbar is always present at startup).
    dumpToolbar().catch(() => {});
    // Existing urlbar-open suggestions-panel dump (2 s poll, 30 s backoff).
    window.setInterval(poll, POLL_MS);
    // v0.5: edit-mode continuous dump (600 ms poll, no backoff).
    window.setInterval(pollEditMode, EDIT_POLL_MS);
  }

  if (document.readyState === "complete" || document.readyState === "interactive") {
    start();
  } else {
    window.addEventListener("DOMContentLoaded", start, { once: true });
  }
})();
