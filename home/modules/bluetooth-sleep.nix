{
  pkgs,
  config,
  ...
}:

# Bluetooth off while the Mac sleeps, so headphones opened next to a closed
# MacBook (in a bag) don't connect to it. On wake, Bluetooth comes back only
# if it was on before. sleepwatcher runs the scripts on system sleep/wake.
let
  blueutil = "${pkgs.blueutil}/bin/blueutil";
  marker = "${config.xdg.stateHome}/bluetooth-was-on";
  onSleep = pkgs.writeShellScript "bluetooth-sleep" ''
    if [ "$(${blueutil} -p)" = "1" ]; then
      mkdir -p "$(dirname "${marker}")"
      touch "${marker}"
      ${blueutil} -p 0
    fi
  '';
  onWake = pkgs.writeShellScript "bluetooth-wake" ''
    if [ -e "${marker}" ]; then
      rm -f "${marker}"
      ${blueutil} -p 1
    fi
  '';
in
{
  launchd.agents.bluetooth-sleep = {
    enable = true;
    config = {
      ProgramArguments = [
        "${pkgs.sleepwatcher}/bin/sleepwatcher"
        "--sleep"
        "${onSleep}"
        "--wakeup"
        "${onWake}"
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };
  };
}
