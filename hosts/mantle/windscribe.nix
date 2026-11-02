{
  lib,
  pkgs,
  vars,
  ...
}:

# Windscribe's root helper (firewall rules, tunnels) only runs while the app
# does. The upstream module starts it at boot; here the launcher starts it,
# runs the GUI, and stops it when the GUI quits. Trade-off: no Windscribe
# firewall or auto-connect before the app is opened.
let
  launcher = pkgs.writeShellScriptBin "windscribe-app" ''
    systemctl start windscribe-helper.service
    /run/wrappers/bin/windscribe "$@"
    systemctl stop windscribe-helper.service
  '';
in
{
  systemd.services.windscribe-helper.wantedBy = lib.mkForce [ ];

  # Start/stop of that one unit without a password prompt.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "windscribe-helper.service" &&
          subject.user == "${vars.user.name}") {
        return polkit.Result.YES;
      }
    });
  '';

  environment.systemPackages = [ launcher ];

  # Shadows the package's windscribe.desktop (Exec=windscribe).
  home-manager.users.${vars.user.name}.xdg.desktopEntries.windscribe = {
    name = "Windscribe";
    exec = "${lib.getExe launcher} %F";
    icon = "Windscribe";
    categories = [ "Network" ];
  };
}
