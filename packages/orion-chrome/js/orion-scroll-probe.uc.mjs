// ==UserScript==
// @name           orion-scroll-probe
// @namespace      orion-chrome/scroll-probe
// @version        1.0.0
// @description    One-shot parent-to-child JSWindowActor transport proof.
// @include        main
// ==/UserScript==

(async () => {
  const LOG = "/tmp/ff-orion-probe.log";

  async function write(message) {
    try {
      await IOUtils.writeUTF8(
        LOG,
        new Date().toISOString() + " " + message + "\n"
      );
    } catch (_) {}
  }

  await write("probe-script-enter");

  try {
    let browser = null;
    let actor = null;

    // Session restore and delayed browser startup can leave the selected
    // WindowGlobal unavailable briefly. Poll for at most 15 seconds.
    for (let attempt = 1; attempt <= 60; attempt++) {
      browser = globalThis.gBrowser?.selectedBrowser || null;
      const global = browser?.browsingContext?.currentWindowGlobal;
      if (global) {
        try {
          actor = global.getActor("OrionScroll");
          if (actor) break;
        } catch (_) {}
      }
      await new Promise(resolve => setTimeout(resolve, 250));
    }

    if (!actor) {
      await write("probe-error actor-unavailable");
      return;
    }

    const result = await actor.sendQuery("OrionScroll:probe", {
      requestedAt: Date.now(),
    });
    await write("probe-ok " + JSON.stringify(result));
  } catch (error) {
    await write(
      "probe-error " + (error?.name || "Error") + ": " +
      (error?.message || String(error)) +
      (error?.stack ? "\n" + error.stack : "")
    );
  }
})();
