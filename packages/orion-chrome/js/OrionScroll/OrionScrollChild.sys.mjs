// Content-process half of the Orion scroll actor. This is intentionally a
// proof-only actor: it records the event streams needed by scroll-collapse and
// pull-to-refresh, but changes no UI and never prevents page input.

export class OrionScrollChild extends JSWindowActorChild {
  #lastTop = null;
  #installed = false;
  #chromeEventHandler = null;
  #scrollEvents = 0;
  #touchEvents = 0;
  #pointerEvents = 0;
  #touchMoves = 0;
  #pointerMoves = 0;

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

  #send(kind, extra = {}, force = false) {
    try {
      const top = this.#scrollTop();
      if (kind === "scroll" && !force && top === this.#lastTop) return;
      this.#lastTop = top;
      this.sendAsyncMessage("OrionScroll:position", {
        kind,
        top,
        uri: this.document.documentURI,
        scrollEvents: this.#scrollEvents,
        touchEvents: this.#touchEvents,
        pointerEvents: this.#pointerEvents,
        ...extra,
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

  #installListeners() {
    if (this.#installed) return;

    const contentWindow = this.contentWindow;
    const chromeEventHandler = this.docShell?.chromeEventHandler;
    contentWindow.addEventListener("scroll", this, {
      capture: true,
      passive: true,
    });

    if (chromeEventHandler) {
      const options = { capture: true, passive: true, mozSystemGroup: true };
      for (const type of [
        "touchstart", "touchmove", "touchend", "touchcancel",
        "pointerdown", "pointermove", "pointerup", "pointercancel",
      ]) {
        chromeEventHandler.addEventListener(type, this, options);
      }
      this.#chromeEventHandler = chromeEventHandler;
    }

    this.#installed = true;
    this.#send("listeners-installed", {
      chromeEventHandler: !!chromeEventHandler,
    }, true);
  }

  actorCreated() {
    try {
      this.#installListeners();
      this.#send("actor-created", {}, true);
    } catch (error) {
      this.#send("install-error", { error: String(error) }, true);
    }
  }

  handleEvent(event) {
    switch (event.type) {
      case "DOMContentLoaded":
      case "pageshow":
        this.#installListeners();
        this.#send(event.type, {}, true);
        break;
      case "scroll":
        this.#scrollEvents++;
        this.#send("scroll");
        break;
      case "touchstart":
      case "touchend":
      case "touchcancel": {
        this.#touchEvents++;
        const touch = event.touches?.[0] || event.changedTouches?.[0];
        this.#send(event.type, {
          x: touch ? Math.round(touch.clientX) : null,
          y: touch ? Math.round(touch.clientY) : null,
          touches: event.touches?.length ?? 0,
          defaultPrevented: event.defaultPrevented,
        }, true);
        break;
      }
      case "touchmove": {
        this.#touchEvents++;
        this.#touchMoves++;
        // Keep the proof log compact while retaining enough samples to measure
        // a pull. Always record the first move and then every fourth move.
        if (this.#touchMoves === 1 || this.#touchMoves % 4 === 0) {
          const touch = event.touches?.[0] || event.changedTouches?.[0];
          this.#send("touchmove", {
            x: touch ? Math.round(touch.clientX) : null,
            y: touch ? Math.round(touch.clientY) : null,
            touches: event.touches?.length ?? 0,
            move: this.#touchMoves,
            defaultPrevented: event.defaultPrevented,
          }, true);
        }
        break;
      }
      case "pointerdown":
      case "pointerup":
      case "pointercancel":
        this.#pointerEvents++;
        this.#send(event.type, {
          x: Math.round(event.clientX),
          y: Math.round(event.clientY),
          pointerType: event.pointerType,
        }, true);
        break;
      case "pointermove":
        this.#pointerEvents++;
        this.#pointerMoves++;
        if (this.#pointerMoves === 1 || this.#pointerMoves % 4 === 0) {
          this.#send("pointermove", {
            x: Math.round(event.clientX),
            y: Math.round(event.clientY),
            pointerType: event.pointerType,
            move: this.#pointerMoves,
          }, true);
        }
        break;
    }
  }

  receiveMessage(message) {
    if (message.name !== "OrionScroll:probe") return null;
    this.#installListeners();
    return {
      ok: true,
      uri: this.document.documentURI,
      top: this.#scrollTop(),
      installed: this.#installed,
      chromeEventHandler: !!this.#chromeEventHandler,
      scrollEvents: this.#scrollEvents,
      touchEvents: this.#touchEvents,
      pointerEvents: this.#pointerEvents,
    };
  }

  didDestroy() {
    try {
      this.contentWindow.removeEventListener("scroll", this, {
        capture: true,
      });
    } catch (_) {}

    if (this.#chromeEventHandler) {
      const options = { capture: true, mozSystemGroup: true };
      for (const type of [
        "touchstart", "touchmove", "touchend", "touchcancel",
        "pointerdown", "pointermove", "pointerup", "pointercancel",
      ]) {
        try {
          this.#chromeEventHandler.removeEventListener(type, this, options);
        } catch (_) {}
      }
    }
  }
}
