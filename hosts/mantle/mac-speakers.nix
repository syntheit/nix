# "Mac mini speakers" output: streams to roc-recv on the mini
# (hosts/mini/speaker.nix) over the tailnet, which runs direct on the LAN.
#
# node.latency forces a ~5 ms quantum while this sink plays. With the default
# (apps ask for up to 100 ms) packets arrive in bursts and the mini's 30 ms
# jitter buffer underruns.
{ ... }:
{
  services.pipewire.extraConfig.pipewire."60-mac-speakers" = {
    "context.modules" = [
      {
        name = "libpipewire-module-roc-sink";
        args = {
          "fec.code" = "rs8m";
          "remote.ip" = "100.75.241.25"; # mac (tailnet)
          "remote.source.port" = 10001;
          "remote.repair.port" = 10002;
          "remote.control.port" = 10003;
          "sink.props" = {
            "node.name" = "mac-speakers";
            "node.description" = "Mac mini speakers";
            "node.latency" = "256/48000";
          };
        };
      }
    ];
  };
}
