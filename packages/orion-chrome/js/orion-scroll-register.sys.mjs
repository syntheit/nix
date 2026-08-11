// OrionScroll actor registration. Loaded once by fx-autoconfig as a background
// ES module before browser windows run their normal userChrome scripts.
//
// IMPORTANT: fx-autoconfig loads .sys.mjs files synchronously through
// ChromeUtils.importESModule(), so this module must not contain top-level await.

const ACTOR_NAME = "OrionScroll";
const REGISTER_LOG = "/tmp/ff-orion-register.log";

const registrationLog = [
  new Date().toISOString() + " module-enter actor=" + ACTOR_NAME,
];

try {
  ChromeUtils.registerWindowActor(ACTOR_NAME, {
    parent: {
      esModuleURI: "chrome://userscripts/content/OrionScroll/OrionScrollParent.sys.mjs",
    },
    child: {
      esModuleURI: "chrome://userscripts/content/OrionScroll/OrionScrollChild.sys.mjs",
      // JSWindowActors, unlike legacy frame scripts, are the Fission/APZ-safe
      // channel for content events. This probe observes only top-level web docs.
      events: {
        DOMContentLoaded: { capture: true },
        pageshow: { capture: true },
      },
    },
    allFrames: false,
    includeChrome: false,
    matches: ["http://*/*", "https://*/*"],
    remoteTypes: ["web"],
    messageManagerGroups: ["browsers"],
  });
  registrationLog.push(new Date().toISOString() + " register-ok");
} catch (error) {
  registrationLog.push(
    new Date().toISOString() + " register-error " +
    (error?.name || "Error") + ": " + (error?.message || String(error)) +
    (error?.stack ? "\n" + error.stack : "")
  );
}

// Fire-and-forget is deliberate: top-level await would prevent this system
// module from loading at all. One overwrite contains both entry and result, so
// there is no append-before-create race and the file is an unambiguous proof.
try {
  IOUtils.writeUTF8(REGISTER_LOG, registrationLog.join("\n") + "\n").catch(
    error => console.error("[OrionScroll] registration log failed", error)
  );
} catch (error) {
  console.error("[OrionScroll] registration log threw", error);
}
