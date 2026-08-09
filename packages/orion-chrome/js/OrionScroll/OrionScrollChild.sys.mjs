// Content-process half of the Orion scroll actor. This is intentionally a
// proof-only actor: it forwards real top-level scroll values but changes no UI.

export class OrionScrollChild extends JSWindowActorChild {
  #lastTop = null;

  #scrollTop() {
    try {
      const document = this.document;
      const window = this.contentWindow;
      return Math.max(
        window.scrollY || 0,
        document.documentElement?.scrollTop || 0,
        document.body?.scrollTop || 0
      );
    } catch (_) {
      return 0;
    }
  }

  #send(kind, force = false) {
    try {
      const top = this.#scrollTop();
      if (!force && top === this.#lastTop) return;
      this.#lastTop = top;
      this.sendAsyncMessage("OrionScroll:position", {
        kind,
        top,
        uri: this.document.documentURI,
      });
    } catch (error) {
      try {
        this.sendAsyncMessage("OrionScroll:position", {
          kind: "child-error",
          error: String(error),
        });
      } catch (_) {}
    }
  }

  actorCreated() {
    this.#send("actor-created", true);
  }

  handleEvent(event) {
    switch (event.type) {
      case "DOMContentLoaded":
      case "pageshow":
        this.#send(event.type, true);
        break;
      case "scroll":
        this.#send("scroll");
        break;
    }
  }
}
