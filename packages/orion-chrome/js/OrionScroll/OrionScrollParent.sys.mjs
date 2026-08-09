// Parent-process half of the Orion scroll actor. It deliberately logs every
// message before any Orion UI behavior is attached, so the actor transport is
// proven on-device before we add collapse or pull-to-refresh policy.

let logInitialized = false;

async function log(message) {
  try {
    const line = new Date().toISOString() + " " + message + "\n";
    if (logInitialized) {
      await IOUtils.writeUTF8("/tmp/ff-orion-actor.log", line, { mode: "append" });
    } else {
      logInitialized = true;
      await IOUtils.writeUTF8("/tmp/ff-orion-actor.log", line);
    }
  } catch (_) {}
}

export class OrionScrollParent extends JSWindowActorParent {
  receiveMessage(message) {
    try {
      const browser = this.browsingContext.top.embedderElement;
      const window = browser?.ownerGlobal;
      const selected = !!(window && browser === window.gBrowser.selectedBrowser);
      const data = message.data || {};
      log("parent " + (data.kind || "unknown") +
          " top=" + (data.top ?? "?") + " selected=" + selected);
    } catch (error) {
      log("parent error: " + error);
    }
  }
}
