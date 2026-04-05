{
  stdenv,
  writeText,
}:

let
  src = writeText "main.c" ''
    #include <ApplicationServices/ApplicationServices.h>

    CGEventRef callback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *refcon) {
        CGPoint location = CGEventGetLocation(event);
        if (location.y <= 1.0) {
            location.y = 2.0;
            CGEventSetLocation(event, location);
        }
        return event;
    }

    int main() {
        CFMachPortRef eventTap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            0,
            CGEventMaskBit(kCGEventMouseMoved) | CGEventMaskBit(kCGEventLeftMouseDragged),
            callback,
            NULL
        );

        if (!eventTap) {
            return 1;
        }

        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CGEventTapEnable(eventTap, true);
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
