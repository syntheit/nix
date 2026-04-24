{
  stdenv,
  writeText,
}:

let
  src = writeText "main.c" ''
    #include <ApplicationServices/ApplicationServices.h>

    static int fnHeld = 0;
    static CFMachPortRef gTap = NULL;

    CGEventRef callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        /* Re-enable tap if macOS disabled it (timeout or user-input guard) */
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            CGEventTapEnable(gTap, true);
            return event;
        }

        /* Track fn/Globe key state */
        if (type == kCGEventFlagsChanged) {
            fnHeld = (CGEventGetFlags(event) & kCGEventFlagMaskSecondaryFn) != 0;
            return event;
        }

        /* Block mouse from reaching menubar trigger zone unless fn is held */
        if (!fnHeld) {
            CGPoint location = CGEventGetLocation(event);
            if (location.y <= 1.0) {
                location.y = 2.0;
                CGEventSetLocation(event, location);
            }
        }
        return event;
    }

    int main() {
        CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved)
                         | CGEventMaskBit(kCGEventLeftMouseDragged)
                         | CGEventMaskBit(kCGEventFlagsChanged);

        gTap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            0,
            mask,
            callback,
            NULL
        );

        if (!gTap) return 1;

        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
        CGEventTapEnable(gTap, true);
        CFRunLoopRun();
        return 0;
    }
  '';
in
stdenv.mkDerivation {
  name = "menubar-blocker";
  inherit src;
  buildInputs = [ ];
  unpackPhase = "true";
  buildPhase = "clang -framework ApplicationServices -O2 -o menubar-blocker $src";
  installPhase = "mkdir -p $out/bin; cp menubar-blocker $out/bin/";
}
