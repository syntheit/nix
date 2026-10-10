# Lock/Suspend/Reboot/Shutdown desktop entries (kept after rofi was removed so
# they stay searchable in the launcher).
{ pkgs, ... }:

{
  home.file.".local/share/applications/lock.desktop".text = ''
    [Desktop Entry]
    Name=Lock
    Exec=${pkgs.hyprlock}/bin/hyprlock
    Icon=system-lock-screen
    Type=Application
    Categories=System;
  '';
  home.file.".local/share/applications/suspend.desktop".text = ''
    [Desktop Entry]
    Name=Suspend
    Exec=systemctl suspend
    Icon=system-suspend
    Type=Application
    Categories=System;
  '';
  home.file.".local/share/applications/reboot.desktop".text = ''
    [Desktop Entry]
    Name=Reboot
    Exec=systemctl reboot
    Icon=system-reboot
    Type=Application
    Categories=System;
  '';
  home.file.".local/share/applications/shutdown.desktop".text = ''
    [Desktop Entry]
    Name=Shutdown
    Exec=systemctl poweroff
    Icon=system-shutdown
    Type=Application
    Categories=System;
  '';
}
