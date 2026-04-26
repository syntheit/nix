{
  stdenv,
  writeText,
}:

let
  dylib_src = writeText "squarecorners.m" ''
    /*
     * square-corners dylib — injected via DYLD_INSERT_LIBRARIES
     * Swizzles NSThemeFrame and NSWindow to return 0 for corner radius.
     * This makes BOTTOM corners truly square on third-party apps.
     * Top corners are handled by a separate overlay daemon.
     */
    #import <objc/runtime.h>
    #import <objc/message.h>
    #include <CoreGraphics/CGGeometry.h>

    static double zeroRadius(id self, SEL _cmd) { return 0.0; }
    static CGSize zeroSize(id self, SEL _cmd) { return CGSizeMake(0.0, 0.0); }
    static void* nilReturn(id self, SEL _cmd) { return NULL; }

    static void swizzle(Class cls, const char *name, IMP imp) {
        Method m = class_getInstanceMethod(cls, sel_registerName(name));
        if (m) method_setImplementation(m, imp);
    }

    __attribute__((constructor))
    static void init(void) {
        Class themeFrame = objc_getClass("NSThemeFrame");
        if (!themeFrame) return;

        swizzle(themeFrame, "_cornerRadius", (IMP)zeroRadius);
        swizzle(themeFrame, "_getCachedWindowCornerRadius", (IMP)zeroRadius);
        swizzle(themeFrame, "_topCornerSize", (IMP)zeroSize);
        swizzle(themeFrame, "_bottomCornerSize", (IMP)zeroSize);
        swizzle(themeFrame, "_continuousCornerRadius", (IMP)zeroRadius);
        swizzle(themeFrame, "_cornerMask", (IMP)nilReturn);

        Class window = objc_getClass("NSWindow");
        if (window) {
            swizzle(window, "_cornerRadius", (IMP)zeroRadius);
            swizzle(window, "_effectiveCornerRadius", (IMP)zeroRadius);
            swizzle(window, "_cornerMask", (IMP)nilReturn);

            SEL setSel = sel_registerName("_setCornerRadius:");
            Method setMethod = class_getInstanceMethod(window, setSel);
            if (setMethod) {
                typedef void (*SetIMP)(id, SEL, double);
                static SetIMP origSet = NULL;
                origSet = (SetIMP)method_getImplementation(setMethod);
                IMP newSet = imp_implementationWithBlock(^(id self, double radius) {
                    origSet(self, setSel, 0.0);
                });
                method_setImplementation(setMethod, newSet);
            }
        }
    }
  '';

  overlay_src = writeText "overlay.swift" ''
    /*
     * square-corners overlay — draws black triangles over the TOP corners
     * of tiled windows to cover the compositor-level rounding that the
     * dylib can't fix. Bottom corners are handled by the dylib.
     */
    import AppKit

    let kR: CGFloat = 11  // match macOS ~10pt window corner radius + margin

    struct WinRect: Equatable {
        let x, y, w, h: CGFloat
    }

    func queryWindows() -> [WinRect] {
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/run/current-system/sw/bin/yabai")
        p.arguments = ["-m", "query", "--windows", "--space"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let wins = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return wins.compactMap { w in
            guard let f = w["frame"] as? [String: Any],
                  let x = f["x"] as? Double, let y = f["y"] as? Double,
                  let ww = f["w"] as? Double, let hh = f["h"] as? Double,
                  let floating = w["is-floating"] as? Int, floating == 0,
                  let minimized = w["is-minimized"] as? Int, minimized == 0
            else { return nil }
            return WinRect(x: CGFloat(x), y: CGFloat(y), w: CGFloat(ww), h: CGFloat(hh))
        }
    }

    class CornerView: NSView {
        var windows: [WinRect] = []

        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let screenH = bounds.height
            let r = kR

            ctx.setFillColor(NSColor.black.cgColor)

            for win in windows {
                let left = win.x
                let right = win.x + win.w
                let top = screenH - win.y

                // Top-left ear
                var cp = CGMutablePath()
                cp.addRect(CGRect(x: left, y: top - r, width: r, height: r))
                cp.move(to: CGPoint(x: left + r, y: top - r))
                cp.addArc(center: CGPoint(x: left + r, y: top - r), radius: r,
                          startAngle: .pi / 2, endAngle: .pi, clockwise: false)
                cp.closeSubpath()
                ctx.addPath(cp); ctx.fillPath(using: .evenOdd)

                // Top-right ear
                cp = CGMutablePath()
                cp.addRect(CGRect(x: right - r, y: top - r, width: r, height: r))
                cp.move(to: CGPoint(x: right - r, y: top - r))
                cp.addArc(center: CGPoint(x: right - r, y: top - r), radius: r,
                          startAngle: .pi / 2, endAngle: 0, clockwise: true)
                cp.closeSubpath()
                ctx.addPath(cp); ctx.fillPath(using: .evenOdd)
            }
        }
    }

    class OverlayWindow: NSWindow {
        let cornerView: CornerView

        init(screen: NSScreen) {
            cornerView = CornerView(frame: screen.frame)
            super.init(contentRect: screen.frame, styleMask: [.borderless],
                       backing: .buffered, defer: false)
            self.level = .screenSaver
            self.isOpaque = false
            self.backgroundColor = .clear
            self.ignoresMouseEvents = true
            self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            self.hasShadow = false
            self.contentView = cornerView
        }

        func refresh() {
            let newWindows = queryWindows()
            if newWindows != cornerView.windows {
                cornerView.windows = newWindows
                cornerView.needsDisplay = true
            }
        }
    }

    class AppDelegate: NSObject, NSApplicationDelegate {
        var overlay: OverlayWindow!

        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApp.setActivationPolicy(.accessory)
            guard let screen = NSScreen.main else { return }
            overlay = OverlayWindow(screen: screen)
            overlay.orderFrontRegardless()
            overlay.refresh()

            Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.overlay.refresh()
            }

            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self?.overlay.refresh()
                }
            }
        }
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
  '';
in
stdenv.mkDerivation {
  name = "square-corners";
  inherit dylib_src overlay_src;
  unpackPhase = "true";
  buildPhase = ''
    # Build the dylib (Objective-C)
    clang -dynamiclib -lobjc \
      -framework CoreGraphics \
      -framework Foundation \
      -O2 -o libsquarecorners.dylib $dylib_src

    # Build the overlay daemon (Swift)
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    export PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH
    swiftc -O \
      -sdk $SDKROOT \
      -framework AppKit \
      -o square-corners-overlay \
      $overlay_src
  '';
  installPhase = ''
    mkdir -p $out/lib $out/bin
    cp libsquarecorners.dylib $out/lib/
    cp square-corners-overlay $out/bin/
  '';
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
