{ lib, pkgs, ... }:

# Patches /Applications/*.app/Contents/Info.plist to inject the square-corners
# dylib via LSEnvironment.DYLD_INSERT_LIBRARIES. This is the only viable
# injection vector on modern macOS — global launchctl-setenv blows up
# hardened-runtime processes (Dock, Finder, Preview), and apps here are
# launched via `open -a` from skhd, which uses Launch Services (not the
# shell), so a wrapper script in PATH would never see them.
#
# Side effects:
#   - Patched apps lose their codesignature. Fine for non-hardened Homebrew
#     casks (Ghostty, Marta); they'll still launch.
#   - Homebrew updates re-install the .app and overwrite Info.plist. The
#     next darwin-rebuild re-applies the patch. Patch is idempotent.
#   - Apple system apps and any app with hardened runtime + library
#     validation MUST NOT be added to targetApps — dyld will terminate them
#     before the dylib's bundle-ID guard runs.

let
  dylib = "${pkgs.square-corners}/lib/libsquarecorners.dylib";
  targetApps = [
    "/Applications/Ghostty.app"
  ];
in
{
  system.activationScripts.postActivation.text = lib.mkAfter ''
    DYLIB="${dylib}"
    # shellcheck disable=SC2043
    for app in ${lib.escapeShellArgs targetApps}; do
      plist="$app/Contents/Info.plist"
      if [ ! -f "$plist" ]; then
        echo "[sharp-corners] $plist not found, skipping"
        continue
      fi

      current=$(/usr/libexec/PlistBuddy -c "Print :LSEnvironment:DYLD_INSERT_LIBRARIES" "$plist" 2>/dev/null || true)
      if [ "$current" = "$DYLIB" ]; then
        continue
      fi

      /usr/libexec/PlistBuddy -c "Print :LSEnvironment" "$plist" >/dev/null 2>&1 \
        || /usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$plist"
      /usr/libexec/PlistBuddy -c "Delete :LSEnvironment:DYLD_INSERT_LIBRARIES" "$plist" 2>/dev/null || true
      /usr/libexec/PlistBuddy -c "Add :LSEnvironment:DYLD_INSERT_LIBRARIES string $DYLIB" "$plist"

      # Force Launch Services to reread LSEnvironment for the next launch.
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app" 2>/dev/null || true
      echo "[sharp-corners] patched $app"
    done
  '';
}
