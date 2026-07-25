// ==UserScript==
// @name           tab-grid
// @namespace      orion-chrome/tab-grid
// @version        1.5.0
// @description    Orion-iOS-style tab grid overlay for Firefox on the fajita
//                 phone (432×936 logical, touch, dark theme).  Intercepts the
//                 #alltabs-button click, shows a full-screen 2-column card grid
//                 with live PageThumbs thumbnails, close ✕ per card, and a
//                 bottom bar with a native tab-groups picker, [+ New Tab], and
//                 [Done]. The picker filters this overview; it does not invent
//                 a parallel group model, so Firefox session restore remains
//                 the authority for groups.
//                 All events (click + touchend) logged to /tmp/ff-grid-touch.log.
//                 All errors appended to /tmp/ff-grid-errors.log.
//                 C1a: injects a toolbar tab button in #nav-bar before ≡.
//                 C1b: tab button + new-tab button injected as DIRECT children
//                 of #nav-bar (before #PanelUI-button) so the two-row bottom bar
//                 can order them onto row 2. Menu button is NOT reparented.
//                 FAB is gated behind SHOW_FAB = false (code kept, not shown).
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
          /* Open/close animation: starts hidden, openOverlay() flips to visible
             via requestAnimationFrame so the transition actually runs. */
          opacity: 0;
          transform: translateY(20px);
          transition: opacity 0.2s ease, transform 0.2s ease;
          will-change: opacity, transform;
        }

        #orion-tab-grid-scroll {
          flex: 1;
          overflow-y: auto;
          overflow-x: hidden;
          padding: 16px 12px 12px;
          -webkit-overflow-scrolling: touch;
        }

        #orion-tab-grid-cards {
          display: grid;
          grid-template-columns: 1fr 1fr;
          grid-auto-rows: 220px;
          gap: 12px;
          align-content: start;
        }

        .orion-tab-card {
          position: relative;
          background: #1c1b22;
          border-radius: 8px;
          border: 2px solid transparent;
          overflow: hidden;
          height: 220px;
          cursor: pointer;
          -webkit-tap-highlight-color: transparent;
          touch-action: manipulation;
          box-shadow: 0 1px 3px rgba(0,0,0,0.3);
        }

        .orion-tab-card.active {
          box-shadow: 0 0 0 2px #00b3f4, 0 2px 8px rgba(0,179,244,0.3);
        }

        .orion-tab-thumb {
          width: 100%;
          height: 192px;
          object-fit: cover;
          display: block;
          background: #38383d;
          border-radius: 8px 8px 0 0;
        }

        .orion-tab-thumb-placeholder {
          width: 100%;
          height: 192px;
          background: #38383d;
          display: flex;
          align-items: center;
          justify-content: center;
          font-size: 28px;
          border-radius: 8px 8px 0 0;
        }

        .orion-tab-title-strip {
          position: absolute;
          bottom: 0;
          left: 0;
          right: 0;
          height: 28px;
          background: linear-gradient(to top, rgba(0,0,0,0.85), rgba(0,0,0,0.6));
          display: flex;
          align-items: center;
          padding: 0 6px;
          gap: 4px;
          overflow: hidden;
          border-radius: 0 0 8px 8px;
        }

        .orion-tab-favicon {
          width: 16px;
          height: 16px;
          flex-shrink: 0;
          border-radius: 2px;
        }

        .orion-tab-label {
          font-size: 14px;
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
          width: 32px;
          height: 32px;
          background: rgba(0,0,0,0.6);
          backdrop-filter: blur(4px);
          -webkit-backdrop-filter: blur(4px);
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

        .orion-tab-close:active {
          background: rgba(255,255,255,0.2);
        }

        #orion-tab-grid-bottom {
          flex-shrink: 0;
          display: flex;
          gap: 8px;
          padding: 12px 16px;
          background: rgba(28,27,34,0.95);
          border-top: 1px solid rgba(255,255,255,0.1);
        }

        #orion-tab-grid-groups,
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

        #orion-tab-grid-groups {
          background: #38383d;
          color: #fff;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        #orion-tab-grid-new {
          background: #00b3f4;
          color: #fff;
        }

        #orion-tab-grid-done {
          background: #38383d;
          color: #fff;
        }

        /* This sheet belongs to the overview, rather than a Firefox panel, so
           it stays in the touch-sized fullscreen layer and cannot be anchored
           to the hidden desktop tab strip. */
        #orion-tab-groups-backdrop {
          position: absolute;
          inset: 0;
          z-index: 1;
          background: rgba(0,0,0,0.38);
          opacity: 0;
          transition: opacity 0.16s ease;
        }

        #orion-tab-groups-sheet {
          position: absolute;
          z-index: 2;
          left: 8px;
          right: 8px;
          bottom: 76px;
          max-height: min(58vh, 480px);
          overflow-y: auto;
          padding: 8px;
          border: 1px solid rgba(255,255,255,0.14);
          border-radius: 14px;
          background: rgba(43,42,51,0.98);
          box-shadow: 0 12px 36px rgba(0,0,0,0.5);
          transform: translateY(16px);
          opacity: 0;
          transition: transform 0.18s ease, opacity 0.18s ease;
          -webkit-overflow-scrolling: touch;
        }

        #orion-tab-groups-sheet[open] {
          transform: translateY(0);
          opacity: 1;
        }

        .orion-tab-group-option {
          box-sizing: border-box;
          display: flex;
          align-items: center;
          width: 100%;
          min-height: 52px;
          gap: 10px;
          padding: 8px 10px;
          border: 0;
          border-radius: 9px;
          background: transparent;
          color: #fff;
          font: 600 15px system-ui, sans-serif;
          text-align: left;
          cursor: pointer;
          touch-action: manipulation;
          -webkit-tap-highlight-color: transparent;
        }

        .orion-tab-group-option.active,
        .orion-tab-group-option:active {
          background: rgba(0,179,244,0.22);
        }

        .orion-tab-group-color {
          width: 12px;
          height: 12px;
          flex: 0 0 12px;
          border-radius: 50%;
          background: var(--orion-group-color, #00b3f4);
          box-shadow: 0 0 0 2px rgba(255,255,255,0.14);
        }

        .orion-tab-group-name {
          min-width: 0;
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }

        .orion-tab-group-count {
          margin-left: auto;
          color: #c5c5cc;
          font-size: 13px;
          font-weight: 500;
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
  // null means the normal all-tabs overview.  A group id is deliberately used
  // instead of retaining a group node: Firefox can remove/recreate group DOM
  // during tab close, session restore, and cross-window adoption.
  let activeGroupId = null;
  let _gridRenderGeneration = 0;

  const GROUP_COLOR_FALLBACKS = {
    blue: "#00b3f4", purple: "#a371f7", cyan: "#22d3ee", orange: "#fb923c",
    yellow: "#facc15", pink: "#f472b6", green: "#4ade80", gray: "#a1a1aa",
    red: "#fb7185",
  };

  function getOpenTabGroups() {
    try {
      return Array.from(gBrowser.tabGroups || []).filter(group =>
        group && group.isConnected !== false && Array.isArray(group.tabs) && group.tabs.length
      );
    } catch (err) {
      logError("getOpenTabGroups: " + err);
      return [];
    }
  }

  function getActiveGroup() {
    if (!activeGroupId) return null;
    const group = getOpenTabGroups().find(candidate => candidate.id === activeGroupId) || null;
    // A group can vanish while the overlay is open (for example, its final tab
    // is closed). Fall back gracefully instead of rendering a blank grid.
    if (!group) activeGroupId = null;
    return group;
  }

  function groupName(group) {
    try {
      return group.label || group.defaultGroupName || "Untitled group";
    } catch (_) {
      return "Untitled group";
    }
  }

  function filteredTabs() {
    try {
      const activeGroup = getActiveGroup();
      return Array.from(activeGroup ? activeGroup.tabs : gBrowser.tabs).filter(tab =>
        tab && !tab.closing && (!activeGroup || tab.group === activeGroup)
      );
    } catch (err) {
      logError("filteredTabs: " + err);
      return [];
    }
  }

  function updateGroupsButton() {
    try {
      const button = overlayEl?.querySelector("#orion-tab-grid-groups");
      if (!button) return;
      const activeGroup = getActiveGroup();
      button.textContent = activeGroup ? groupName(activeGroup) : "Groups";
      button.setAttribute("aria-label", activeGroup ?
        "Tab groups, showing " + groupName(activeGroup) : "Tab groups, showing all tabs");
    } catch (err) {
      logError("updateGroupsButton: " + err);
    }
  }

  function closeGroupsPicker() {
    try {
      const sheet = overlayEl?.querySelector("#orion-tab-groups-sheet");
      const backdrop = overlayEl?.querySelector("#orion-tab-groups-backdrop");
      if (!sheet || !backdrop || !sheet._orionPickerOpen) return;
      sheet._orionPickerOpen = false;
      sheet.removeAttribute("open");
      backdrop.style.opacity = "0";
      setTimeout(() => {
        try {
          if (!sheet._orionPickerOpen) {
            sheet.remove();
            backdrop.remove();
          }
        } catch (_) {}
      }, 180);
    } catch (err) {
      logError("closeGroupsPicker: " + err);
    }
  }

  function openGroupsPicker() {
    try {
      if (!overlayEl) return;
      const existing = overlayEl.querySelector("#orion-tab-groups-sheet");
      if (existing) {
        closeGroupsPicker();
        return;
      }

      const backdrop = document.createElement("div");
      backdrop.id = "orion-tab-groups-backdrop";
      backdrop.setAttribute("aria-hidden", "true");
      const sheet = document.createElement("div");
      sheet.id = "orion-tab-groups-sheet";
      sheet.setAttribute("role", "dialog");
      sheet.setAttribute("aria-label", "Tab groups");
      sheet._orionPickerOpen = true;

      const addOption = (label, count, group = null) => {
        const option = document.createElement("button");
        option.className = "orion-tab-group-option" +
          ((!group && !activeGroupId) || (group && group.id === activeGroupId) ? " active" : "");
        option.type = "button";
        const swatch = document.createElement("span");
        swatch.className = "orion-tab-group-color";
        if (group) {
          const color = GROUP_COLOR_FALLBACKS[group.color] || "#00b3f4";
          swatch.style.setProperty("--orion-group-color", color);
        } else {
          swatch.style.setProperty("--orion-group-color", "#c5c5cc");
        }
        const name = document.createElement("span");
        name.className = "orion-tab-group-name";
        name.textContent = label;
        const countLabel = document.createElement("span");
        countLabel.className = "orion-tab-group-count";
        countLabel.textContent = String(count);
        option.append(swatch, name, countLabel);
        addTapHandler(option, event => {
          event.preventDefault();
          event.stopPropagation();
          activeGroupId = group?.id || null;
          logTouch("groups picker selected " + (group ? group.id : "all-tabs"));
          updateGroupsButton();
          closeGroupsPicker();
          rerenderGrid();
        });
        sheet.appendChild(option);
      };

      addOption("All Tabs", Array.from(gBrowser.tabs).filter(tab => !tab.closing).length);
      for (const group of getOpenTabGroups()) {
        addOption(groupName(group), group.tabs.filter(tab => !tab.closing).length, group);
      }

      addTapHandler(backdrop, event => {
        event.preventDefault();
        event.stopPropagation();
        closeGroupsPicker();
      });
      overlayEl.appendChild(backdrop);
      overlayEl.appendChild(sheet);
      requestAnimationFrame(() => {
        try {
          if (!sheet._orionPickerOpen) return;
          sheet.setAttribute("open", "");
          backdrop.style.opacity = "1";
        } catch (_) {}
      });
      logTouch("groups picker opened " + getOpenTabGroups().length + " groups");
    } catch (err) {
      logError("openGroupsPicker: " + err);
    }
  }

  function closeOverlay() {
    try {
      if (!overlayEl) return; // already closed / never opened — no-op
      // Guard against double-close: mark as closing so a second call during
      // the 200ms fade-out window is a no-op.
      if (overlayEl._orionClosing) return;
      overlayEl._orionClosing = true;
      _gridRenderGeneration++;
      closeGroupsPicker();

      const el = overlayEl;
      // Trigger the fade-out transition.  CSS on #orion-tab-grid-overlay already
      // declares transition: opacity 0.2s ease, transform 0.2s ease.
      el.style.opacity = "0";
      el.style.transform = "translateY(20px)";

      // Remove from DOM after the transition completes.  200ms matches the CSS
      // duration; a tiny extra slack avoids a frame-edge miss.
      setTimeout(() => {
        try {
          if (el.parentNode) el.parentNode.removeChild(el);
        } catch (_) {}
        // Only clear the module-global if it still points at us (openOverlay may
        // have already replaced it).
        if (overlayEl === el) overlayEl = null;
        // Remove nav-hide attribute so #nav-bar reappears
        try { document.documentElement.removeAttribute("orion-tabgrid-open"); } catch (_) {}
        logTouch("overlay closed");
      }, 200);
    } catch (err) {
      logError("closeOverlay: " + err);
      // Best-effort cleanup on error so we never strand the overlay.
      try {
        if (overlayEl && overlayEl.parentNode) {
          overlayEl.parentNode.removeChild(overlayEl);
        }
      } catch (_) {}
      overlayEl = null;
      try { document.documentElement.removeAttribute("orion-tabgrid-open"); } catch (_) {}
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
      const generation = ++_gridRenderGeneration;

      // Clear existing cards
      while (grid.firstChild) {
        grid.removeChild(grid.firstChild);
      }

      const tabs = filteredTabs();
      updateGroupsButton();
      logTouch("rerenderGrid: " + tabs.length + " tabs" +
        (activeGroupId ? " in group " + activeGroupId : " (all tabs)"));

      // Build cards in order (await each thumbnail sequentially to avoid
      // hammering the compositor; for v1 this is fine at <10 tabs)
      for (const tab of tabs) {
        try {
          const card = await buildCardForTab(tab);
          // A picker choice or a close can start a later render while a
          // PageThumbs capture is awaiting the compositor. Never append stale
          // cards into the newly selected group's grid.
          if (generation !== _gridRenderGeneration || !overlayEl || !grid.isConnected) {
            return;
          }
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

      // Dismiss OSK + address bar before building the overlay so the grid gets
      // full viewport height and the bottom bar is not obscured.
      try {
        if (gURLBar.view && gURLBar.view.isOpen) {
          gURLBar.view.close();
          logTouch("openOverlay: closed urlbar view");
        }
        gURLBar.blur();
        logTouch("openOverlay: blurred urlbar");
      } catch (blurErr) {
        logError("openOverlay: urlbar blur/close failed: " + blurErr);
      }

      // Hide #nav-bar + #TabsToolbar while grid is open (CSS keyed on attribute)
      try { document.documentElement.setAttribute("orion-tabgrid-open", ""); } catch (_) {}

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

      const groupsBtn = document.createElement("button");
      groupsBtn.id = "orion-tab-grid-groups";
      groupsBtn.type = "button";
      groupsBtn.textContent = "Groups";
      addTapHandler(groupsBtn, event => {
        event.preventDefault();
        event.stopPropagation();
        openGroupsPicker();
      });

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

      bottomBar.appendChild(groupsBtn);
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

      // Trigger the open transition: the overlay starts at opacity:0 /
      // translateY(20px) from CSS; flip to visible on the next frame so the
      // browser actually runs the 0.2s transition instead of snapping.
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          try {
            overlay.style.opacity = "1";
            overlay.style.transform = "translateY(0)";
          } catch (_) {}
        });
      });

      // Populate cards after DOM is live
      await rerenderGrid();
    } catch (err) {
      logError("openOverlay: " + err);
    }
  }

  // ── C1a: toolbar tab button ────────────────────────────────────────────────
  // Gate: SHOW_FAB keeps the floating ▦ code but prevents it rendering.
  const SHOW_FAB = false;

  // Overlapping-squares SVG for the tab button icon (Orion-style).
  const TAB_ICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
    <rect x="2" y="5" width="11" height="11" rx="2" stroke="currentColor" stroke-width="1.8" fill="none"/>
    <rect x="7" y="2" width="11" height="11" rx="2" stroke="currentColor" stroke-width="1.8" fill="none" style="fill:var(--toolbar-bgcolor,#1c1b22)"/>
  </svg>`;

  // Plus-in-circle SVG for the new-tab button (Orion-style).
  const NEWTAB_ICON_SVG = `<svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 20 20" fill="none">
    <path d="M10 4.5v11M4.5 10h11" stroke="currentColor" stroke-width="1.9" stroke-linecap="round"/>
  </svg>`;

  // Build a count-badge label, e.g. "3" or "9+" for many tabs.
  function tabCountLabel() {
    try {
      const n = gBrowser.tabs.length;
      return n > 9 ? "9+" : String(n);
    } catch (_) {
      return "?";
    }
  }

  let _toolbarBtn = null;
  let _newTabBtn  = null;

  // Update the tab count shown on the toolbar button.
  function updateToolbarCount() {
    try {
      if (!_toolbarBtn) return;
      const badge = _toolbarBtn.querySelector(".orion-tb-count");
      if (badge) badge.textContent = tabCountLabel();
    } catch (err) {
      logError("updateToolbarCount: " + err);
    }
  }

  // Shared cssText for the row-2 injected toolbarbuttons — a bare, touch-sized
  // flex button. Sizing/spacing (order, flex) is applied by toolbar-mobile.css
  // keyed on the element id; here we only set the intrinsic button chrome.
  const INJECTED_BTN_CSS = [
    "min-width:44px",
    "min-height:44px",
    "display:flex",
    "align-items:center",
    "justify-content:center",
    "flex-direction:column",
    "padding:0",
    "border:none",
    "background:transparent",
    "color:var(--toolbarbutton-icon-fill,currentColor)",
    "cursor:pointer",
    "-webkit-tap-highlight-color:transparent",
    "touch-action:manipulation",
    "position:relative",
  ].join(";");

  // C1b: inject the tab-grid button AND a new-tab button as DIRECT children of
  // #nav-bar, immediately before #PanelUI-button (the toolbaritem wrapping the
  // ≡ menu). They must be direct nav-bar children (not nested inside
  // #PanelUI-button) so the flex-wrap two-row layout in toolbar-mobile.css can
  // order them onto row 2. We deliberately do NOT reparent #PanelUI-menu-button
  // itself: it uses consumeanchor/delegatesanchor="PanelUI-button" for popup
  // anchoring, so moving it would misplace the app menu.
  //
  // Row-2 final order (via CSS `order`): back | forward | new-tab | tabs | menu.
  function injectToolbarButton() {
    try {
      if (_toolbarBtn) return true; // already injected

      // Anchor before the whole #PanelUI-button toolbaritem so we sit as
      // siblings of it directly under #nav-bar.
      const panelBtn = document.getElementById("PanelUI-button");
      const navBar   = document.getElementById("nav-bar");
      if (!panelBtn || !panelBtn.parentNode || !navBar) return false; // not ready

      // ── new-tab button ──────────────────────────────────────────────────────
      const nt = document.createElement("toolbarbutton");
      nt.id = "orion-newtab-toolbar-btn";
      nt.setAttribute("tooltiptext", "New tab");
      nt.setAttribute("class", "toolbarbutton-1 chromeclass-toolbar-additional");
      nt.style.cssText = INJECTED_BTN_CSS;
      const ntIcon = document.createElement("span");
      ntIcon.style.cssText = "display:flex;align-items:center;justify-content:center;width:20px;height:20px;pointer-events:none";
      ntIcon.innerHTML = NEWTAB_ICON_SVG;
      nt.appendChild(ntIcon);

      function openNewTab() {
        try {
          const tab = gBrowser.addTab("about:newtab", {
            triggeringPrincipal:
              Services.scriptSecurityManager.getSystemPrincipal(),
          });
          gBrowser.selectedTab = tab;
          // Focus the address bar so the user can type immediately.
          try { gURLBar.focus(); gURLBar.select(); } catch (_) {}
        } catch (err) {
          logError("openNewTab: " + err);
        }
      }
      nt.addEventListener("click", (e) => {
        logTouch("newtab btn click");
        e.preventDefault(); e.stopPropagation();
        openNewTab();
      }, { capture: true });
      nt.addEventListener("touchend", (e) => {
        logTouch("newtab btn touchend");
        e.preventDefault(); e.stopPropagation();
        openNewTab();
      }, { capture: true, passive: false });

      // ── tab-grid button ─────────────────────────────────────────────────────
      const btn = document.createElement("toolbarbutton");
      btn.id = "orion-tab-toolbar-btn";
      btn.setAttribute("tooltiptext", "Tab grid");
      btn.setAttribute("class", "toolbarbutton-1 chromeclass-toolbar-additional");
      btn.style.cssText = INJECTED_BTN_CSS;

      // Icon wrapper
      const iconWrap = document.createElement("span");
      iconWrap.style.cssText = "display:flex;align-items:center;justify-content:center;width:20px;height:20px;pointer-events:none";
      iconWrap.innerHTML = TAB_ICON_SVG;

      // Count badge — shown below the icon, overlaid like iOS
      const badge = document.createElement("span");
      badge.className = "orion-tb-count";
      badge.textContent = tabCountLabel();
      badge.style.cssText = [
        "position:absolute",
        "bottom:5px",
        "right:8px",
        "font-size:9px",
        "font-weight:700",
        "line-height:1",
        "color:var(--toolbarbutton-icon-fill,currentColor)",
        "pointer-events:none",
        "font-family:system-ui,sans-serif",
      ].join(";");

      btn.appendChild(iconWrap);
      btn.appendChild(badge);

      // Wire click + touchend (capture)
      btn.addEventListener("click", (e) => {
        logTouch("toolbar tab button click → openOverlay");
        e.preventDefault();
        e.stopPropagation();
        openOverlay().catch((err) => logError("openOverlay (toolbar btn click): " + err));
      }, { capture: true });

      btn.addEventListener("touchend", (e) => {
        logTouch("toolbar tab button touchend → openOverlay");
        e.preventDefault();
        e.stopPropagation();
        openOverlay().catch((err) => logError("openOverlay (toolbar btn touchend): " + err));
      }, { capture: true, passive: false });

      // Insert both as direct children of #nav-bar, before #PanelUI-button.
      panelBtn.parentNode.insertBefore(nt, panelBtn);
      panelBtn.parentNode.insertBefore(btn, panelBtn);
      _newTabBtn  = nt;
      _toolbarBtn = btn;

      logTouch("toolbar tab + newtab buttons injected");
      logError("toolbar tab + newtab buttons injected " + new Date().toISOString());

      // Keep count up-to-date when tabs are opened/closed/selected.
      try {
        gBrowser.tabContainer.addEventListener("TabOpen", updateToolbarCount);
        gBrowser.tabContainer.addEventListener("TabClose", updateToolbarCount);
        gBrowser.tabContainer.addEventListener("TabSelect", updateToolbarCount);
      } catch (err) {
        logError("toolbar btn tab listeners: " + err);
      }

      return true;
    } catch (err) {
      logError("injectToolbarButton: " + err);
      return false;
    }
  }

  // ── FIX 2: PanelUI menu button toggle — mousedown takeover ───────────────
  // ROOT CAUSE (confirmed by /tmp/ff-menu.log evidence): taps 2+ reopen the
  // panel via the button's low-level mousedown/command path, which NEVER reaches
  // our capture-phase CLICK handler.  The panel oscillates popupshown/popuphidden
  // 3× with no additional click events, so click-suppression is inert.
  //
  // FIX: take over the button at MOUSEDOWN (and touchstart, which fires first on
  // touch).  Always preventDefault+stopImmediatePropagation so the native
  // open/toggle machinery never runs.  Then decide manually:
  //   - if the panel is open/showing → close via PanelUI.hide()
  //   - if the panel just hid within 350ms (rollup fired on THIS press, so
  //     isOpen already reads false by the time we run) → close = no-op (don't
  //     reopen)
  //   - otherwise → open via PanelUI.show(event)
  // A shared _lastToggleAt gate prevents double-acting when both touchstart and
  // mousedown fire for the same physical tap (<100ms apart).
  //
  // PanelUI.show(aEvent) / PanelUI.hide() verified in FF150 panelUI.js.

  // Timestamps set by popup event listeners (ms, performance.now()).
  let _menuHiddenAt = -Infinity;
  let _menuShownAt  = -Infinity;
  // Guard: timestamp of last toggle action — prevents double-fire when both
  // touchstart and mousedown fire for the same physical tap.
  let _lastToggleAt = -Infinity;

  function wirePanelUIToggle() {
    try {
      const menuBtn = document.getElementById("PanelUI-menu-button");
      if (!menuBtn) {
        logError("wirePanelUIToggle: #PanelUI-menu-button not found, retrying");
        return false;
      }

      // Locate the popup node.  #appMenu-popup is the XUL panel in FF150.
      // PanelUI.panel is the same node but accessed via the global object.
      const appMenuPopup = document.getElementById("appMenu-popup") ||
                           (typeof PanelUI !== "undefined" && PanelUI.panel) ||
                           null;

      if (!appMenuPopup) {
        logError("wirePanelUIToggle: #appMenu-popup not found, retrying");
        return false;
      }

      logError("wirePanelUIToggle: popup node id=" + appMenuPopup.id +
               " tagName=" + appMenuPopup.tagName);

      // Track hidden/shown times — critical for the justHidden decision.
      appMenuPopup.addEventListener("popuphidden", () => {
        _menuHiddenAt = performance.now();
        appendLog("/tmp/ff-menu.log",
          new Date().toISOString() + " popuphidden ts=" + _menuHiddenAt.toFixed(1));
      });
      appMenuPopup.addEventListener("popupshown", () => {
        _menuShownAt = performance.now();
        appendLog("/tmp/ff-menu.log",
          new Date().toISOString() + " popupshown ts=" + _menuShownAt.toFixed(1));
      });

      // Shared handler used by both mousedown and touchstart.
      function handleTogglePress(e) {
        try {
          // Always kill the native open/toggle path.
          e.preventDefault();
          e.stopImmediatePropagation();

          const now = performance.now();

          // Double-fire guard: both touchstart and mousedown fire for one tap.
          if (now - _lastToggleAt < 100) {
            appendLog("/tmp/ff-menu.log",
              new Date().toISOString() + " " + e.type + " double-fire guard — skipped");
            return;
          }
          _lastToggleAt = now;

          const isOpen = appMenuPopup.state === "open" ||
                         appMenuPopup.state === "showing";
          // justHidden: the native rollup (light-dismiss) fires on mousedown BEFORE
          // our handler, so the panel may already read "closed" even though THIS
          // press is what caused it to close.  350ms window catches this.
          const justHidden = (now - _menuHiddenAt) < 350;

          let action;
          if (isOpen || justHidden) {
            action = "close";
            try {
              if (typeof PanelUI !== "undefined" && PanelUI.hide) {
                PanelUI.hide();
              } else {
                appMenuPopup.hidePopup();
              }
            } catch (hideErr) {
              logError("wirePanelUIToggle hide: " + hideErr);
            }
          } else {
            action = "open";
            try {
              if (typeof PanelUI !== "undefined" && PanelUI.show) {
                PanelUI.show(e);
              } else {
                // Fallback: open the popup directly anchored to the button.
                appMenuPopup.openPopup(menuBtn, "after_end", 0, 0, false, false, e);
              }
            } catch (showErr) {
              logError("wirePanelUIToggle show: " + showErr);
            }
          }

          appendLog("/tmp/ff-menu.log",
            new Date().toISOString() + " " + e.type +
            " isOpen=" + isOpen + " justHidden=" + justHidden +
            " action=" + action);
        } catch (err) {
          logError("wirePanelUIToggle handleTogglePress: " + err);
        }
      }

      menuBtn.addEventListener("touchstart", handleTogglePress,
        { capture: true, passive: false });
      menuBtn.addEventListener("mousedown", handleTogglePress,
        { capture: true });

      logError("wirePanelUIToggle: wired mousedown+touchstart takeover on #PanelUI-menu-button");
      return true;
    } catch (err) {
      logError("wirePanelUIToggle: " + err);
      return false;
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
    // C1a: FAB is retired in favour of the toolbar button. SHOW_FAB=false keeps
    // this code intact but prevents the button from rendering.
    if (!SHOW_FAB) return true; // pretend success so the poll loop never starts
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

      // C1a: inject toolbar tab button before ≡ in #nav-bar.
      // Poll until #PanelUI-menu-button is in the DOM (same pattern as FAB poll).
      if (!injectToolbarButton()) {
        const tbPollId = setInterval(() => {
          try {
            if (injectToolbarButton()) {
              clearInterval(tbPollId);
            }
          } catch (err) {
            logError("toolbar btn poll: " + err);
            clearInterval(tbPollId);
          }
        }, 300);
      }

      // FIX 2: wire PanelUI toggle — retry until #PanelUI-menu-button exists.
      if (!wirePanelUIToggle()) {
        const puPollId = setInterval(() => {
          try {
            if (wirePanelUIToggle()) {
              clearInterval(puPollId);
            }
          } catch (err) {
            logError("panelui toggle poll: " + err);
            clearInterval(puPollId);
          }
        }, 300);
        setTimeout(() => clearInterval(puPollId), 10000);
      }

      // Keep #alltabs-button interception wired (harmless; button is now hidden
      // with #TabsToolbar by CSS, but the observer is cheap to keep running).
      if (!wireAlltabsButton()) {
        logTouch("start: #alltabs-button not found, starting observer");
        watchForAlltabsButton();
      }

      // FAB: SHOW_FAB=false — ensureFloatingButton returns true immediately.
      if (!ensureFloatingButton()) {
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
