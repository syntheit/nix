{
  stdenv,
  writeText,
}:

let
  src = writeText "squarecorners.m" ''
    #import <objc/runtime.h>
    #import <objc/message.h>
    #include <CoreGraphics/CGGeometry.h>
    #include <stdio.h>

    static BOOL enabled = YES;

    /* Check if window is a standard app window (not menus, tooltips, etc) */
    static inline BOOL isStandardAppWindow(id window) {
        if (!window) return NO;
        unsigned long mask = ((unsigned long(*)(id,SEL))objc_msgSend)(
            window, sel_registerName("styleMask"));
        /* Must be titled */
        if (!(mask & (1 << 0))) return NO;  /* NSWindowStyleMaskTitled */
        /* Skip HUD and utility windows */
        if (mask & (1 << 13)) return NO;  /* NSWindowStyleMaskHUDWindow */
        if (mask & (1 << 4)) return NO;   /* NSWindowStyleMaskUtilityWindow */
        /* Must be normal window level */
        long level = ((long(*)(id,SEL))objc_msgSend)(window, sel_registerName("level"));
        if (level != 0) return NO;  /* NSNormalWindowLevel = 0 */
        return YES;
    }

    /* Apply corner radius via KVC — this goes through the full internal path
       including notifying WindowServer */
    static void applySquareCorners(id window) {
        if (!window || !enabled) return;
        if (!isStandardAppWindow(window)) return;

        /* [window setValue:@(0) forKey:@"cornerRadius"] */
        id zero = ((id(*)(Class,SEL,int))objc_msgSend)(
            objc_getClass("NSNumber"), sel_registerName("numberWithInteger:"), 0);
        id key = ((id(*)(Class,SEL,const char*))objc_msgSend)(
            objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"), "cornerRadius");
        ((void(*)(id,SEL,id,id))objc_msgSend)(
            window, sel_registerName("setValue:forKey:"), zero, key);
        /* Force shadow redraw to match new shape */
        ((void(*)(id,SEL))objc_msgSend)(window, sel_registerName("invalidateShadow"));
    }

    static void swizzle(Class cls, const char *name, IMP newImp, IMP *origOut) {
        Method m = class_getInstanceMethod(cls, sel_registerName(name));
        if (!m) return;
        if (origOut) *origOut = method_getImplementation(m);
        method_setImplementation(m, newImp);
        fprintf(stderr, "[square-corners] swizzled %s on %s\n", name, class_getName(cls));
    }

    /* Swizzled _setCornerRadius: — force to 0 then call original */
    static IMP orig_setCornerRadius = NULL;
    static void hook_setCornerRadius(id self, SEL _cmd, double radius) {
        if (!isStandardAppWindow(self)) {
            ((void(*)(id,SEL,double))orig_setCornerRadius)(self, _cmd, radius);
            return;
        }
        ((void(*)(id,SEL,double))orig_setCornerRadius)(self, _cmd, 0.0);
    }

    /* Swizzled _updateCornerMask — call original then reapply our radius */
    static IMP orig_updateCornerMask = NULL;
    static void hook_updateCornerMask(id self, SEL _cmd) {
        ((void(*)(id,SEL))orig_updateCornerMask)(self, _cmd);
        applySquareCorners(self);
    }

    /* Swizzled setFrame:display: — call original then reapply */
    static IMP orig_setFrame = NULL;
    static void hook_setFrame(id self, SEL _cmd, CGRect frame, int display) {
        ((void(*)(id,SEL,CGRect,int))orig_setFrame)(self, _cmd, frame, display);
        applySquareCorners(self);
    }

    __attribute__((constructor))
    static void init(void) {
        Class window = objc_getClass("NSWindow");
        if (!window) return;
        fprintf(stderr, "[square-corners] loaded\n");

        /* Swizzle NSWindow methods */
        swizzle(window, "_setCornerRadius:", (IMP)hook_setCornerRadius, &orig_setCornerRadius);
        swizzle(window, "_updateCornerMask", (IMP)hook_updateCornerMask, &orig_updateCornerMask);
        swizzle(window, "setFrame:display:", (IMP)hook_setFrame, &orig_setFrame);

        /* Listen for window activation events to apply corners */
        id center = ((id(*)(id,SEL))objc_msgSend)(
            objc_getClass("NSNotificationCenter"), sel_registerName("defaultCenter"));

        id mainNote = ((id(*)(Class,SEL,const char*))objc_msgSend)(
            objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
            "NSWindowDidBecomeMainNotification");
        id keyNote = ((id(*)(Class,SEL,const char*))objc_msgSend)(
            objc_getClass("NSString"), sel_registerName("stringWithUTF8String:"),
            "NSWindowDidBecomeKeyNotification");

        void (^handler)(id) = ^(id notification) {
            id window = ((id(*)(id,SEL))objc_msgSend)(notification, sel_registerName("object"));
            applySquareCorners(window);
        };

        ((void(*)(id,SEL,id,id,id,id))objc_msgSend)(
            center, sel_registerName("addObserverForName:object:queue:usingBlock:"),
            mainNote, nil, nil, handler);
        ((void(*)(id,SEL,id,id,id,id))objc_msgSend)(
            center, sel_registerName("addObserverForName:object:queue:usingBlock:"),
            keyNote, nil, nil, handler);

        /* Apply to any already-existing windows */
        id app = ((id(*)(id,SEL))objc_msgSend)(
            objc_getClass("NSApplication"), sel_registerName("sharedApplication"));
        if (app) {
            id windows = ((id(*)(id,SEL))objc_msgSend)(app, sel_registerName("windows"));
            if (windows) {
                long count = ((long(*)(id,SEL))objc_msgSend)(windows, sel_registerName("count"));
                for (long i = 0; i < count; i++) {
                    id w = ((id(*)(id,SEL,long))objc_msgSend)(
                        windows, sel_registerName("objectAtIndex:"), i);
                    applySquareCorners(w);
                }
            }
        }

        fprintf(stderr, "[square-corners] done — notifications registered\n");
    }
  '';
in
stdenv.mkDerivation {
  name = "square-corners";
  inherit src;
  unpackPhase = "true";
  buildPhase = ''
    clang -dynamiclib -lobjc \
      -framework CoreGraphics \
      -framework Foundation \
      -F/System/Library/PrivateFrameworks -framework SkyLight \
      -O2 -o libsquarecorners.dylib $src
  '';
  installPhase = "mkdir -p $out/lib; cp libsquarecorners.dylib $out/lib/";
}
