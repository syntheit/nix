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

  # Listens for UDP audio; unsigned, so allow it through the firewall.
  matv.darwin.firewallAllowedApps = [ "${roc-recv}" ];
}
