// ==UserScript==
// @name           loader-proof
// @namespace      orion-chrome/loader-proof
// @version        0.3.0
// @description    Bare import-time write to /tmp/ff-loader-proof.log.
//                 If this file exists after Firefox starts, the fx-autoconfig
//                 loader is running scripts.  No window hooks — executes at
//                 module import time so it proves the loader itself fires.
// ==/UserScript==

// Wrapped in an async IIFE so we can await IOUtils (fire-and-forget Promises
// can be GC'd before Gecko schedules them; the async IIFE keeps the chain alive).
// NOTE: do NOT use { mode: "append" } here — overwrite (default) is proven to
// work from chrome modules (urlbar-inspect uses it).  Append mode silently
// fails to create the file when it does not already exist in Firefox 150.
(async () => {
  try {
    await IOUtils.writeUTF8(
      "/tmp/ff-loader-proof.log",
      "loaded " + new Date().toISOString() + "\n"
    );
  } catch (_) {}
})();
