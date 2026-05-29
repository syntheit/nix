{
  stdenv,
  writeText,
}:

let
  dylib_src = writeText "squarecorners.m" ''
    /*
     * square-corners dylib — injected via DYLD_INSERT_LIBRARIES.
     *
     * Swizzles NSThemeFrame, NSWindow, and _NSTitlebarDecorationView so that
     * every window in the host process is rendered with sharp corners on BOTH
     * top and bottom. The key trick (vs the 2026-04 attempt that only fixed
     * bottom corners) is _cornerMask returning a custom 1×1 black NSImage:
     * AppKit hands this image to WindowServer as the window's silhouette
     * mask, and the compositor uses it for the outline drawn against the
     * desktop. Returning nil (as the old build did) leaves the default
     * rounded mask in place. Borrowed from CornerFix by Mehmet T. AKALIN
     * (MIT) — see github.com/makalin/CornerFix.
     */
    #import <AppKit/AppKit.h>
    #import <objc/runtime.h>
    #import <objc/message.h>
    #include <string.h>

    static NSImage *gSquareMask = nil;

    static NSImage *squareCornerMaskImage(void) {
        if (gSquareMask == nil) {
            gSquareMask = [NSImage imageWithSize:NSMakeSize(1.0, 1.0)
                                         flipped:NO
                                  drawingHandler:^BOOL(NSRect r) {
                [[NSColor blackColor] set];
                [[NSBezierPath bezierPathWithRect:r] fill];
                return YES;
            }];
            gSquareMask.capInsets = NSEdgeInsetsMake(0, 0, 0, 0);
            gSquareMask.resizingMode = NSImageResizingModeStretch;
        }
        return gSquareMask;
    }

    static double zeroRadius(id self, SEL _cmd) { return 0.0; }
    static CGSize zeroSize(id self, SEL _cmd) { return CGSizeMake(0.0, 0.0); }
    static id squareMask(id self, SEL _cmd) { return squareCornerMaskImage(); }
    static void noOp(id self, SEL _cmd) { }

    static void swizzle(Class cls, const char *name, IMP imp) {
        Method m = class_getInstanceMethod(cls, sel_registerName(name));
        if (m) method_setImplementation(m, imp);
    }

    /* Setters get rewritten to call the original with 0 so the window's
       internal radius ivars stay consistent (some AppKit code paths read
       them back). Each setter captures its own original IMP. */
    static void swizzleSetterToZero(Class cls, const char *name) {
        SEL sel = sel_registerName(name);
        Method m = class_getInstanceMethod(cls, sel);
        if (!m) return;
        typedef void (*SetIMP)(id, SEL, double);
        SetIMP orig = (SetIMP)method_getImplementation(m);
        IMP newImp = imp_implementationWithBlock(^(id self, double radius) {
            orig(self, sel, 0.0);
        });
        method_setImplementation(m, newImp);
    }

    static const char *hostBundleID(void) {
        id main = [NSBundle mainBundle];
        if (!main) return NULL;
        NSString *bid = [main bundleIdentifier];
        return bid ? [bid UTF8String] : NULL;
    }

    __attribute__((constructor))
    static void init(void) {
        /* Bundle-ID guard: refuse to swizzle in Apple system apps and known
           fragile browsers. With per-app LSEnvironment injection this should
           never fire in practice, but keep it as belt-and-braces. */
        const char *bid = hostBundleID();
        if (bid) {
            if (strncmp(bid, "com.apple.", 10) == 0) return;
            if (strncmp(bid, "org.mozilla.", 12) == 0) return;
            if (strncmp(bid, "app.zen-browser", 15) == 0) return;
        }

        Class themeFrame = objc_getClass("NSThemeFrame");
        if (themeFrame) {
            swizzle(themeFrame, "_cornerRadius", (IMP)zeroRadius);
            swizzle(themeFrame, "_getCachedWindowCornerRadius", (IMP)zeroRadius);
            swizzle(themeFrame, "_topCornerSize", (IMP)zeroSize);
            swizzle(themeFrame, "_bottomCornerSize", (IMP)zeroSize);
            swizzle(themeFrame, "_continuousCornerRadius", (IMP)zeroRadius);
            swizzle(themeFrame, "_cornerMask", (IMP)squareMask);
        }

        Class window = objc_getClass("NSWindow");
        if (window) {
            swizzle(window, "_cornerRadius", (IMP)zeroRadius);
            swizzle(window, "_effectiveCornerRadius", (IMP)zeroRadius);
            swizzle(window, "_topCornerRadius", (IMP)zeroRadius);
            swizzle(window, "_bottomCornerRadius", (IMP)zeroRadius);
            swizzle(window, "_cornerMask", (IMP)squareMask);
            /* Don't call original — it reapplies the default rounded mask. */
            swizzle(window, "_updateCornerMask", (IMP)noOp);

            swizzleSetterToZero(window, "_setCornerRadius:");
            swizzleSetterToZero(window, "_setEffectiveCornerRadius:");
            swizzleSetterToZero(window, "_setContinuousCornerRadius:");
            swizzleSetterToZero(window, "_setContentCornerRadius:");
        }

        /* NOTE: _NSTitlebarDecorationView drawRect: is intentionally NOT
           swizzled. apple-sharpener and CornerFix only suppress it for
           non-zero custom radii; for radius 0 the original needs to run
           so the titlebar content fills the now-square corners — no-oping
           it leaves gray "ears" where the corners used to be rounded. */
    }
  '';
in
stdenv.mkDerivation {
  name = "square-corners";
  inherit dylib_src;
  unpackPhase = "true";
  buildPhase = ''
    # Fat binary supporting arm64 and arm64e. arm64e is needed for any host
    # process built with pointer authentication (Apple-signed apps); without
    # it dyld terminates the host before our constructor runs. Per-app
    # injection means we mostly target arm64-only third-party apps, but
    # keep both for safety.
    clang -dynamiclib -lobjc -fobjc-arc \
      -arch arm64 -arch arm64e \
      -framework AppKit \
      -framework CoreGraphics \
      -framework Foundation \
      -O2 -o libsquarecorners.dylib $dylib_src
  '';
  installPhase = ''
    mkdir -p $out/lib
    cp libsquarecorners.dylib $out/lib/
  '';
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
