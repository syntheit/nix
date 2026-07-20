// ==UserScript==
// @name           loader-proof
// @namespace      orion-chrome/loader-proof
// @version        0.1.0
// @description    Bare import-time write to /tmp/ff-loader-proof.log.
//                 If this file exists after Firefox starts, the fx-autoconfig
//                 loader is running scripts.  No window hooks — executes at
//                 module import time so it proves the loader itself fires.
// ==/UserScript==

// Top-level module code: runs the moment this .uc.mjs is imported by the
// module_loader.mjs inside a window context.
try {
  IOUtils.writeUTF8(
    "/tmp/ff-loader-proof.log",
    "loaded " + new Date().toISOString() + "\n",
    { mode: "append" }
  );
} catch (_) {}
