{
  lib,
  pkgs,
  config,
  ...
}:

{
  home.packages = [ pkgs.overview ];

  # Sign the .app bundle with Developer ID at activation time (nix build
  # can't access the login keychain, so signing must happen as the user).
  # Copies to ~/.local/share/Overview.app and signs in place.
  home.activation.signOverview = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    APP="$HOME/.local/share/Overview.app"
    SRC="${pkgs.overview}/Applications/Overview.app"
    IDENTITY="Developer ID Application: Daniel Miller (6NHZWHQX37)"

    rm -rf "$APP"
    cp -R "$SRC" "$APP"
    chmod -R u+w "$APP"
    /usr/bin/codesign --force --sign "$IDENTITY" \
      --identifier com.nix.overview \
      --options runtime \
      "$APP/Contents/MacOS/overview" 2>/dev/null && \
    /usr/bin/codesign --force --sign "$IDENTITY" \
      --identifier com.nix.overview \
      "$APP" 2>/dev/null && \
    echo "Overview.app signed with Developer ID" || \
    echo "Warning: could not sign Overview.app (Developer ID not in keychain?)"
  '';

  # Persistent daemon — launches the signed copy
  launchd.agents.overview = {
    enable = true;
    config = {
      ProgramArguments = [ "${config.home.homeDirectory}/.local/share/Overview.app/Contents/MacOS/overview" ];
      KeepAlive = true;
      RunAtLoad = true;
      EnvironmentVariables = {
        PATH = "${pkgs.yabai}/bin:${pkgs.jq}/bin:/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };

  # CLI toggle script
  home.file.".local/bin/toggle-overview" = {
    executable = true;
    text = ''
      #!/bin/bash
      pkill -SIGUSR1 overview
    '';
  };
}
