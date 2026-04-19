{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "argus";
  excludeShellChecks = [ "SC2016" ]; # jq filter strings use $var syntax, not bash expansions
  runtimeInputs = with pkgs; [
    docker
    jq
    systemd
    coreutils
    util-linux
    findutils
  ];
  text = builtins.readFile ./argus.sh;
}
