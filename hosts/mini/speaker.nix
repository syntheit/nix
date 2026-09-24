# Network speaker: plays mantle's "Mac mini speakers" output through the
# mini's built-in speakers. mantle's PipeWire roc-sink (hosts/mantle/
# mac-speakers.nix) streams RTP+FEC over UDP to this roc-recv.
#
# Latency: tested stable at 20 ms target over the direct LAN/tailnet path,
# 10 ms drops sessions. 30 ms leaves headroom for load spikes on mantle.
{ pkgs, lib, vars, ... }:

let
  roc-recv = "${pkgs.roc-toolkit}/bin/roc-recv";
in
{
  launchd.user.agents.roc-recv = {
    serviceConfig = {
      ProgramArguments = [
        roc-recv
        "-s" "rtp+rs8m://0.0.0.0:10001"
        "-r" "rs8m://0.0.0.0:10002"
        "-c" "rtcp://0.0.0.0:10003"
        "-o" "core://default"
        "--target-latency=30ms"
      ];
      KeepAlive = true;
      RunAtLoad = true;
      StandardErrorPath = "/Users/${vars.user.name}/Library/Logs/roc-recv.log";
    };
  };

  # The application firewall (stealth mode, modules/darwin/common.nix) drops
  # inbound UDP to unknown binaries and nix-darwin has no per-app allow
  # option. Allow the current roc-recv and drop entries for old store paths.
  system.activationScripts.postActivation.text = lib.mkAfter ''
    fw=/usr/libexec/ApplicationFirewall/socketfilterfw
    $fw --listapps | sed -n 's|^[0-9]* : \(/nix/store/[^ ]*/bin/roc-recv\) *$|\1|p' | while read -r old; do
      [ "$old" = "${roc-recv}" ] || $fw --remove "$old" >/dev/null
    done
    $fw --add ${roc-recv} >/dev/null
    $fw --unblockapp ${roc-recv} >/dev/null
  '';
}
