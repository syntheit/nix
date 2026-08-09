// OrionScroll actor registration. Loaded once by fx-autoconfig as a background
// ES module before browser windows run their normal userChrome scripts.

const ACTOR_NAME = "OrionScroll";

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
        scroll: { capture: true, passive: true },
      },
    },
    allFrames: false,
    includeChrome: false,
    matches: ["http://*/*", "https://*/*"],
    remoteTypes: ["web"],
    messageManagerGroups: ["browsers"],
  });
} catch (error) {
  // Duplicate registration during a same-session module reload is expected;
  // emit a diagnostic rather than allowing module loading to abort silently.
  try {
    await IOUtils.writeUTF8(
      "/tmp/ff-orion-actor.log",
      "OrionScroll registration failed: " + error + "\n"
    );
  } catch (_) {}
}
