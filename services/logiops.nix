{ pkgs, ... }:
{
  # Logitech HID++ device configuration (logid)
  # Remaps the MX Vertical top button to Super+S (toggle Spotify workspace)
  environment.systemPackages = [ pkgs.logiops ];

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
    serviceConfig = {
      ExecStart = "${pkgs.logiops}/bin/logid -c /etc/logid.cfg";
      Restart = "on-failure";
    };
  };
}
