{ pkgs, ... }:
{
  # Logitech HID++ device configuration (logid)
  # Remaps the MX Vertical top button to F20 (toggle Spotify workspace via Hyprland)
  environment.systemPackages = [ pkgs.logiops ];

  # Restart logid when a Logitech HID device appears (logid starts before the
  # mouse is ready and gives up after 5 tries without exiting)
  services.udev.extraRules = ''
    ACTION=="add|bind", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="046d", RUN+="${pkgs.systemd}/bin/systemctl restart logid.service"
  '';

  environment.etc."logid.cfg".text = ''
    devices: (
      {
        name: "MX Vertical Advanced Ergonomic Mouse";
        buttons: (
          {
            cid: 0xfd;
            action = {
              type: "Keypress";
              keys: ["KEY_F20"];
            };
          }
        );
      }
    );
  '';

  systemd.services.logid = {
    description = "Logitech Configuration Daemon";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    restartIfChanged = true;
    serviceConfig = {
      ExecStart = "${pkgs.logiops}/bin/logid -c /etc/logid.cfg";
      Restart = "always";
      RestartSec = 3;
    };
  };
}
