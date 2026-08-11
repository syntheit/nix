// Parent-process half of the Orion scroll actor. It deliberately logs every
// message before any Orion UI behavior is attached, so the actor transport is
// proven on-device before we add collapse or pull-to-refresh policy.

let logInitialized = false;
let logChain = Promise.resolve();

function log(message) {
  logChain = logChain.then(async () => {
    const line = new Date().toISOString() + " " + message + "\n";
    if (logInitialized) {
      await IOUtils.writeUTF8("/tmp/ff-orion-actor.log", line, { mode: "append" });
    } else {
      logInitialized = true;
      await IOUtils.writeUTF8("/tmp/ff-orion-actor.log", line);
    }
  }).catch(error => {
    console.error("[OrionScroll] actor log failed", error);
  });
}

export class OrionScrollParent extends JSWindowActorParent {
  receiveMessage(message) {
    try {
      const browser = this.browsingContext.top.embedderElement;
      const window = browser?.ownerGlobal;
      const selected = !!(window && browser === window.gBrowser.selectedBrowser);
      const data = message.data || {};
      log("parent " + (data.kind || "unknown") +
          " top=" + (data.top ?? "?") + " selected=" + selected +
          " scroll=" + (data.scrollEvents ?? "?") +
          " touch=" + (data.touchEvents ?? "?") +
          " pointer=" + (data.pointerEvents ?? "?") +
          (data.x == null ? "" : " x=" + data.x) +
          (data.y == null ? "" : " y=" + data.y) +
          (data.move == null ? "" : " move=" + data.move) +
          (data.touches == null ? "" : " touches=" + data.touches) +
          (data.pointerType ? " pointerType=" + data.pointerType : "") +
          (data.chromeEventHandler == null ? "" :
            " chromeEventHandler=" + data.chromeEventHandler) +
          (data.error ? " error=" + data.error : ""));
    } catch (error) {
      log("parent error: " + error);
    }
  }
}
