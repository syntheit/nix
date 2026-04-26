{
  stdenv,
  writeText,
}:

let
  src = writeText "main.c" ''
    #include <ApplicationServices/ApplicationServices.h>
    #include <stdio.h>
    #include <unistd.h>

    static int fnHeld = 0;
    static CFMachPortRef gTap = NULL;

    CGEventRef callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
            CGEventTapEnable(gTap, true);
            return event;
        }

        if (type == kCGEventFlagsChanged) {
            fnHeld = (CGEventGetFlags(event) & kCGEventFlagMaskSecondaryFn) != 0;
            return event;
        }

        if (!fnHeld) {
            CGPoint loc = CGEventGetLocation(event);
            if (loc.y <= 10.0) {
                loc.y = 11.0;
                CGEventSetLocation(event, loc);
            }
        }
        return event;
    }

    int main() {
        CGEventMask mask = CGEventMaskBit(kCGEventMouseMoved)
                         | CGEventMaskBit(kCGEventLeftMouseDragged)
                         | CGEventMaskBit(kCGEventFlagsChanged);

        for (int attempt = 0; !gTap; attempt++) {
            gTap = CGEventTapCreate(
                kCGSessionEventTap,
                kCGHeadInsertEventTap,
                0,
                mask,
                callback,
                NULL
            );
            if (!gTap) {
                int delay = attempt < 5 ? 2 : 10;
                fprintf(stderr, "menubar-blocker: waiting for Accessibility permission (retry in %ds)\n", delay);
                sleep(delay);
            }
        }

        CFRunLoopSourceRef src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, gTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, kCFRunLoopCommonModes);
        CGEventTapEnable(gTap, true);

        fprintf(stderr, "menubar-blocker: running (hold fn + mouse to top edge to reveal)\n");
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
