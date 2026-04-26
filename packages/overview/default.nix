{
  stdenv,
}:

stdenv.mkDerivation {
  pname = "overview";
  version = "0.1.0";
  src = ./src;
  unpackPhase = "true";
  dontStrip = true;
  buildPhase = ''
    # Use system Swift compiler with macOS 26 SDK for liquid glass APIs
    export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
    export PATH=/Library/Developer/CommandLineTools/usr/bin:$PATH
    swiftc -O \
      -sdk $SDKROOT \
      -framework AppKit \
      -framework SwiftUI \
      -framework CoreGraphics \
      -framework ScreenCaptureKit \
      -framework QuartzCore \
      -o overview \
      $src/*.swift
  '';
  installPhase = ''
    APP=$out/Applications/Overview.app/Contents
    mkdir -p $APP/MacOS
    cp overview $APP/MacOS/overview

    cat > $APP/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.nix.overview</string>
    <key>CFBundleName</key>
    <string>Overview</string>
    <key>CFBundleExecutable</key>
    <string>overview</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Overview needs screen recording to show window previews.</string>
</dict>
</plist>
PLIST

    mkdir -p $out/bin
    ln -s $APP/MacOS/overview $out/bin/overview
  '';
  meta.platforms = [ "aarch64-darwin" "x86_64-darwin" ];
}
